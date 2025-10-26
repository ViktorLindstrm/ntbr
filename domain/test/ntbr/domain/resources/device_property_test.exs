defmodule NTBR.Domain.Resources.DevicePropertyTest do
  @moduledoc false
  # Property-based tests for Device resource.
  #
  # Tests device management, topology, and link quality tracking.
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Resources.{Device, Network}

  @moduletag :property
  @moduletag :resources
  @moduletag :device

  # ============================================================================
  # BASIC PROPERTIES - CRUD
  # ============================================================================

  property "device can be created with valid attributes" do
    forall attrs <- valid_device_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      case Device.create(attrs) do
        {:ok, device} ->
          rloc_match = device.rloc16 == attrs.rloc16
          eui_match = device.extended_address == attrs.extended_address
          type_match = device.device_type == attrs.device_type
          active_match = device.active == true

          rloc_match and eui_match and type_match and active_match

        {:error, _} ->
          false
      end
    end
  end

  property "device uses default values when not specified" do
    forall {rloc, eui} <- {integer(0, 0xFFFF), eui64_gen()} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: rloc,
          extended_address: eui
        })

      device.device_type == :end_device and
        device.active == true and
        device.version == 3 and
        not is_nil(device.last_seen)
    end
  end

  property "device can be destroyed" do
    forall attrs <- minimal_device_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      {:ok, device} = Device.create(attrs)

      case Device.destroy(device) do
        :ok -> true
        {:ok, _} -> true
        {:error, _} -> false
      end
    end
  end

  # ============================================================================
  # VALIDATION PROPERTIES
  # ============================================================================

  property "rloc16 must be within valid range" do
    forall rloc <- integer(-100, 0x10000 + 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: rloc,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      case rloc do
        r when r >= 0 and r <= 0xFFFF -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "extended_address must be exactly 8 bytes" do
    forall byte_count <- integer(0, 16) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      eui = if byte_count > 0, do: :crypto.strong_rand_bytes(byte_count), else: <<>>

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: eui
        })

      case byte_count do
        8 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "link_quality must be 0-3 if provided" do
    forall lq <- oneof([nil, integer(-5, 10)]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          link_quality: lq
        })

      case lq do
        nil -> match?({:ok, _}, result)
        q when q >= 0 and q <= 3 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "rssi must be -128 to 0 if provided" do
    forall rssi <- oneof([nil, integer(-200, 50)]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          rssi: rssi
        })

      case rssi do
        nil -> match?({:ok, _}, result)
        r when r >= -128 and r <= 0 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "version must be 1-4" do
    forall version <- integer(0, 5) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          version: version
        })

      case version do
        v when v >= 1 and v <= 4 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "device_type must be valid" do
    forall device_type <- device_type_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: device_type
        })

      case device_type do
        dt when dt in [:end_device, :router, :leader, :reed] -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # ACTION PROPERTIES
  # ============================================================================

  property "can update device attributes" do
    forall update_attrs <- update_device_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      result = Device.update(device, update_attrs)
      match?({:ok, _}, result)
    end
  end

  property "update_last_seen updates timestamp" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      original_time = device.last_seen

      # Small delay to ensure time difference
      Process.sleep(10)

      {:ok, updated} = Device.update_last_seen(device)

      DateTime.compare(updated.last_seen, original_time) == :gt
    end
  end

  property "deactivate marks device as inactive" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      initial_active = device.active == true

      {:ok, deactivated} = Device.deactivate(device)
      now_inactive = deactivated.active == false

      initial_active and now_inactive
    end
  end

  property "update_link_metrics updates metrics and timestamp" do
    forall {lq, rssi} <- {integer(0, 3), integer(-128, 0)} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      original_time = device.last_seen

      # Small delay
      Process.sleep(10)

      {:ok, updated} =
        Device.update_link_metrics(device, %{
          link_quality: lq,
          rssi: rssi
        })

      lq_match = updated.link_quality == lq
      rssi_match = updated.rssi == rssi
      time_updated = DateTime.compare(updated.last_seen, original_time) == :gt

      lq_match and rssi_match and time_updated
    end
  end

  # ============================================================================
  # READ ACTION PROPERTIES
  # ============================================================================

  property "active_devices returns only active devices" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create active device
      {:ok, active} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      # Create and deactivate device
      {:ok, device2} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x5678,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      {:ok, _inactive} = Device.deactivate(device2)

      {:ok, active_devices} = Device.active_devices()

      # Should include active device
      active_ids = Enum.map(active_devices, & &1.id)
      active.id in active_ids and Enum.all?(active_devices, & &1.active)
    end
  end

  property "by_network returns devices for specific network" do
    forall _ <- integer(1, 100) do
      {:ok, network1} = Network.create(%{name: "N1", network_name: "N1", channel: 15})
      {:ok, network2} = Network.create(%{name: "N2", network_name: "N2", channel: 16})

      {:ok, device1} =
        Device.create(%{
          network_id: network1.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      {:ok, _device2} =
        Device.create(%{
          network_id: network2.id,
          rloc16: 0x5678,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      {:ok, network1_devices} = Device.by_network(network1.id)

      length(network1_devices) == 1 and hd(network1_devices).id == device1.id
    end
  end

  property "routers returns only router and leader devices" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, router} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :router
        })

      {:ok, _end_device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x5678,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :end_device
        })

      {:ok, routers} = Device.routers()

      router_ids = Enum.map(routers, & &1.id)
      router.id in router_ids and Enum.all?(routers, &(&1.device_type in [:router, :leader]))
    end
  end

  property "end_devices returns only end devices" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, _router} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :router
        })

      {:ok, end_device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x5678,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :end_device
        })

      {:ok, end_devices} = Device.end_devices()

      end_device_ids = Enum.map(end_devices, & &1.id)
      end_device.id in end_device_ids and Enum.all?(end_devices, &(&1.device_type == :end_device))
    end
  end

  property "by_extended_address finds device" do
    forall eui <- eui64_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: eui
        })

      {:ok, found} = Device.by_extended_address(eui)

      found != [] and hd(found).id == device.id
    end
  end

  property "by_rloc16 finds device" do
    forall rloc <- integer(0, 0xFFFF) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: rloc,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      {:ok, found} = Device.by_rloc16(rloc)

      found != [] and hd(found).id == device.id
    end
  end

  # ============================================================================
  # TOPOLOGY PROPERTIES
  # ============================================================================

  property "device can have parent relationship" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create parent (router)
      {:ok, parent} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1000,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :router
        })

      # Create child (end device)
      {:ok, child} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1001,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :end_device,
          parent_id: parent.id
        })

      child.parent_id == parent.id
    end
  end

  property "children_of returns child devices" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create parent
      {:ok, parent} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1000,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :router
        })

      # Create children
      {:ok, child1} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1001,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :end_device,
          parent_id: parent.id
        })

      {:ok, child2} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1002,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: :end_device,
          parent_id: parent.id
        })

      {:ok, children} = Device.children_of(parent.id)

      child_ids = Enum.map(children, & &1.id)
      child1.id in child_ids and child2.id in child_ids and length(children) == 2
    end
  end

  # ============================================================================
  # CALCULATION PROPERTIES
  # ============================================================================

  property "age_seconds calculation" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      device = Ash.load!(device, :age_seconds)

      # Age should be very small (just created)
      is_integer(device.age_seconds) and device.age_seconds >= 0 and device.age_seconds < 5
    end
  end

  property "is_router_capable calculation" do
    forall device_type <- oneof([:end_device, :router, :leader, :reed]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, device} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: :crypto.strong_rand_bytes(8),
          device_type: device_type
        })

      device = Ash.load!(device, :is_router_capable)

      expected = device_type in [:router, :leader, :reed]
      device.is_router_capable == expected
    end
  end

  # ============================================================================
  # IDENTITY PROPERTIES
  # ============================================================================

  property "extended_address must be unique per network" do
    forall eui <- eui64_gen() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, _device1} =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x1234,
          extended_address: eui
        })

      # Try to create another device with same EUI64
      result =
        Device.create(%{
          network_id: network.id,
          rloc16: 0x5678,
          extended_address: eui
        })

      # Should fail due to identity constraint
      match?({:error, _}, result)
    end
  end

  property "rloc16 must be unique per network" do
    forall rloc <- integer(0, 0xFFFF) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, _device1} =
        Device.create(%{
          network_id: network.id,
          rloc16: rloc,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      # Try to create another device with same RLOC16
      result =
        Device.create(%{
          network_id: network.id,
          rloc16: rloc,
          extended_address: :crypto.strong_rand_bytes(8)
        })

      # Should fail due to identity constraint
      match?({:error, _}, result)
    end
  end

  # ============================================================================
  # GENERATORS
  # ============================================================================

  defp valid_device_attrs do
    let {rloc, device_type, lq, rssi, version} <-
          {
            integer(0, 0xFFFF),
            oneof([:end_device, :router, :leader, :reed]),
            oneof([nil, integer(0, 3)]),
            oneof([nil, integer(-128, 0)]),
            integer(1, 4)
          } do
      %{
        rloc16: rloc,
        extended_address: :crypto.strong_rand_bytes(8),
        device_type: device_type,
        link_quality: lq,
        rssi: rssi,
        version: version
      }
    end
  end

  defp minimal_device_attrs do
    %{
      rloc16: 0x1234,
      extended_address: :crypto.strong_rand_bytes(8)
    }
  end

  defp update_device_attrs do
    let {device_type, lq, rssi, active} <-
          {
            oneof([:end_device, :router, :leader, :reed]),
            oneof([nil, integer(0, 3)]),
            oneof([nil, integer(-128, 0)]),
            boolean()
          } do
      %{
        device_type: device_type,
        link_quality: lq,
        rssi: rssi,
        active: active
      }
    end
  end

  defp device_type_gen do
    oneof([
      :end_device,
      :router,
      :leader,
      :reed,
      # Invalid
      :invalid_type,
      :broker
    ])
  end

  defp eui64_gen do
    :crypto.strong_rand_bytes(8)
  end
end
