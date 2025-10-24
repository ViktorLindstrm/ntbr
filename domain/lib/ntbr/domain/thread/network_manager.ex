defmodule NTBR.Domain.Thread.NetworkManager do
  @moduledoc """
  Manages Thread network state and coordinates with RCP via Spinel.
  
  This GenServer bridges high-level Ash domain resources with the low-level
  Spinel protocol, providing:
  
  - Network lifecycle management (attach/detach)
  - Automatic topology discovery (polling)
  - Joiner session monitoring
  - RCP event handling via PubSub
  - State synchronization between RCP and domain
  
  ## Configuration
  
      config :ntbr_domain, NTBR.Domain.Thread.NetworkManager,
        topology_interval: 30_000,  # 30 seconds
        joiner_check_interval: 10_000  # 10 seconds
  
  ## Usage
  
      # Start the manager (typically in supervision tree)
      {:ok, pid} = NetworkManager.start_link()
      
      # Attach to a network
      {:ok, network} = Network.create(%{name: "Home", network_name: "HomeNet"})
      :ok = NetworkManager.attach_network(network.id)
      
      # Detach from network
      :ok = NetworkManager.detach_network()
  """
  use GenServer
  require Logger

  alias NTBR.Domain.Spinel.Client
  alias NTBR.Domain.Resources.{Network, Device, Joiner}

  @type state :: %{
          network_id: String.t() | nil,
          border_router_id: String.t() | nil,
          topology_timer: reference() | nil,
          joiner_timer: reference() | nil,
          pending_operations: map()
        }

  # Configuration
  @topology_interval Application.compile_env(
                       :ntbr_domain,
                       [__MODULE__, :topology_interval],
                       30_000
                     )
  @joiner_check_interval Application.compile_env(
                           :ntbr_domain,
                           [__MODULE__, :joiner_check_interval],
                           10_000
                         )

  # Client API

  @doc """
  Starts the NetworkManager GenServer.
  
  Options:
    - `:name` - The name to register the GenServer (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Attaches to a Thread network using the given network ID.
  
  This will:
  1. Load network credentials from the domain
  2. Configure the RCP with network parameters
  3. Bring up the network interface
  4. Start Thread networking
  5. Begin topology discovery
  
  ## Examples
  
      iex> NetworkManager.attach_network(network_id)
      :ok
      
      iex> NetworkManager.attach_network("invalid-id")
      {:error, :network_not_found}
  """
  @spec attach_network(String.t()) :: :ok | {:error, term()}
  def attach_network(network_id) do
    GenServer.call(__MODULE__, {:attach_network, network_id}, 30_000)
  end

  @doc """
  Detaches from the current Thread network.
  
  This will:
  1. Stop Thread networking
  2. Bring down the network interface
  3. Cancel topology and joiner timers
  4. Update network state in domain
  """
  @spec detach_network() :: :ok
  def detach_network do
    GenServer.call(__MODULE__, :detach_network, 10_000)
  end

  @doc """
  Manually triggers a topology update.
  
  This is useful for testing or forcing an immediate refresh
  of device information from the RCP.
  """
  @spec update_topology() :: :ok
  def update_topology do
    GenServer.cast(__MODULE__, :update_topology)
  end

  @doc """
  Gets the current state of the NetworkManager.
  
  Returns a map containing:
    - `:network_id` - Currently attached network ID (or nil)
    - `:border_router_id` - Border router resource ID (or nil)
    - `:topology_timer` - Active topology timer reference
    - `:joiner_timer` - Active joiner check timer reference
  """
  @spec get_state() :: state()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Checks if the manager is currently attached to a network.
  """
  @spec attached?() :: boolean()
  def attached? do
    case get_state() do
      %{network_id: nil} -> false
      %{network_id: _} -> true
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      network_id: nil,
      border_router_id: nil,
      topology_timer: nil,
      joiner_timer: nil,
      pending_operations: %{}
    }

    # Subscribe to Spinel events
    Phoenix.PubSub.subscribe(NTBR.PubSub, "spinel:events")

    Logger.info("NetworkManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:attach_network, network_id}, _from, state) do
    Logger.info("Attaching to network: #{network_id}")

    case Network.by_id(network_id) do
      {:ok, network} ->
        case configure_and_start_network(network) do
          :ok ->
            # Start background tasks
            topology_timer = schedule_topology_update(@topology_interval)
            joiner_timer = schedule_joiner_check(@joiner_check_interval)

            # Update network state to attaching
            Network.by_id!(network_id)
            |> Network.attach!()

            new_state = %{
              state
              | network_id: network_id,
                topology_timer: topology_timer,
                joiner_timer: joiner_timer
            }

            Logger.info("Successfully attached to network: #{network_id}")
            {:reply, :ok, new_state}

          {:error, reason} = error ->
            Logger.error("Failed to attach to network: #{inspect(reason)}")
            {:reply, error, state}
        end

      {:error, _reason} ->
        {:reply, {:error, :network_not_found}, state}
    end
  end

  @impl true
  def handle_call(:detach_network, _from, state) do
    Logger.info("Detaching from network")

    # Stop Thread network gracefully
    with :ok <- Client.thread_stop(),
         :ok <- Client.interface_down() do
      # Cancel timers
      if state.topology_timer, do: Process.cancel_timer(state.topology_timer)
      if state.joiner_timer, do: Process.cancel_timer(state.joiner_timer)

      # Update network state
      if state.network_id do
        case Network.by_id(state.network_id) do
          {:ok, network} ->
            Network.detach!(network)

          {:error, _} ->
            Logger.warning("Network not found during detach: #{state.network_id}")
        end
      end

      new_state = %{
        state
        | network_id: nil,
          border_router_id: nil,
          topology_timer: nil,
          joiner_timer: nil
      }

      Logger.info("Successfully detached from network")
      {:reply, :ok, new_state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to detach from network: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:update_topology, state) do
    if state.network_id do
      Task.start(fn -> discover_topology(state.network_id) end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_topology, state) do
    if state.network_id do
      Logger.debug("Updating topology for network: #{state.network_id}")
      discover_topology(state.network_id)
      topology_timer = schedule_topology_update(@topology_interval)
      {:noreply, %{state | topology_timer: topology_timer}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:check_joiners, state) do
    if state.network_id do
      Logger.debug("Checking for expired joiners")
      process_expired_joiners(state.network_id)
      joiner_timer = schedule_joiner_check(@joiner_check_interval)
      {:noreply, %{state | joiner_timer: joiner_timer}}
    else
      {:noreply, state}
    end
  end

  # Spinel Event Handlers

  @impl true
  def handle_info({:spinel_event, :state_changed, spinel_state}, state) do
    Logger.info("Thread state changed to: #{inspect(spinel_state)}")

    if state.network_id do
      domain_state = map_spinel_state(spinel_state)

      case Network.by_id(state.network_id) do
        {:ok, network} ->
          Network.update!(network, %{state: domain_state})

        {:error, reason} ->
          Logger.error("Failed to update network state: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:spinel_event, :role_changed, spinel_role}, state) do
    Logger.info("Thread role changed to: #{inspect(spinel_role)}")

    if state.network_id do
      domain_role = map_spinel_role(spinel_role)

      case Network.by_id(state.network_id) do
        {:ok, network} ->
          case domain_role do
            :leader -> Network.promote!(network)
            :router -> Network.promote!(network)
            :child -> Network.demote!(network)
            _ -> :ok
          end

        {:error, reason} ->
          Logger.error("Failed to update network role: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:spinel_event, :joiner_start, eui64}, state) do
    Logger.info("Joiner started: #{Base.encode16(eui64)}")

    if state.network_id do
      case Joiner.by_eui64(eui64) do
        {:ok, joiners} when is_list(joiners) and length(joiners) > 0 ->
          joiner = List.first(joiners)
          Joiner.start!(joiner)

        _ ->
          Logger.warning("Unknown joiner attempted to join: #{Base.encode16(eui64)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:spinel_event, :joiner_complete, eui64}, state) do
    Logger.info("Joiner completed: #{Base.encode16(eui64)}")

    if state.network_id do
      case Joiner.by_eui64(eui64) do
        {:ok, joiners} when is_list(joiners) and length(joiners) > 0 ->
          joiner = List.first(joiners)
          Joiner.complete!(joiner)

        _ ->
          Logger.debug("Joiner complete event for unknown device")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  @spec configure_and_start_network(Network.t()) :: :ok | {:error, term()}
  defp configure_and_start_network(network) do
    Logger.debug("Configuring RCP with network credentials")

    with :ok <- Client.set_network_key(network.network_key),
         :ok <- Client.set_pan_id(network.pan_id),
         :ok <- Client.set_extended_pan_id(network.extended_pan_id),
         :ok <- Client.set_channel(network.channel),
         :ok <- Client.set_network_name(network.network_name),
         :ok <- Client.interface_up(),
         :ok <- Client.thread_start() do
      Logger.info("RCP configured and Thread network started")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to configure RCP: #{inspect(reason)}")
        error
    end
  end

  @spec discover_topology(String.t()) :: :ok
  defp discover_topology(network_id) do
    Logger.debug("Discovering network topology")

    # Get router table from RCP
    case Client.get_router_table() do
      {:ok, routers} ->
        update_devices(network_id, routers, :router)
        Logger.debug("Updated #{length(routers)} routers")

      {:error, reason} ->
        Logger.error("Failed to get router table: #{inspect(reason)}")
    end

    # Get child table
    case Client.get_child_table() do
      {:ok, children} ->
        update_devices(network_id, children, :end_device)
        Logger.debug("Updated #{length(children)} end devices")

      {:error, reason} ->
        Logger.error("Failed to get child table: #{inspect(reason)}")
    end

    :ok
  end

  @spec update_devices(String.t(), list(), atom()) :: :ok
  defp update_devices(network_id, device_list, default_type) do
    Enum.each(device_list, fn device_info ->
      attrs = %{
        network_id: network_id,
        rloc16: device_info[:rloc16],
        extended_address: device_info[:extended_address],
        device_type: device_info[:device_type] || default_type,
        link_quality: device_info[:link_quality],
        rssi: device_info[:rssi]
      }

      case Device.by_extended_address(attrs.extended_address) do
        {:ok, []} ->
          # Create new device
          case Device.create(attrs) do
            {:ok, device} ->
              Logger.debug("Created device: #{Base.encode16(device.extended_address)}")

            {:error, reason} ->
              Logger.error("Failed to create device: #{inspect(reason)}")
          end

        {:ok, [existing | _]} ->
          # Update existing device
          update_attrs = %{
            link_quality: attrs.link_quality,
            rssi: attrs.rssi,
            device_type: attrs.device_type
          }

          case Device.update(existing, update_attrs) do
            {:ok, _device} ->
              Device.update_last_seen!(existing)

            {:error, reason} ->
              Logger.error("Failed to update device: #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.error("Failed to query device: #{inspect(reason)}")
      end
    end)
  end

  @spec process_expired_joiners(String.t()) :: :ok
  defp process_expired_joiners(network_id) do
    case Joiner.expired_joiners() do
      {:ok, expired_joiners} ->
        expired_joiners
        |> Enum.filter(&(&1.network_id == network_id))
        |> Enum.each(fn joiner ->
          Logger.info("Expiring joiner: #{Base.encode16(joiner.eui64)}")
          Joiner.expire!(joiner)
        end)

      {:error, reason} ->
        Logger.error("Failed to query expired joiners: #{inspect(reason)}")
    end

    :ok
  end

  @spec schedule_topology_update(non_neg_integer()) :: reference()
  defp schedule_topology_update(interval) do
    Process.send_after(self(), :update_topology, interval)
  end

  @spec schedule_joiner_check(non_neg_integer()) :: reference()
  defp schedule_joiner_check(interval) do
    Process.send_after(self(), :check_joiners, interval)
  end

  # State/Role Mapping

  @spec map_spinel_state(atom()) :: atom()
  defp map_spinel_state(:disabled), do: :detached
  defp map_spinel_state(:detached), do: :detached
  defp map_spinel_state(:child), do: :child
  defp map_spinel_state(:router), do: :router
  defp map_spinel_state(:leader), do: :leader
  defp map_spinel_state(unknown), do: unknown

  @spec map_spinel_role(atom()) :: atom()
  defp map_spinel_role(:disabled), do: :detached
  defp map_spinel_role(:detached), do: :detached
  defp map_spinel_role(:child), do: :child
  defp map_spinel_role(:router), do: :router
  defp map_spinel_role(:leader), do: :leader
  defp map_spinel_role(unknown), do: unknown
end
