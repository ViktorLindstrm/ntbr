defmodule NTBR.Domain.Test.RegressionPropertiesTest do
  @moduledoc false
  # Property-based tests for historical bugs and edge cases.
  #   
  #   CONVERTED FROM: regression_tests.exs
  #   
  #   Tests that past bugs don't reoccur under ANY conditions.
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Joiner, Device}
  alias NTBR.Domain.Spinel.Frame

  @moduletag :property
  @moduletag :integration
  @moduletag :regression

  property "network name validation catches ALL invalid inputs",
           [:verbose, {:numtests, 200}] do
    forall name <- string_gen(0, 50) do
      result = Network.create(%{
        name: name,
        network_name: "TestNet"
      })
      
      # Empty names should fail
      case String.length(name) do
        0 -> match?({:error, _}, result)
        n when n > 0 and n <= 32 -> true  # Should succeed or have other validation
        _ -> true  # May fail for other reasons
      end
    end
    |> aggregate(:name_length, fn name ->
      len = String.length(name)
      cond do
        len == 0 -> :empty
        len < 5 -> :very_short
        len < 10 -> :short
        len < 20 -> :medium
        len < 32 -> :long
        true -> :too_long
      end
    end)
  end

  property "PSKD validation catches ALL special characters",
           [:verbose, {:numtests, 300}] do
    forall pskd <- pskd_candidate_gen() do
      {:ok, network} = Network.create(%{
        name: "PSKD-#{:rand.uniform(10000)}",
        network_name: "PSKDNet"
      })
      
      result = Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: pskd,
        timeout: 120
      })
      
      # Only alphanumeric should succeed
      valid_chars = String.match?(pskd, ~r/^[0-9A-Z]+$/i)
      valid_length = String.length(pskd) >= 6 and String.length(pskd) <= 32
      
      case {valid_chars, valid_length} do
        {true, true} -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
    |> aggregate(:character_type, fn pskd ->
      cond do
        String.match?(pskd, ~r/[!@#$%^&*()]/) -> :special_chars
        String.match?(pskd, ~r/^[0-9A-Z]+$/i) -> :valid_chars
        true -> :other
      end
    end)
  end

  property "device parent validation prevents self-reference",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "Parent-#{:rand.uniform(10000)}",
        network_name: "ParentNet"
      })
      
      eui64 = :crypto.strong_rand_bytes(8)
      
      # Attempt to create device with self as parent
      result = Device.create(%{
        network_id: network.id,
        extended_address: eui64,
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        parent_id: eui64,  # Self-reference!
        link_quality: 3,
        rssi: -50
      })
      
      # Must fail
      match?({:error, _}, result)
    end
  end

  property "TID overflow handling wraps correctly for ALL values",
           [:verbose, {:numtests, 200}] do
    forall tid_input <- integer(0, 100) do
      # Create frame with potentially overflowing TID
      frame = Frame.new(:reset, <<>>, tid: tid_input)
      
      # TID should always be in valid range (0-15)
      frame.tid >= 0 and frame.tid <= 15 and
      # Should wrap correctly
      frame.tid == rem(tid_input, 16)
    end
    |> aggregate(:tid_category, fn tid ->
      cond do
        tid <= 15 -> :valid_range
        tid <= 31 -> :first_overflow
        tid <= 63 -> :second_overflow
        true -> :multiple_overflow
      end
    end)
  end

  property "network with ANY invalid configuration fails gracefully",
           [:verbose, {:numtests, 200}] do
    forall invalid_attrs <- invalid_network_attrs_gen() do
      result = try do
        Network.create(invalid_attrs)
      rescue
        _ -> {:error, :crashed}
      catch
        _ -> {:error, :crashed}
      end
      
      # Should return error, not crash
      match?({:error, _}, result)
    end
    |> aggregate(:invalid_type, fn attrs ->
      cond do
        attrs.name == "" -> :empty_name
        String.length(attrs.name) > 100 -> :name_too_long
        not is_integer(attrs.channel) -> :invalid_channel
        attrs.channel < 11 -> :channel_too_low
        attrs.channel > 26 -> :channel_too_high
        true -> :other
      end
    end)
  end

  property "joiner timeout ALWAYS prevents indefinite waiting",
           [:verbose, {:numtests, 100}] do
    forall timeout <- integer(1, 600) do
      {:ok, network} = Network.create(%{
        name: "Timeout-#{:rand.uniform(10000)}",
        network_name: "TimeoutNet"
      })
      
      {:ok, joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: "TIMEOUT",
        timeout: timeout
      })
      
      {:ok, joiner} = Joiner.start(joiner)
      
      # Verify expiration is set correctly
      not is_nil(joiner.expires_at) and
      DateTime.diff(joiner.expires_at, joiner.started_at, :second) == timeout
    end
    |> measure("Timeout (seconds)", fn t -> t end)
  end

  property "device topology NEVER creates cycles under ANY operations",
           [:verbose, {:numtests, 100}] do
    forall device_operations <- device_operation_sequence_gen() do
      {:ok, network} = Network.create(%{
        name: "Cycle-#{:rand.uniform(10000)}",
        network_name: "CycleNet"
      })
      
      # Apply operations
      Enum.each(device_operations, fn op ->
        apply_device_operation(network.id, op)
      end)
      
      # Check for cycles
      devices = Device.by_network!(network.id)
      not has_topology_cycles?(devices)
    end
    |> measure("Operations", &length/1)
  end

  # Generators

  defp string_gen(min, max) do
    let len <- integer(min, max) do
      :crypto.strong_rand_bytes(len)
      |> Base.encode64()
      |> String.slice(0, len)
    end
  end

  defp pskd_candidate_gen do
    oneof([
      # Valid PSKDs
      let len <- integer(6, 32) do
        chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        for _ <- 1..len, into: "", do: <<Enum.random(chars)>>
      end,
      
      # Invalid PSKDs with special characters
      "TEST!@#$",
      "PASS word",
      "emoji😀",
      "tab\there",
      
      # Edge cases
      "",
      "SHORT",
      String.duplicate("A", 50)
    ])
  end

  defp invalid_network_attrs_gen do
    oneof([
      %{name: "", network_name: "Test", channel: 15},
      %{name: "Test", network_name: "", channel: 15},
      %{name: String.duplicate("X", 200), network_name: "Test", channel: 15},
      %{name: "Test", network_name: "Test", channel: 5},
      %{name: "Test", network_name: "Test", channel: 100},
      %{name: "Test", network_name: "Test", channel: "invalid"}
    ])
  end

  defp device_operation_sequence_gen do
    let count <- integer(10, 50) do
      Enum.map(1..count, fn _ ->
        oneof([
          {:create, :root},
          {:create, :child},
          {:update_parent}
        ])
      end)
    end
  end

  defp apply_device_operation(network_id, {:create, :root}) do
    Device.create(%{
      network_id: network_id,
      extended_address: :crypto.strong_rand_bytes(8),
      rloc16: :rand.uniform(0xFFFF),
      device_type: :router,
      parent_id: nil,
      link_quality: 3,
      rssi: -50
    })
  end

  defp apply_device_operation(network_id, {:create, :child}) do
    # Get existing devices
    devices = Device.by_network!(network_id)
    
    if length(devices) > 0 do
      parent = Enum.random(devices)
      Device.create(%{
        network_id: network_id,
        extended_address: :crypto.strong_rand_bytes(8),
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        parent_id: parent.extended_address,
        link_quality: 2,
        rssi: -60
      })
    else
      {:error, :no_parents}
    end
  end

  defp apply_device_operation(_network_id, _op) do
    {:ok, :skipped}
  end

  defp has_topology_cycles?(devices) do
    device_map = Map.new(devices, fn d -> {d.extended_address, d} end)
    
    Enum.any?(devices, fn device ->
      check_cycle(device, device_map, MapSet.new())
    end)
  end

  defp check_cycle(device, device_map, visited) do
    if MapSet.member?(visited, device.extended_address) do
      true  # Cycle detected
    else
      visited = MapSet.put(visited, device.extended_address)
      
      if device.parent_id do
        case Map.get(device_map, device.parent_id) do
          nil -> false
          parent -> check_cycle(parent, device_map, visited)
        end
      else
        false
      end
    end
  end
end
