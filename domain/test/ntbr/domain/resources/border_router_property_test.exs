defmodule NTBR.Domain.Resources.BorderRouterPropertyTest do
  @moduledoc false
  # Property-based tests for BorderRouter resource.
  #
  # Tests infrastructure configuration, routing, and service management.
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Resources.{BorderRouter, Network}

  @moduletag :property
  @moduletag :border_router

  # ============================================================================
  # BASIC PROPERTIES - CRUD
  # ============================================================================

  property "border router can be created with valid attributes" do
    forall attrs <- valid_border_router_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      case BorderRouter.create(attrs) do
        {:ok, br} ->
          infra_match = br.infrastructure_interface == attrs.infrastructure_interface
          nat64_match = br.enable_nat64 == attrs.enable_nat64
          mdns_match = br.enable_mdns == attrs.enable_mdns
          srp_match = br.enable_srp_server == attrs.enable_srp_server

          infra_match and nat64_match and mdns_match and srp_match

        {:error, _} ->
          false
      end
    end
  end

  property "border router uses default values when not specified" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} =
        BorderRouter.create(%{
          network_id: network.id,
          on_mesh_prefix: "fd00:1234:5678:9abc::/64"
        })

      br.infrastructure_interface == "eth0" and
        br.enable_nat64 == true and
        br.enable_mdns == true and
        br.enable_srp_server == true and
        br.srp_server_port == 53 and
        br.forwarding_enabled == true and
        br.operational == false
    end
  end

  property "border router generates defaults if not provided" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} = BorderRouter.create(%{network_id: network.id})

      # Check generated on_mesh_prefix is valid ULA /64
      prefix_valid = br.on_mesh_prefix =~ ~r/^fd[0-9a-f]{10}::\/64$/i

      # Check generated backbone_interface_id is 8 bytes
      iid_valid = is_binary(br.backbone_interface_id) and byte_size(br.backbone_interface_id) == 8

      prefix_valid and iid_valid
    end
  end

  property "border router can be destroyed" do
    forall attrs <- minimal_border_router_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      {:ok, br} = BorderRouter.create(attrs)

      case BorderRouter.destroy(br) do
        :ok -> true
        {:ok, _} -> true
        {:error, _} -> false
      end
    end
  end

  # ============================================================================
  # VALIDATION PROPERTIES
  # ============================================================================

  property "on_mesh_prefix must be a /64 prefix" do
    forall prefix_len <- integer(0, 128) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      prefix = "fd00:1234:5678:9abc::/#{prefix_len}"

      result =
        BorderRouter.create(%{
          network_id: network.id,
          on_mesh_prefix: prefix
        })

      case prefix_len do
        64 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "infrastructure_interface must be valid" do
    forall iface <- interface_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        BorderRouter.create(%{
          network_id: network.id,
          on_mesh_prefix: "fd00:1234:5678:9abc::/64",
          infrastructure_interface: iface
        })

      case iface do
        "eth0" -> match?({:ok, _}, result)
        "wlan0" -> match?({:ok, _}, result)
        "usb0" -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "srp_server_port must be valid port number" do
    forall port <- integer(-100, 70000) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        BorderRouter.create(%{
          network_id: network.id,
          on_mesh_prefix: "fd00:1234:5678:9abc::/64",
          srp_server_port: port
        })

      case port do
        p when p >= 1 and p <= 65535 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "backbone_interface_id must be exactly 8 bytes" do
    forall byte_count <- integer(0, 16) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      iid = if byte_count > 0, do: :crypto.strong_rand_bytes(byte_count), else: nil

      result =
        BorderRouter.create(%{
          network_id: network.id,
          on_mesh_prefix: "fd00:1234:5678:9abc::/64",
          backbone_interface_id: iid
        })

      case byte_count do
        8 -> match?({:ok, _}, result)
        # nil is allowed (will be generated)
        0 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # ACTION PROPERTIES
  # ============================================================================

  property "can update configuration settings" do
    forall new_settings <- update_settings_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} = BorderRouter.create(%{network_id: network.id})

      result = BorderRouter.update(br, new_settings)
      match?({:ok, _}, result)
    end
  end

  property "can add external routes" do
    forall route_attrs <- external_route_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} = BorderRouter.create(%{network_id: network.id})

      {:ok, updated} =
        BorderRouter.add_external_route(
          br,
          route_attrs.prefix,
          route_attrs.preference
        )

      route_added = length(updated.external_routes) == 1
      route_match = hd(updated.external_routes).prefix == route_attrs.prefix

      route_added and route_match
    end
  end

  property "can remove external routes" do
    forall prefix <- ipv6_prefix_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} = BorderRouter.create(%{network_id: network.id})

      # Add a route
      {:ok, with_route} = BorderRouter.add_external_route(br, prefix, :high)

      # Remove the route
      {:ok, without_route} = BorderRouter.remove_external_route(with_route, prefix)

      length(without_route.external_routes) == 0
    end
  end

  property "can mark operational and not operational" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} = BorderRouter.create(%{network_id: network.id})

      # Initial state
      initial_op = br.operational == false

      # Mark operational
      {:ok, operational} = BorderRouter.mark_operational(br)
      marked_op = operational.operational == true

      # Mark not operational
      {:ok, not_operational} = BorderRouter.mark_not_operational(operational)
      marked_not_op = not_operational.operational == false

      initial_op and marked_op and marked_not_op
    end
  end

  property "operational filter returns only operational routers" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create operational router
      {:ok, br1} = BorderRouter.create(%{network_id: network.id})
      {:ok, _op_br} = BorderRouter.mark_operational(br1)

      # Create non-operational router
      {:ok, _non_op_br} = BorderRouter.create(%{network_id: network.id})

      # Query operational
      {:ok, operational_brs} = BorderRouter.operational()

      # Should find at least the operational one
      length(operational_brs) >= 1 and Enum.all?(operational_brs, & &1.operational)
    end
  end

  property "by_network filter returns routers for specific network" do
    forall _ <- integer(1, 100) do
      {:ok, network1} = Network.create(%{name: "N1", network_name: "N1", channel: 15})
      {:ok, network2} = Network.create(%{name: "N2", network_name: "N2", channel: 16})

      {:ok, br1} = BorderRouter.create(%{network_id: network1.id})
      {:ok, _br2} = BorderRouter.create(%{network_id: network2.id})

      {:ok, network1_brs} = BorderRouter.by_network(network1.id)

      length(network1_brs) == 1 and hd(network1_brs).id == br1.id
    end
  end

  # ============================================================================
  # CALCULATION PROPERTIES
  # ============================================================================

  property "has_external_connectivity calculation" do
    forall {operational, forwarding} <- {boolean(), boolean()} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} =
        BorderRouter.create(%{
          network_id: network.id,
          forwarding_enabled: forwarding
        })

      br =
        if operational do
          {:ok, op_br} = BorderRouter.mark_operational(br)
          op_br
        else
          br
        end

      br = Ash.load!(br, :has_external_connectivity)
      expected = operational and forwarding

      br.has_external_connectivity == expected
    end
  end

  property "service_count calculation counts enabled services" do
    forall {mdns, srp, nat64} <- {boolean(), boolean(), boolean()} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, br} =
        BorderRouter.create(%{
          network_id: network.id,
          enable_mdns: mdns,
          enable_srp_server: srp,
          enable_nat64: nat64
        })

      br = Ash.load!(br, :service_count)

      expected =
        [mdns, srp, nat64]
        |> Enum.count(& &1)

      br.service_count == expected
    end
  end

  # ============================================================================
  # GENERATORS
  # ============================================================================

  defp valid_border_router_attrs do
    let {iface, nat64, mdns, srp, port} <-
          {oneof(["eth0", "wlan0", "usb0"]), boolean(), boolean(), boolean(), integer(1, 65535)} do
      %{
        infrastructure_interface: iface,
        enable_nat64: nat64,
        enable_mdns: mdns,
        enable_srp_server: srp,
        srp_server_port: port,
        on_mesh_prefix: "fd00:1234:5678:9abc::/64"
      }
    end
  end

  defp minimal_border_router_attrs do
    %{
      on_mesh_prefix: "fd00:1234:5678:9abc::/64"
    }
  end

  defp interface_gen do
    oneof([
      "eth0",
      "wlan0",
      "usb0",
      # Invalid
      "eth1",
      "wlan1",
      "lo"
    ])
  end

  defp update_settings_gen do
    let {iface, nat64, mdns, srp, forwarding} <-
          {oneof(["eth0", "wlan0", "usb0"]), boolean(), boolean(), boolean(), boolean()} do
      %{
        infrastructure_interface: iface,
        enable_nat64: nat64,
        enable_mdns: mdns,
        enable_srp_server: srp,
        forwarding_enabled: forwarding
      }
    end
  end

  defp external_route_gen do
    let {prefix, preference} <- {ipv6_prefix_gen(), oneof([:high, :medium, :low])} do
      %{
        prefix: prefix,
        preference: preference
      }
    end
  end

  defp ipv6_prefix_gen do
    # Generate simple IPv6 /64 prefixes
    oneof([
      "fd00:1234:5678:1111::/64",
      "fd00:1234:5678:2222::/64",
      "fd00:abcd:ef12:3456::/64"
    ])
  end
end
