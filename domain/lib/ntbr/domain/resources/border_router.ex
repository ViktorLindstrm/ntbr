defmodule NTBR.Domain.Resources.BorderRouter do
  @moduledoc """
  Represents the Border Router configuration and operational state.
  Manages infrastructure interface, routing, and external connectivity.
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id

    attribute :infrastructure_interface, :string do
      allow_nil? false
      default "eth0"
    end

    attribute :on_mesh_prefix, :string do
      allow_nil? false
      constraints match: ~r/^[0-9a-f]{1,4}(:[0-9a-f]{1,4}){3}::[0-9a-f]{0,4}\/\d{1,3}$/i
    end

    attribute :nat64_prefix, :string do
      constraints match: ~r/^[0-9a-f]{1,4}(:[0-9a-f]{1,4}){2,5}::[0-9a-f]{0,4}\/\d{1,3}$/i
    end

    attribute :enable_nat64, :boolean do
      allow_nil? false
      default true
    end

    attribute :enable_dhcpv6_pd, :boolean do
      allow_nil? false
      default false
    end

    attribute :enable_mdns, :boolean do
      allow_nil? false
      default true
    end

    attribute :enable_srp_server, :boolean do
      allow_nil? false
      default true
    end

    attribute :srp_server_port, :integer do
      allow_nil? false
      default 53
      constraints min: 1, max: 65535
    end

    # Binary attributes don't support size constraints
    attribute :backbone_interface_id, :binary

    attribute :external_routes, {:array, :map} do
      default []
      # Each route: %{prefix: "fd00::/64", preference: :high, stable: true, next_hop_is_this_device: true}
    end

    attribute :forwarding_enabled, :boolean do
      allow_nil? false
      default true
    end

    attribute :operational, :boolean do
      allow_nil? false
      default false
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :network, NTBR.Domain.Resources.Network do
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:infrastructure_interface, :on_mesh_prefix, :nat64_prefix,
              :enable_nat64, :enable_dhcpv6_pd, :enable_mdns, :enable_srp_server,
              :srp_server_port, :backbone_interface_id, :external_routes,
              :forwarding_enabled, :network_id]

      change fn changeset, _context ->
        # Generate defaults if not provided
        changeset
        |> maybe_generate_on_mesh_prefix()
        |> maybe_generate_backbone_interface_id()
      end
    end

    update :update do
      accept [:infrastructure_interface, :enable_nat64, :enable_dhcpv6_pd,
              :enable_mdns, :enable_srp_server, :srp_server_port, :forwarding_enabled]
      require_atomic? false

    end

    update :add_external_route do
      argument :prefix, :string, allow_nil?: false
      argument :preference, :atom, allow_nil?: false
      argument :stable, :boolean, default: true
      argument :next_hop_is_this_device, :boolean, default: true
      require_atomic? false

      # Thread spec: Route preference must be one of :high, :medium, :low
      validate fn changeset, context ->
        preference = context.arguments.preference

        if preference in [:high, :medium, :low] do
          :ok
        else
          {:error, "Route preference must be one of: :high, :medium, :low (Thread spec)"}
        end
      end

      change fn changeset, context ->
        route = %{
          prefix: context.arguments.prefix,
          preference: context.arguments.preference,
          stable: context.arguments.stable || true,
          next_hop_is_this_device: context.arguments.next_hop_is_this_device || true
        }

        current_routes = Ash.Changeset.get_attribute(changeset, :external_routes) || []
        Ash.Changeset.change_attribute(changeset, :external_routes, [route | current_routes])
      end
    end

    update :remove_external_route do
      argument :prefix, :string, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        current_routes = Ash.Changeset.get_attribute(changeset, :external_routes) || []
        updated_routes = Enum.reject(current_routes, &(&1.prefix == context.arguments.prefix))
        Ash.Changeset.change_attribute(changeset, :external_routes, updated_routes)
      end
    end

    update :mark_operational do
      require_atomic? false
      
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :operational, true)
      end
    end

    update :mark_not_operational do
      require_atomic? false
      
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :operational, false)
      end
    end

    destroy :destroy

    # Query actions
    read :operational do
      filter expr(operational == true)
    end

    read :by_network do
      argument :network_id, :uuid, allow_nil?: false
      filter expr(network_id == ^arg(:network_id))
    end
  end

  code_interface do
    define :create
    define :update
    define :add_external_route, args: [:prefix, :preference]
    define :remove_external_route, args: [:prefix]
    define :mark_operational
    define :mark_not_operational
    define :destroy
    define :read
    define :operational
    define :by_network, args: [:network_id]
  end

  calculations do
    calculate :has_external_connectivity, :boolean, expr(
      operational and forwarding_enabled
    )

    calculate :service_count, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn br ->
          [br.enable_mdns, br.enable_srp_server, br.enable_nat64]
          |> Enum.count(& &1)
        end)
      end
    end
  end

  validations do
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :on_mesh_prefix) do
        nil ->
          :ok

        prefix ->
          if String.ends_with?(prefix, "/64") do
            :ok
          else
            {:error, field: :on_mesh_prefix, message: "must be a /64 prefix"}
          end
      end
    end

    # Validate infrastructure_interface is one of the allowed values
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :infrastructure_interface) do
        nil -> :ok
        iface when iface in ["eth0", "wlan0", "usb0"] -> :ok
        iface ->
          {:error, field: :infrastructure_interface,
           message: "must be one of: eth0, wlan0, usb0. Got: #{iface}"}
      end
    end

    # Validate backbone_interface_id is exactly 8 bytes if present
    validate fn changeset, _context ->
      case Ash.Changeset.get_attribute(changeset, :backbone_interface_id) do
        nil -> :ok
        iid when is_binary(iid) and byte_size(iid) == 8 -> :ok
        iid when is_binary(iid) ->
          {:error, field: :backbone_interface_id, message: "must be exactly 8 bytes, got #{byte_size(iid)}"}
        _ -> {:error, field: :backbone_interface_id, message: "must be a binary"}
      end
    end
  end

  # Private helper functions
  defp maybe_generate_on_mesh_prefix(changeset) do
    case Ash.Changeset.get_attribute(changeset, :on_mesh_prefix) do
      nil ->
        # Generate a ULA prefix: fd + 40 random bits + ::/64
        random_hex =
          :crypto.strong_rand_bytes(5)
          |> Base.encode16(case: :lower)
          |> String.slice(0..9)

        prefix = "fd#{random_hex}::/64"
        Ash.Changeset.change_attribute(changeset, :on_mesh_prefix, prefix)

      _ ->
        changeset
    end
  end

  defp maybe_generate_backbone_interface_id(changeset) do
    case Ash.Changeset.get_attribute(changeset, :backbone_interface_id) do
      nil ->
        Ash.Changeset.change_attribute(
          changeset,
          :backbone_interface_id,
          :crypto.strong_rand_bytes(8)
        )

      _ ->
        changeset
    end
  end
end
