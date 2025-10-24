defmodule NTBR.Domain.Spinel.Client do
  @moduledoc """
  GenServer wrapper for Spinel RCP communication.
  
  This module provides a high-level API for communicating with the
  ESP32-C6 RCP over UART using the Spinel protocol. It handles:
  
  - UART connection management
  - Request/response correlation using TIDs
  - Async event broadcasting via PubSub
  - Frame encoding/decoding
  - Error handling and retries
  
  ## Configuration
  
      config :ntbr_domain, NTBR.Domain.Spinel.Client,
        uart_device: "ttyACM0",
        uart_speed: 460_800,
        uart_adapter: Circuits.UART,  # Can be mocked for testing
        response_timeout: 5_000
  
  ## Usage
  
      # Start the client (typically in supervision tree)
      {:ok, pid} = Client.start_link()
      
      # Configure network
      :ok = Client.set_channel(15)
      :ok = Client.set_network_key(<<0, 1, 2, ...>>)
      :ok = Client.interface_up()
      :ok = Client.thread_start()
      
      # Query state
      {:ok, channel} = Client.get_channel()
      {:ok, role} = Client.get_net_role()
  """
  use GenServer
  require Logger

  import Bitwise
  alias NTBR.Domain.Spinel.{Frame, Property, DataEncoder}

  @type state :: %{
          uart: any(),
          uart_adapter: module(),
          next_tid: 0..15,
          pending: %{0..15 => {reference(), GenServer.from()}},
          frame_buffer: binary()
        }

  # Configuration
  @uart_device Application.compile_env(:ntbr_domain, [__MODULE__, :uart_device], "ttyACM0")
  @uart_speed Application.compile_env(:ntbr_domain, [__MODULE__, :uart_speed], 460_800)
  @uart_adapter Application.compile_env(:ntbr_domain, [__MODULE__, :uart_adapter], Circuits.UART)
  @response_timeout Application.compile_env(
                      :ntbr_domain,
                      [__MODULE__, :response_timeout],
                      5_000
                    )

  # Client API

  @doc """
  Starts the Spinel client GenServer.
  
  Options:
    - `:name` - The name to register the GenServer (default: `__MODULE__`)
    - `:uart_device` - UART device path (default: "ttyACM0")
    - `:uart_speed` - UART baud rate (default: 460_800)
    - `:uart_adapter` - UART module to use (default: Circuits.UART)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # Network Configuration API

  @doc "Set the network key (16 bytes)"
  @spec set_network_key(binary()) :: :ok | {:error, term()}
  def set_network_key(key) when byte_size(key) == 16 do
    set_property(Property.net_network_key(), key)
  end

  @doc "Set the PAN ID (0-0xFFFF)"
  @spec set_pan_id(non_neg_integer()) :: :ok | {:error, term()}
  def set_pan_id(pan_id) when pan_id >= 0 and pan_id <= 0xFFFF do
    value = DataEncoder.encode_uint16(pan_id)
    set_property(Property.mac_pan_id(), value)
  end

  @doc "Set the Extended PAN ID (8 bytes)"
  @spec set_extended_pan_id(binary()) :: :ok | {:error, term()}
  def set_extended_pan_id(xpan) when byte_size(xpan) == 8 do
    set_property(Property.net_xpanid(), xpan)
  end

  @doc "Set the channel (11-26)"
  @spec set_channel(11..26) :: :ok | {:error, term()}
  def set_channel(channel) when channel >= 11 and channel <= 26 do
    value = DataEncoder.encode_uint8(channel)
    set_property(Property.phy_chan(), value)
  end

  @doc "Set the network name (max 16 characters)"
  @spec set_network_name(String.t()) :: :ok | {:error, term()}
  def set_network_name(name) when is_binary(name) do
    set_property(Property.net_network_name(), name)
  end

  # Network Control API

  @doc "Bring the network interface up"
  @spec interface_up() :: :ok | {:error, term()}
  def interface_up do
    set_property(Property.net_if_up(), <<1>>)
  end

  @doc "Bring the network interface down"
  @spec interface_down() :: :ok | {:error, term()}
  def interface_down do
    set_property(Property.net_if_up(), <<0>>)
  end

  @doc "Start Thread networking"
  @spec thread_start() :: :ok | {:error, term()}
  def thread_start do
    set_property(Property.net_stack_up(), <<1>>)
  end

  @doc "Stop Thread networking"
  @spec thread_stop() :: :ok | {:error, term()}
  def thread_stop do
    set_property(Property.net_stack_up(), <<0>>)
  end

  @doc "Reset the RCP"
  @spec reset() :: :ok | {:error, term()}
  def reset do
    GenServer.call(__MODULE__, :reset, @response_timeout)
  end

  # Query API

  @doc "Get the current channel"
  @spec get_channel() :: {:ok, non_neg_integer()} | {:error, term()}
  def get_channel do
    case get_property(Property.phy_chan()) do
      {:ok, <<channel::8>>} -> {:ok, channel}
      error -> error
    end
  end

  @doc "Get the current network role"
  @spec get_net_role() :: {:ok, atom()} | {:error, term()}
  def get_net_role do
    case get_property(Property.net_role()) do
      {:ok, <<role::8>>} -> {:ok, decode_role(role)}
      error -> error
    end
  end

  @doc "Get the router table"
  @spec get_router_table() :: {:ok, list()} | {:error, term()}
  def get_router_table do
    case get_property(Property.thread_router_table()) do
      {:ok, data} -> {:ok, decode_router_table(data)}
      error -> error
    end
  end

  @doc "Get the child table"
  @spec get_child_table() :: {:ok, list()} | {:error, term()}
  def get_child_table do
    case get_property(Property.thread_child_table()) do
      {:ok, data} -> {:ok, decode_child_table(data)}
      error -> error
    end
  end

  @doc "Get NCP version"
  @spec get_ncp_version() :: {:ok, String.t()} | {:error, term()}
  def get_ncp_version do
    case get_property(Property.ncp_version()) do
      {:ok, version} -> {:ok, to_string(version)}
      error -> error
    end
  end

  @doc "Get NCP capabilities"
  @spec get_caps() :: {:ok, list()} | {:error, term()}
  def get_caps do
    get_property(Property.caps())
  end

  # Generic property access

  @doc "Set a property value"
  @spec set_property(Property.property(), binary()) :: :ok | {:error, term()}
  def set_property(property, value) when is_binary(value) do
    GenServer.call(__MODULE__, {:set_property, property, value}, @response_timeout)
  end

  @doc "Get a property value"
  @spec get_property(Property.property()) :: {:ok, binary()} | {:error, term()}
  def get_property(property) do
    GenServer.call(__MODULE__, {:get_property, property}, @response_timeout)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    uart_device = Keyword.get(opts, :uart_device, @uart_device)
    uart_speed = Keyword.get(opts, :uart_speed, @uart_speed)
    uart_adapter = Keyword.get(opts, :uart_adapter, @uart_adapter)

    Logger.info("Starting Spinel client on #{uart_device} @ #{uart_speed} baud")

    case uart_adapter.start_link() do
      {:ok, uart} ->
        case uart_adapter.open(uart, uart_device,
               speed: uart_speed,
               active: true,
               framing: Circuits.UART.Framing.None
             ) do
          :ok ->
            state = %{
              uart: uart,
              uart_adapter: uart_adapter,
              next_tid: 0,
              pending: %{},
              frame_buffer: <<>>
            }

            Logger.info("Spinel client connected to #{uart_device}")
            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to open UART: #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to start UART: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:reset, from, state) do
    frame = Frame.reset(tid: state.next_tid)
    send_frame(frame, from, state)
  end

  @impl true
  def handle_call({:set_property, property, value}, from, state) do
    frame = Frame.prop_value_set(property, value, tid: state.next_tid)
    send_frame(frame, from, state)
  end

  @impl true
  def handle_call({:get_property, property}, from, state) do
    frame = Frame.prop_value_get(property, tid: state.next_tid)
    send_frame(frame, from, state)
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) do
    # Accumulate data in buffer
    buffer = state.frame_buffer <> data

    # Try to decode frames from buffer
    {frames, remaining} = decode_frames(buffer)

    # Process each decoded frame
    new_state =
      Enum.reduce(frames, state, fn frame, acc_state ->
        handle_frame(frame, acc_state)
      end)

    {:noreply, %{new_state | frame_buffer: remaining}}
  end

  @impl true
  def handle_info({:timeout, tid}, state) do
    case Map.get(state.pending, tid) do
      {_timer_ref, from} ->
        GenServer.reply(from, {:error, :timeout})
        new_pending = Map.delete(state.pending, tid)
        {:noreply, %{state | pending: new_pending}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  @spec send_frame(Frame.t(), GenServer.from(), state()) ::
          {:noreply, state()} | {:reply, term(), state()}
  defp send_frame(frame, from, state) do
    encoded = Frame.encode(frame)
    tid = frame.tid

    case state.uart_adapter.write(state.uart, encoded) do
      :ok ->
        # Set timeout for response
        timer_ref = Process.send_after(self(), {:timeout, tid}, @response_timeout)

        # Store pending request
        new_pending = Map.put(state.pending, tid, {timer_ref, from})

        # Increment TID (wraps at 16)
        next_tid = rem(state.next_tid + 1, 16)

        new_state = %{state | next_tid: next_tid, pending: new_pending}
        {:noreply, new_state}

      {:error, reason} = error ->
        Logger.error("Failed to write to UART: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @spec handle_frame(Frame.t(), state()) :: state()
  defp handle_frame(frame, state) do
    tid = Frame.extract_tid(frame.header)

    case Map.get(state.pending, tid) do
      {timer_ref, from} ->
        # Cancel timeout
        Process.cancel_timer(timer_ref)

        # Reply to caller
        case frame.command do
          :prop_value_is ->
            # Successful response
            case Frame.extract_value(frame) do
              {:ok, value} ->
                GenServer.reply(from, {:ok, value})

              {:error, _} = error ->
                GenServer.reply(from, error)
            end

          :last_status ->
            # Error response
            <<status::8, _rest::binary>> = frame.payload
            GenServer.reply(from, {:error, decode_status(status)})

          _ ->
            GenServer.reply(from, {:ok, frame.payload})
        end

        # Remove from pending
        new_pending = Map.delete(state.pending, tid)
        %{state | pending: new_pending}

      nil ->
        # Unsolicited frame - might be an event
        handle_event(frame, state)
        state
    end
  end

  @spec handle_event(Frame.t(), state()) :: :ok
  defp handle_event(frame, _state) do
    case frame.command do
      :prop_value_is ->
        property = Frame.extract_property(frame)
        {:ok, value} = Frame.extract_value(frame)

        case property do
          :net_state ->
            <<state_byte::8>> = value
            state_atom = decode_state(state_byte)
            broadcast_event(:state_changed, state_atom)

          :net_role ->
            <<role_byte::8>> = value
            role_atom = decode_role(role_byte)
            broadcast_event(:role_changed, role_atom)

          _ ->
            Logger.debug("Unsolicited property update: #{inspect(property)}")
        end

      :prop_value_inserted ->
        property = Frame.extract_property(frame)
        Logger.debug("Property inserted: #{inspect(property)}")

      :prop_value_removed ->
        property = Frame.extract_property(frame)
        Logger.debug("Property removed: #{inspect(property)}")

      _ ->
        Logger.debug("Unhandled frame: #{inspect(frame)}")
    end
  end

  @spec broadcast_event(atom(), term()) :: :ok
  defp broadcast_event(event_type, data) do
    Phoenix.PubSub.broadcast(
      NTBR.PubSub,
      "spinel:events",
      {:spinel_event, event_type, data}
    )
  end

  @spec decode_frames(binary()) :: {list(Frame.t()), binary()}
  defp decode_frames(buffer) do
    decode_frames_acc(buffer, [])
  end

  @spec decode_frames_acc(binary(), list(Frame.t())) :: {list(Frame.t()), binary()}
  defp decode_frames_acc(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp decode_frames_acc(buffer, acc) do
    # Try to decode a frame
    case Frame.decode(buffer) do
      {:ok, frame} ->
        # Calculate frame length
        frame_bytes = Frame.encode(frame)
        frame_length = byte_size(frame_bytes)

        # Remove frame from buffer and continue
        <<_consumed::binary-size(frame_length), rest::binary>> = buffer
        decode_frames_acc(rest, [frame | acc])

      {:error, :invalid_frame} ->
        # Not enough data yet, or corrupted frame
        if byte_size(buffer) > 2 do
          # Try to find next valid frame start
          case find_frame_start(buffer) do
            {:ok, offset} ->
              <<_skip::binary-size(offset), rest::binary>> = buffer
              decode_frames_acc(rest, acc)

            :not_found ->
              # No valid frame start found, keep buffer as is
              {Enum.reverse(acc), buffer}
          end
        else
          # Not enough data, keep buffer
          {Enum.reverse(acc), buffer}
        end
    end
  end

  @spec find_frame_start(binary()) :: {:ok, non_neg_integer()} | :not_found
  defp find_frame_start(buffer) do
    # Look for header byte (bit 7 set)
    find_frame_start(buffer, 0)
  end

  defp find_frame_start(<<>>, _offset), do: :not_found

  defp find_frame_start(<<byte::8, rest::binary>>, offset) do
    if (byte &&& 0x80) == 0x80 do
      {:ok, offset}
    else
      find_frame_start(rest, offset + 1)
    end
  end

  # Decoders

  @spec decode_state(non_neg_integer()) :: atom()
  defp decode_state(0), do: :uninitialized
  defp decode_state(1), do: :fault
  defp decode_state(2), do: :upgrading
  defp decode_state(3), do: :deep_sleep
  defp decode_state(4), do: :offline
  defp decode_state(5), do: :commissioned
  defp decode_state(6), do: :associating
  defp decode_state(7), do: :credentials_needed
  defp decode_state(8), do: :associated
  defp decode_state(9), do: :isolated
  defp decode_state(_), do: :unknown

  @spec decode_role(non_neg_integer()) :: atom()
  defp decode_role(0), do: :disabled
  defp decode_role(1), do: :detached
  defp decode_role(2), do: :child
  defp decode_role(3), do: :router
  defp decode_role(4), do: :leader
  defp decode_role(_), do: :unknown

  @spec decode_status(non_neg_integer()) :: atom()
  defp decode_status(0), do: :ok
  defp decode_status(1), do: :failure
  defp decode_status(2), do: :unimplemented
  defp decode_status(3), do: :invalid_argument
  defp decode_status(4), do: :invalid_state
  defp decode_status(5), do: :invalid_command
  defp decode_status(6), do: :invalid_interface
  defp decode_status(7), do: :internal_error
  defp decode_status(8), do: :security_error
  defp decode_status(9), do: :parse_error
  defp decode_status(10), do: :in_progress
  defp decode_status(11), do: :nomem
  defp decode_status(12), do: :busy
  defp decode_status(13), do: :property_not_found
  defp decode_status(14), do: :dropped
  defp decode_status(15), do: :empty
  defp decode_status(16), do: :cmd_too_big
  defp decode_status(17), do: :no_ack
  defp decode_status(18), do: :cca_failure
  defp decode_status(19), do: :already
  defp decode_status(20), do: :item_not_found
  defp decode_status(21), do: :invalid_command_for_prop
  defp decode_status(_), do: :unknown

  @spec decode_router_table(binary()) :: list(map())
  defp decode_router_table(data) do
    # Parse router table entries
    # Format: Each entry is variable length with router info
    parse_router_entries(data, [])
  end

  @spec parse_router_entries(binary(), list(map())) :: list(map())
  defp parse_router_entries(<<>>, acc), do: Enum.reverse(acc)

  defp parse_router_entries(data, acc) do
    # Router entry format (example, adjust based on actual Spinel format):
    # RLOC16 (2 bytes) + RouterID (1 byte) + NextHop (1 byte) + PathCost (1 byte) + LinkQuality (1 byte) + Age (1 byte)
    case data do
      <<rloc16::16, router_id::8, next_hop::8, path_cost::8, link_quality::8, age::8,
        rest::binary>> ->
        entry = %{
          rloc16: rloc16,
          router_id: router_id,
          next_hop: next_hop,
          path_cost: path_cost,
          link_quality: link_quality,
          age: age,
          device_type: :router
        }

        parse_router_entries(rest, [entry | acc])

      _ ->
        # Not enough data or malformed
        Enum.reverse(acc)
    end
  end

  @spec decode_child_table(binary()) :: list(map())
  defp decode_child_table(data) do
    # Parse child table entries
    parse_child_entries(data, [])
  end

  @spec parse_child_entries(binary(), list(map())) :: list(map())
  defp parse_child_entries(<<>>, acc), do: Enum.reverse(acc)

  defp parse_child_entries(data, acc) do
    # Child entry format (example):
    # Extended Address (8 bytes) + RLOC16 (2 bytes) + Mode (1 byte) + LinkQuality (1 byte) + RSSI (1 byte signed)
    case data do
      <<ext_addr::binary-size(8), rloc16::16, mode::8, link_quality::8, rssi::signed-8,
        rest::binary>> ->
        entry = %{
          extended_address: ext_addr,
          rloc16: rloc16,
          mode: mode,
          link_quality: link_quality,
          rssi: rssi,
          device_type: if((mode &&& 0x02) != 0, do: :router, else: :end_device)
        }

        parse_child_entries(rest, [entry | acc])

      _ ->
        # Not enough data or malformed
        Enum.reverse(acc)
    end
  end
end
