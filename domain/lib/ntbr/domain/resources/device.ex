defmodule NTBR.Domain.Resources.Device do
  @moduledoc """
  Represents a device in the Thread network.
  
  Tracks all devices participating in the mesh, including routers, end devices,
  and their parent-child relationships. Monitors link quality, connectivity,
  and device capabilities.
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id

    attribute :rloc16, :integer do
      allow_nil? false
      constraints min: 0, max: 0xFFFF
      public? true
    end

    attribute :extended_address, :binary do
      allow_nil? false
      public? true
    end

    attribute :ipv6_addresses, {:array, :string} do
      default []
      public? true
    end

    attribute :device_type, :atom do
      allow_nil? false
      constraints one_of: [:end_device, :router, :leader, :reed]
      default :end_device
      public? true
    end

    attribute :mode, :map do
      default %{
        rx_on_when_idle: false,
        secure_data_requests: true,
        full_network_data: false,
        full_thread_device: false
      }
      public? true
    end

    attribute :link_quality, :integer do
      allow_nil? true
      constraints min: 0, max: 3
      public? true
    end

    attribute :rssi, :integer do
      allow_nil? true
      constraints min: -128, max: 0
      public? true
    end

    attribute :version, :integer do
      constraints min: 1, max: 4
      default 3
      public? true
    end

    attribute :last_seen, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :network, NTBR.Domain.Resources.Network do
      allow_nil? false
    end

    belongs_to :parent, NTBR.Domain.Resources.Device do
      allow_nil? true
    end

    has_many :children, NTBR.Domain.Resources.Device do
      destination_attribute :parent_id
    end
  end

  calculations do
    calculate :age_seconds, :integer do
      calculation fn records, _context ->
        now = DateTime.utc_now()
        Enum.map(records, fn device ->
          DateTime.diff(now, device.last_seen, :second)
        end)
      end
    end

    calculate :is_stale, :boolean do
      argument :threshold_seconds, :integer do
        allow_nil? false
        default 300
      end

      calculation fn records, %{arguments: %{threshold_seconds: threshold}} ->
        now = DateTime.utc_now()
        
        Enum.map(records, fn device ->
          age = DateTime.diff(now, device.last_seen, :second)
          age > threshold
        end)
      end
    end

    calculate :is_router_capable, :boolean do
      calculation fn records, _context ->
        Enum.map(records, fn device ->
          device.mode[:full_thread_device] == true or
            device.device_type in [:router, :leader, :reed]
        end)
      end
    end

    calculate :child_count, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn device ->
          device
          |> Ash.load!(:children)
          |> Map.get(:children, [])
          |> length()
        end)
      end
    end
  end

  actions do
    defaults [:destroy]

    create :create do
      accept [:network_id, :rloc16, :extended_address, :ipv6_addresses,
              :device_type, :mode, :link_quality, :rssi, :version, :parent_id]

      validate fn changeset, _context ->
        extended_address = Ash.Changeset.get_attribute(changeset, :extended_address)

        if extended_address && byte_size(extended_address) != 8 do
          {:error, "Extended address must be exactly 8 bytes"}
        else
          :ok
        end
      end

      # Prevent self-reference in parent relationship
      validate fn changeset, _context ->
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)
        device_id = Ash.Changeset.get_attribute(changeset, :id)

        if parent_id && device_id && parent_id == device_id do
          {:error, "Device cannot be its own parent"}
        else
          :ok
        end
      end

      # Thread spec: Only routers and leaders can have children
      validate fn changeset, _context ->
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)

        if parent_id do
          case Ash.get(__MODULE__, parent_id) do
            {:ok, parent} ->
              if parent.device_type in [:router, :leader] do
                :ok
              else
                {:error, "Only routers and leaders can have children (Thread spec constraint)"}
              end
            _ ->
              :ok
          end
        else
          :ok
        end
      end
    end

    read :read do
      primary? true
      prepare build(sort: [last_seen: :desc])
    end

    read :active_devices do
      filter expr(active == true)
      prepare build(sort: [last_seen: :desc])
    end

    read :by_network do
      argument :network_id, :uuid, allow_nil?: false
      filter expr(network_id == ^arg(:network_id))
      prepare build(sort: [last_seen: :desc])
    end

    read :routers do
      argument :network_id, :uuid, allow_nil?: true
      
      filter expr(
        device_type in [:router, :leader] and
        if not is_nil(^arg(:network_id)) do
          network_id == ^arg(:network_id)
        else
          true
        end
      )
    end

    read :end_devices do
      argument :network_id, :uuid, allow_nil?: true
      
      filter expr(
        device_type == :end_device and
        if not is_nil(^arg(:network_id)) do
          network_id == ^arg(:network_id)
        else
          true
        end
      )
    end

    read :by_extended_address do
      argument :extended_address, :binary, allow_nil?: false
      filter expr(extended_address == ^arg(:extended_address))
    end

    read :by_rloc16 do
      argument :rloc16, :integer, allow_nil?: false
      filter expr(rloc16 == ^arg(:rloc16))
    end

    read :stale_devices do
      argument :network_id, :uuid, allow_nil?: true
      argument :timeout_seconds, :integer, default: 300
      
      filter expr(
        last_seen < ago(^arg(:timeout_seconds), :second) and
        active == true and
        if not is_nil(^arg(:network_id)) do
          network_id == ^arg(:network_id)
        else
          true
        end
      )
    end

    read :children_of do
      argument :parent_id, :uuid, allow_nil?: false
      filter expr(parent_id == ^arg(:parent_id) and active == true)
    end

    read :orphaned do
      argument :network_id, :uuid, allow_nil?: false
      
      filter expr(
        network_id == ^arg(:network_id) and
        not is_nil(parent_id) and
        active == true
      )
    end

    update :update do
      accept [:ipv6_addresses, :device_type, :mode, :link_quality, :rssi,
              :parent_id, :version, :active]
      require_atomic?(false)

      # Prevent self-reference in parent relationship
      validate fn changeset, _context ->
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)
        device_id = changeset.data.id

        if parent_id && device_id && parent_id == device_id do
          {:error, "Device cannot be its own parent"}
        else
          :ok
        end
      end
    end

    update :update_last_seen do
      require_atomic? false
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_seen, DateTime.utc_now())
      end
    end

    update :deactivate do
      require_atomic? false
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :active, false)
      end
    end

    update :update_link_metrics do
      accept [:link_quality, :rssi]
      require_atomic? false
      
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_seen, DateTime.utc_now())
      end
    end
  end

  identities do
    identity :unique_extended_address, [:network_id, :extended_address],
      pre_check_with: NTBR.Domain

    identity :unique_rloc16, [:network_id, :rloc16],
      pre_check_with: NTBR.Domain
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :active_devices
    define :by_network, args: [:network_id]
    define :routers, args: [{:optional, :network_id}]
    define :end_devices, args: [{:optional, :network_id}]
    define :by_extended_address, args: [:extended_address]
    define :by_rloc16, args: [:rloc16]
    define :stale_devices, args: [{:optional, :network_id}, {:optional, :timeout_seconds}]
    define :children_of, args: [:parent_id]
    define :orphaned, args: [:network_id]
    define :update_last_seen
    define :deactivate
    define :update_link_metrics
  end
end
