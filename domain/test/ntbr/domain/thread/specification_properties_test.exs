defmodule NTBR.Domain.Test.ThreadSpecificationPropertiesTest do
  @moduledoc """
  Property-based tests for Thread 1.3 specification compliance.
  
  CONVERTED FROM: thread_compliance_tests.exs
  
  Tests that Thread spec requirements hold for ALL cases.
  """
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Device}

  @moduletag :property
  @moduletag :thread
  @moduletag :compliance

  property "operational dataset ALWAYS contains required TLVs per Thread 1.3",
           [:verbose, {:numtests, 200}] do
    forall network_attrs <- network_attrs_gen() do
      {:ok, network} = Network.create(network_attrs)
      dataset = Network.operational_dataset(network)
      
      # Thread 1.3 required TLVs
      required_tlvs = [
        :network_key,
        :pan_id,
        :extended_pan_id,
        :network_name,
        :channel,
        :mesh_local_prefix,
        :security_policy
      ]
      
      # All required TLVs present
      has_all_tlvs = Enum.all?(required_tlvs, &Map.has_key?(dataset, &1))
      
      # Validate formats
      valid_formats = 
        byte_size(dataset.network_key) == 16 and
        byte_size(dataset.extended_pan_id) == 8 and
        dataset.pan_id >= 0 and dataset.pan_id <= 0xFFFF and
        dataset.channel >= 11 and dataset.channel <= 26 and
        String.length(dataset.network_name) <= 16
      
      has_all_tlvs and valid_formats
    end
    |> measure("Network name length", fn attrs -> String.length(attrs.network_name) end)
  end

  property "security policy complies with Thread specification requirements",
           [:verbose, {:numtests, 100}] do
    forall network_attrs <- network_attrs_gen() do
      {:ok, network} = Network.create(network_attrs)
      dataset = Network.operational_dataset(network)
      policy = dataset.security_policy
      
      # Thread spec requirements
      is_map(policy) and
      Map.has_key?(policy, :rotation_time) and
      Map.has_key?(policy, :flags) and
      policy.rotation_time > 0 and
      policy.rotation_time <= 168 and  # Max 1 week in hours
      is_map(policy.flags)
    end
  end

  property "mesh-local prefix is ALWAYS valid ULA format (fd00::/8)",
           [:verbose, {:numtests, 200}] do
    forall network_attrs <- network_attrs_gen() do
      {:ok, network} = Network.create(network_attrs)
      dataset = Network.operational_dataset(network)
      
      String.starts_with?(dataset.mesh_local_prefix, "fd") and
      String.contains?(dataset.mesh_local_prefix, "/64")
    end
  end

  property "state machine transitions ALWAYS follow Thread specification",
           [:verbose, {:numtests, 100}] do
    forall transition_sequence <- valid_thread_transition_gen() do
      {:ok, network} = Network.create(%{
        name: "FSM-#{:rand.uniform(10000)}",
        network_name: "FSMNet"
      })
      
      # Apply all transitions
      final_state = Enum.reduce(transition_sequence, :detached, fn transition, state ->
        case apply_thread_transition(network.id, state, transition) do
          {:ok, new_state} -> new_state
          {:error, _} -> state
        end
      end)
      
      # Must end in valid Thread state
      final_state in [:detached, :child, :router, :leader]
    end
  end

  property "end devices NEVER have children per Thread specification",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "EndDev-#{:rand.uniform(10000)}",
        network_name: "EndDevNet"
      })
      
      {:ok, end_device} = Device.create(%{
        network_id: network.id,
        extended_address: :crypto.strong_rand_bytes(8),
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        link_quality: 3,
        rssi: -50
      })
      
      # Attempt to create child - must fail
      result = Device.create(%{
        network_id: network.id,
        extended_address: :crypto.strong_rand_bytes(8),
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        parent_id: end_device.extended_address,
        link_quality: 2,
        rssi: -60
      })
      
      match?({:error, _}, result)
    end
  end

  property "RLOC16 addresses follow Thread format specification",
           [:verbose, {:numtests, 100}] do
    forall device_count <- integer(10, 100) do
      {:ok, network} = Network.create(%{
        name: "RLOC-#{:rand.uniform(10000)}",
        network_name: "RLOCNet"
      })
      
      # Create routers with proper RLOC16 format
      devices = Enum.map(1..device_count, fn i ->
        {:ok, device} = Device.create(%{
          network_id: network.id,
          extended_address: :crypto.strong_rand_bytes(8),
          rloc16: i * 0x400,  # Router IDs are multiples of 0x400
          device_type: :router,
          link_quality: 3,
          rssi: -50
        })
        device
      end)
      
      # All RLOC16s must be in valid range
      Enum.all?(devices, fn d -> 
        d.rloc16 >= 0 and d.rloc16 <= 0xFFFF
      end)
    end
    |> measure("Devices created", fn count -> count end)
  end

  property "EUI-64 addresses are ALWAYS unique 64-bit identifiers",
           [:verbose, {:numtests, 100}] do
    forall device_count <- integer(50, 500) do
      {:ok, network} = Network.create(%{
        name: "EUI64-#{:rand.uniform(10000)}",
        network_name: "EUI64Net"
      })
      
      devices = Enum.map(1..device_count, fn _i ->
        {:ok, device} = Device.create(%{
          network_id: network.id,
          extended_address: :crypto.strong_rand_bytes(8),
          rloc16: :rand.uniform(0xFFFF),
          device_type: Enum.random([:end_device, :router]),
          link_quality: Enum.random(0..3),
          rssi: Enum.random(-100..-20)
        })
        device
      end)
      
      eui64s = Enum.map(devices, & &1.extended_address)
      
      # All 8 bytes
      all_correct_length = Enum.all?(eui64s, fn eui -> byte_size(eui) == 8 end)
      
      # All unique
      all_unique = length(eui64s) == length(Enum.uniq(eui64s))
      
      all_correct_length and all_unique
    end
    |> measure("Device count", fn count -> count end)
    |> classify(fn count -> count > 200 end, "large network")
  end

  property "channel assignments comply with Thread frequency bands",
           [:verbose, {:numtests, 200}] do
    forall channel <- integer(11, 26) do
      {:ok, network} = Network.create(%{
        name: "Chan-#{:rand.uniform(10000)}",
        network_name: "ChanNet",
        channel: channel
      })
      
      # Channel must be in 2.4 GHz band (11-26)
      network.channel >= 11 and network.channel <= 26
    end
    |> aggregate(:channel, fn ch -> ch end)
  end

  property "PAN IDs are valid 16-bit values per Thread spec",
           [:verbose, {:numtests, 200}] do
    forall _scenario <- integer(1, 200) do
      {:ok, network} = Network.create(%{
        name: "PAN-#{:rand.uniform(10000)}",
        network_name: "PANNet"
      })
      
      network.pan_id >= 0 and network.pan_id <= 0xFFFF
    end
    |> collect(:pan_id_range, fn _ ->
      {:ok, network} = Network.create(%{name: "P", network_name: "PN"})
      case network.pan_id do
        n when n < 0x4000 -> :low
        n when n < 0x8000 -> :mid_low
        n when n < 0xC000 -> :mid_high
        _ -> :high
      end
    end)
  end

  # Generators

  defp network_attrs_gen do
    let {name_len, channel} <- {integer(1, 16), integer(11, 26)} do
      name = String.duplicate("N", name_len)
      %{
        name: name,
        network_name: name,
        channel: channel
      }
    end
  end

  defp valid_thread_transition_gen do
    let count <- integer(3, 15) do
      # Generate valid transition sequences
      base = [:attach, :promote, :promote]  # detached -> child -> router -> leader
      extras = List.duplicate(oneof([:demote, :promote]), count - 3)
      base ++ extras
    end
  end

  defp apply_thread_transition(network_id, :detached, :attach) do
    network = Network.read!(network_id)
    Network.attach(network)
  end

  defp apply_thread_transition(network_id, :child, :promote) do
    network = Network.read!(network_id)
    Network.promote(network)
  end

  defp apply_thread_transition(network_id, :router, :promote) do
    network = Network.read!(network_id)
    Network.promote(network)
  end

  defp apply_thread_transition(network_id, :leader, :demote) do
    network = Network.read!(network_id)
    Network.demote(network)
  end

  defp apply_thread_transition(network_id, :router, :demote) do
    network = Network.read!(network_id)
    Network.demote(network)
  end

  defp apply_thread_transition(_network_id, state, _transition) do
    {:error, {:invalid_transition, state}}
  end
end
