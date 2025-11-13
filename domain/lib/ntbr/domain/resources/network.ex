defmodule NTBR.Domain.Resources.Network do
  @moduledoc """
  Represents a Thread network with its configuration and state.

  Manages network credentials, topology, and operational state with a state
  machine that tracks the network's role in the Thread mesh.

  ## State Machine

  The network transitions through these states:

  ```
  :detached ──attach──> :child ──promote──> :router ──become_leader──> :leader
                         ↑                     ↑                          ↓
                         └─────demote──────────┴──────────demote─────────┘
                         ↓
                     :disabled
  ```

  ## Features

  - Auto-generates secure network credentials
  - State machine for network role tracking
  - Thread 1.3 operational dataset generation
  - Security policy management
  - Mesh-local prefix generation

  ## Security Policy

  The network's security policy includes the `rotation_time` parameter which 
  controls how often the Thread network rotates its network key. According to 
  the Thread 1.3 specification (section 8.10.1.15), `rotation_time` must meet
  the following constraints:

  - **Must be greater than 0 hours** - A value of 0 would disable key rotation,
    which is not permitted by the Thread specification
  - **Must be less than or equal to 168 hours (1 week)** - This maximum ensures
    timely key rotation for security purposes

  **Rationale:** Regular network key rotation is a fundamental security requirement
  in Thread networks. It limits the window of vulnerability if a network key is 
  compromised. The Thread specification enforces a minimum rotation frequency 
  (maximum 168-hour period) to ensure that compromised keys have a limited 
  validity window.

  **Thread 1.3 Specification Reference:** Section 8.10.1.15 - Security Policy TLV

  ## Examples

      # Create a network with auto-generated credentials
      {:ok, network} = Network.create(%{
        name: "HomeNetwork",
        network_name: "HomeThread"
      })
      
      # Network credentials are generated automatically
      network.network_key        # 16-byte random key
      network.pan_id             # Random 0x0000-0xFFFE
      network.extended_pan_id    # 8-byte random
      
      # Transition through states
      {:ok, network} = Network.attach(network)       # :detached -> :child
      {:ok, network} = Network.promote(network)      # :child -> :router
      {:ok, network} = Network.become_leader(network) # :router -> :leader
      
      # Get operational dataset
      dataset = Network.operational_dataset!(network)
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine],
    primary_read_warning?: false

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      constraints(min_length: 1, max_length: 16)
      public?(true)
    end

    attribute :network_name, :string do
      allow_nil?(false)
      constraints(min_length: 1, max_length: 16)
      public?(true)
    end

    attribute :network_key, :binary do
      allow_nil?(false)
      sensitive?(true)
      public?(true)
    end

    attribute :pan_id, :integer do
      allow_nil?(false)
      constraints(min: 0, max: 0xFFFE)
      public?(true)
    end

    attribute :extended_pan_id, :binary do
      allow_nil?(false)
      public?(true)
    end

    attribute :channel, :integer do
      allow_nil?(false)
      constraints(min: 11, max: 26)
      default(15)
      public?(true)
    end

    attribute :pskc, :binary do
      allow_nil?(true)
      sensitive?(true)
      public?(true)
    end

    attribute :mesh_local_prefix, :string do
      allow_nil?(true)
      # Thread mesh-local prefix: fdXX:XXXX:XXXX:XXXX::/64
      constraints(match: ~r/^fd[0-9a-f]{2}:[0-9a-f]{4}:[0-9a-f]{4}:[0-9a-f]{4}::\/64$/i)
      public?(true)
    end

    attribute :state, :atom do
      allow_nil?(false)
      default(:detached)
      constraints(one_of: [:detached, :child, :router, :leader, :disabled])
      public?(true)
    end

    attribute :security_policy, :map do
      allow_nil?(false)

      # Security policy configuration per Thread 1.3 specification
      # 
      # rotation_time: Network key rotation period in hours
      #   - MUST be > 0 (Thread 1.3 spec section 8.10.1.15)
      #   - MUST be <= 168 hours (1 week maximum per Thread 1.3 spec)
      #   - Setting to 0 would disable rotation (not permitted by spec)
      # 
      # Rationale: Regular key rotation limits the window of compromise if a 
      # network key is leaked. The 168-hour maximum ensures keys are rotated 
      # at least weekly for security.
      # 
      # Thread 1.3 Specification Reference: Section 8.10.1.15 - Security Policy TLV
      default(%{
        # Hours (Thread spec: max 1 week = 168 hours)
        rotation_time: 168,
        flags: %{
          obtain_network_key: true,
          native_commissioning: true,
          routers: true,
          external_commissioning: true,
          beacons: true,
          commercial_commissioning: false,
          autonomous_enrollment: false,
          network_key_provisioning: false,
          non_ccm_routers: false
        }
      })

      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :devices, NTBR.Domain.Resources.Device do
    end

    has_many :joiners, NTBR.Domain.Resources.Joiner do
    end

    has_one :border_router, NTBR.Domain.Resources.BorderRouter do
    end
  end

  calculations do
    calculate :operational_dataset, :map do
      calculation(fn records, _context ->
        Enum.map(records, fn network ->
          %{
            network_key: network.network_key,
            network_name: network.network_name,
            extended_pan_id: network.extended_pan_id,
            pan_id: network.pan_id,
            channel: network.channel,
            pskc: network.pskc,
            mesh_local_prefix: network.mesh_local_prefix || generate_mesh_local_prefix(),
            security_policy: network.security_policy,
            # Channels 11-26
            channel_mask: 0x07FFF800,
            active_timestamp: %{
              seconds: DateTime.to_unix(network.updated_at),
              ticks: 0,
              u: false
            }
          }
        end)
      end)
    end

    calculate :device_count, :integer do
      calculation(fn records, _context ->
        Enum.map(records, fn network ->
          network
          |> Ash.load!(:devices)
          |> Map.get(:devices, [])
          |> Enum.count(& &1.active)
        end)
      end)
    end

    calculate :router_count, :integer do
      calculation(fn records, _context ->
        Enum.map(records, fn network ->
          network
          |> Ash.load!(:devices)
          |> Map.get(:devices, [])
          |> Enum.count(&(&1.device_type in [:router, :leader]))
        end)
      end)
    end

    calculate :is_operational, :boolean do
      description("True if network is in an operational state (not detached/disabled)")

      calculation(fn records, _context ->
        Enum.map(records, fn network ->
          network.state in [:child, :router, :leader]
        end)
      end)
    end
  end

  state_machine do
    initial_states([:detached])
    default_initial_state(:detached)

    transitions do
      transition(:attach, from: [:detached, :disabled], to: :child)
      transition(:promote, from: :child, to: :router)
      transition(:become_leader, from: [:router, :child], to: :leader)
      transition(:demote, from: [:router, :leader], to: :child)
      transition(:detach, from: [:child, :router, :leader], to: :detached)
      transition(:disable, from: [:detached, :child, :router, :leader, :disabled], to: :disabled)
    end
  end

  actions do
    defaults([:destroy])

    create :create do
      accept([
        :name,
        :network_name,
        :network_key,
        :pan_id,
        :extended_pan_id,
        :channel,
        :pskc,
        :mesh_local_prefix,
        :security_policy
      ])

      change(fn changeset, _context ->
        changeset
        |> generate_network_key_if_missing()
        |> generate_pan_id_if_missing()
        |> generate_extended_pan_id_if_missing()
        |> generate_mesh_local_prefix_if_missing()
      end)

      validate(fn changeset, _context ->
        network_key = Ash.Changeset.get_attribute(changeset, :network_key)
        extended_pan_id = Ash.Changeset.get_attribute(changeset, :extended_pan_id)
        pskc = Ash.Changeset.get_attribute(changeset, :pskc)

        cond do
          network_key && byte_size(network_key) != 16 ->
            {:error, "Network key must be exactly 16 bytes"}

          extended_pan_id && byte_size(extended_pan_id) != 8 ->
            {:error, "Extended PAN ID must be exactly 8 bytes"}

          pskc && byte_size(pskc) != 16 ->
            {:error, "PSKc must be exactly 16 bytes"}

          true ->
            :ok
        end
      end)

      # Thread spec: Security policy rotation_time must be positive and max 1 week (168 hours)
      validate(fn changeset, _context ->
        security_policy = Ash.Changeset.get_attribute(changeset, :security_policy)

        if security_policy && is_map(security_policy) do
          rotation_time = Map.get(security_policy, :rotation_time)

          cond do
            is_nil(rotation_time) ->
              :ok

            not is_integer(rotation_time) ->
              {:error, "Security policy rotation_time must be an integer"}

            rotation_time <= 0 ->
              {:error, "Security policy rotation_time must be positive"}

            rotation_time > 168 ->
              {:error, "Security policy rotation_time must not exceed 168 hours (1 week) per Thread spec"}

            true ->
              :ok
          end
        else
          :ok
        end
      end)
    end

    read :read do
      primary?(true)
      prepare(build(sort: [created_at: :desc]))
    end

    read :by_name do
      argument(:name, :string, allow_nil?: false)
      filter(expr(name == ^arg(:name)))
    end

    read :operational do
      filter(expr(state in [:child, :router, :leader]))
    end

    read :leaders do
      filter(expr(state == :leader))
    end

    update :update do
      accept([:name, :network_name, :channel, :security_policy])
      require_atomic?(false)

      # Thread spec: Security policy rotation_time must be positive and max 1 week (168 hours)
      validate(fn changeset, _context ->
        security_policy = Ash.Changeset.get_attribute(changeset, :security_policy)

        if security_policy && is_map(security_policy) do
          rotation_time = Map.get(security_policy, :rotation_time)

          cond do
            is_nil(rotation_time) ->
              :ok

            not is_integer(rotation_time) ->
              {:error, "Security policy rotation_time must be an integer"}

            rotation_time <= 0 ->
              {:error, "Security policy rotation_time must be positive"}

            rotation_time > 168 ->
              {:error, "Security policy rotation_time must not exceed 168 hours (1 week) per Thread spec"}

            true ->
              :ok
          end
        else
          :ok
        end
      end)
    end

    update :update_credentials do
      accept([:network_key, :pskc])
      require_atomic?(false)

      validate(fn changeset, _context ->
        state = Ash.Changeset.get_attribute(changeset, :state)

        if state == :detached do
          :ok
        else
          {:error, "Network must be detached to update credentials"}
        end
      end)
    end

    # State machine transition actions
    update :attach do
      description("Attach to the Thread network - transitions to child state")
      require_atomic?(false)
      change(transition_state(:child))
    end

    update :promote do
      description("Promote from child to router role")
      require_atomic?(false)
      change(transition_state(:router))
    end

    update :become_leader do
      description("Become the leader of the Thread network")
      require_atomic?(false)
      change(transition_state(:leader))
    end

    update :demote do
      description("Demote from router or leader back to child role")
      require_atomic?(false)
      change(transition_state(:child))
    end

    update :detach do
      description("Detach from the Thread network")
      require_atomic?(false)
      change(transition_state(:detached))
    end

    update :disable do
      description("Disable the network")
      require_atomic?(false)
      change(transition_state(:disabled))
    end
  end

  code_interface do
    define(:create)
    define(:read)
    define(:list, action: :read)
    define(:by_name, args: [:name])
    define(:operational)
    define(:leaders)
    define(:update)
    define(:update_credentials)
    define(:destroy)
    define(:attach)
    define(:promote)
    define(:become_leader)
    define(:demote)
    define(:detach)
    define(:disable)
    define(:by_id, action: :read, get_by: [:id])
    # define :by_id!, action: :read, get_by: [:id], not_found_error?: true
  end

  @doc """
  Returns the operational dataset for a network.
  Automatically loads the calculation if not already loaded.
  """
  def operational_dataset(network) when is_struct(network, __MODULE__) do
    network
    |> Ash.load!(:operational_dataset)
    |> Map.get(:operational_dataset)
  end

  def operational_dataset(network_id) when is_binary(network_id) do
    {:ok, network} = read(network_id, load: [:operational_dataset])
    Map.get(network, :operational_dataset)
  end

  @doc """
  Returns the operational dataset for a network, raising on error.
  """
  def operational_dataset!(network_or_id) do
    operational_dataset(network_or_id)
  end

  # Private helper functions

  @spec generate_network_key_if_missing(Ash.Changeset.t()) :: Ash.Changeset.t()
  defp generate_network_key_if_missing(changeset) do
    if Ash.Changeset.get_attribute(changeset, :network_key) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, :network_key, :crypto.strong_rand_bytes(16))
    end
  end

  @spec generate_pan_id_if_missing(Ash.Changeset.t()) :: Ash.Changeset.t()
  defp generate_pan_id_if_missing(changeset) do
    if Ash.Changeset.get_attribute(changeset, :pan_id) do
      changeset
    else
      # Generate random PAN ID (exclude 0xFFFF which is broadcast)
      pan_id = :rand.uniform(0xFFFE)
      Ash.Changeset.change_attribute(changeset, :pan_id, pan_id)
    end
  end

  @spec generate_extended_pan_id_if_missing(Ash.Changeset.t()) :: Ash.Changeset.t()
  defp generate_extended_pan_id_if_missing(changeset) do
    if Ash.Changeset.get_attribute(changeset, :extended_pan_id) do
      changeset
    else
      Ash.Changeset.change_attribute(changeset, :extended_pan_id, :crypto.strong_rand_bytes(8))
    end
  end

  @spec generate_mesh_local_prefix_if_missing(Ash.Changeset.t()) :: Ash.Changeset.t()
  defp generate_mesh_local_prefix_if_missing(changeset) do
    if Ash.Changeset.get_attribute(changeset, :mesh_local_prefix) do
      changeset
    else
      prefix = generate_mesh_local_prefix()
      Ash.Changeset.change_attribute(changeset, :mesh_local_prefix, prefix)
    end
  end

  @spec generate_mesh_local_prefix() :: String.t()
  defp generate_mesh_local_prefix do
    # Generate Thread mesh-local prefix per RFC 4193
    # Format: fdXX:XXXX:XXXX:XXXX::/64
    # Total: 2 + 4 + 4 + 4 = 14 hex chars (7 bytes of randomness)

    # Generate 7 bytes for the segments
    random_hex = :crypto.strong_rand_bytes(7) |> Base.encode16(case: :lower)

    # Split into: fd + 2 chars + 4 chars + 4 chars + 4 chars
    <<seg1::binary-size(2), seg2::binary-size(4), seg3::binary-size(4), seg4::binary-size(4)>> =
      random_hex

    "fd#{seg1}:#{seg2}:#{seg3}:#{seg4}::/64"
  end
end
