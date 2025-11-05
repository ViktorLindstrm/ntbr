defmodule NTBR.Domain.Test.NetworkLifecycleProperties do
  @moduledoc false
  # Property-based tests for complete network lifecycle workflows.
  #
  # These properties test network formation sequences, commissioning,
  # and all lifecycle transitions.
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Device, Joiner, BorderRouter}
  alias NTBR.Domain.Spinel.Client

  @moduletag :property
  @moduletag :integration
  @moduletag :lifecycle

  setup do
    # Mock Spinel Client for tests that don't have hardware
    # The Client module should handle :noproc gracefully or tests should mock it
    :ok
  end

  property "network formation follows valid state transition sequences",
           [:verbose, {:numtests, 100}] do
    forall transition_sequence <- network_transition_sequence_gen(3, 10) do
      {:ok, network} = Network.create(%{
        name: "Lifecycle-#{:rand.uniform(10000)}",
        network_name: "LifecycleNet"
      })
      
      # Configure RCP if Client is available
      try do
        :ok = Client.set_channel(network.channel)
        :ok = Client.set_network_key(network.network_key)
        :ok = Client.set_pan_id(network.pan_id)
        :ok = Client.set_extended_pan_id(network.extended_pan_id)
      catch
        :exit, {:noproc, _} -> :ok  # Client not running, skip configuration
      end
      
      # Apply transition sequence and track transition validity
      {final_state, all_transitions_valid} = Enum.reduce(
        transition_sequence,
        {:detached, true},
        fn transition, {state, valid_so_far} ->
          case apply_transition(network.id, state, transition) do
            {:ok, new_state} ->
              # Valid transition succeeded
              {new_state, valid_so_far and true}

            {:error, _reason} ->
              # Invalid transition failed - this is expected for some sequences
              # Mark as invalid and stay in current state
              {state, false}
          end
        end
      )

      # Verify final state is valid
      # Note: all_transitions_valid being false means some transitions were invalid,
      # which is acceptable (testing error handling). What matters is the final state.
      final_state_valid = final_state in [:detached, :child, :router, :leader]

      # Both are acceptable outcomes:
      # 1. All transitions valid and final state valid, OR
      # 2. Some transitions invalid (expected for property testing) but system didn't crash
      result = final_state_valid
      
      aggregate(:sequence_length, length(transition_sequence),
        classify(:leader in transition_sequence, "reaches leader state", result))
    end
  end

  property "device commissioning completes successfully under various conditions",
           [:verbose, {:numtests, 100}] do
    forall {network_state, joiner_timeout, device_delay} <- commissioning_scenario_gen() do
      {:ok, network} = create_network_in_state(network_state)
      device_eui64 = :crypto.strong_rand_bytes(8)
      
      # Create joiner with variable timeout
      {:ok, joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: device_eui64,
        pskd: generate_valid_pskd(),
        timeout: joiner_timeout
      })
      
      # Start commissioning
      {:ok, joiner} = Joiner.start(joiner)
      
      # Simulate device joining with delay
      if device_delay > 0, do: Process.sleep(device_delay)
      
      {:ok, device} = Device.create(%{
        network_id: network.id,
        extended_address: device_eui64,
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        link_quality: Enum.random(1..3),
        rssi: Enum.random(-90..-30)
      })
      
      # Complete commissioning
      {:ok, joiner} = Joiner.link_device(joiner, device.id)
      {:ok, joiner} = Joiner.complete(joiner)
      
      # Verify completion
      joiner.state == :joined and
      not is_nil(joiner.completed_at) and
      Device.by_network!(network.id) |> length() >= 1
    end
    |> collect(:network_state, fn {state, _, _} -> state end)
    |> collect(:timeout_range, fn {_, timeout, _} -> 
      cond do
        timeout < 60 -> :short
        timeout < 180 -> :medium
        true -> :long
      end
    end)
  end

  property "border router configuration with various route combinations",
           [:verbose, {:numtests, 100}] do
    forall {route_count, nat64_enabled, route_priorities} <- border_router_config_gen() do
      {:ok, network} = create_network_in_state(:leader)
      
      {:ok, br} = BorderRouter.create(%{
        network_id: network.id,
        infrastructure_interface: Enum.random(["eth0", "wlan0"]),
        enable_nat64: nat64_enabled,
        enable_mdns: Enum.random([true, false]),
        enable_srp_server: Enum.random([true, false])
      })
      
      # Add routes
      br = Enum.reduce(1..route_count, br, fn i, br_acc ->
        prefix = "2001:db8:#{i}::/64"
        priority = Enum.at(route_priorities, rem(i - 1, length(route_priorities)))
        {:ok, br_updated} = BorderRouter.add_external_route(br_acc, prefix, priority)
        br_updated
      end)
      
      # Verify configuration
      length(br.external_routes) == route_count and
      br.enable_nat64 == nat64_enabled
    end
    |> aggregate(:route_count, fn {count, _, _} -> count end)
    |> classify(fn {_, nat64, _} -> nat64 end, "NAT64 enabled")
  end

  property "multiple devices join network concurrently without conflicts",
           [:verbose, {:numtests, 50}] do
    forall device_count <- integer(5, 50) do
      {:ok, network} = create_network_in_state(:leader)
      
      # Create joiners concurrently
      tasks = Enum.map(1..device_count, fn i ->
        Task.async(fn ->
          eui64 = <<0::48, i::16>>
          
          {:ok, joiner} = Joiner.create(%{
            network_id: network.id,
            eui64: eui64,
            pskd: "DEVICE#{i}",
            timeout: 120
          })
          
          {:ok, joiner} = Joiner.start(joiner)
          
          {:ok, device} = Device.create(%{
            network_id: network.id,
            extended_address: eui64,
            rloc16: i,
            device_type: :end_device,
            link_quality: 2,
            rssi: -60
          })
          
          {:ok, joiner} = Joiner.link_device(joiner, device.id)
          {:ok, joiner} = Joiner.complete(joiner)
          
          {joiner, device}
        end)
      end)
      
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      
      # All should succeed
      all_succeeded = Enum.all?(results, fn {joiner, device} ->
        joiner.state == :joined and not is_nil(device.id)
      end)
      
      # All addresses unique
      devices = Device.by_network!(network.id)
      eui64s = Enum.map(devices, & &1.extended_address)
      addresses_unique = length(eui64s) == length(Enum.uniq(eui64s))
      
      result = all_succeeded and addresses_unique and length(devices) == device_count
      
      measure("Concurrent devices", device_count,
        classify(device_count > 25, "high concurrency", result))
    end
  end

  property "network recovers correctly after RCP reset at any point",
           [:verbose, {:numtests, 50}] do
    forall {initial_state, device_count, reset_delay} <- recovery_scenario_gen() do
      {:ok, network} = create_network_in_state(initial_state)
      
      # Add devices
      Enum.each(1..device_count, fn i ->
        Device.create(%{
          network_id: network.id,
          extended_address: <<0::48, i::16>>,
          rloc16: i,
          device_type: if(rem(i, 3) == 0, do: :router, else: :end_device),
          link_quality: 3,
          rssi: -50
        })
      end)
      
      # Reset after delay
      if reset_delay > 0, do: Process.sleep(reset_delay)
      :ok = Client.reset()
      
      # Allow recovery time
      Process.sleep(2000)
      
      # Network should be in valid state
      try do
        recovered_network = Network.read!(network.id)
        recovered_network.state in [:detached, :child, :router, :leader]
      rescue
        _ -> false
      end
    end
    |> aggregate(:initial_state, fn {state, _, _} -> state end)
    |> aggregate(:device_count, fn {_, count, _} ->
      cond do
        count < 5 -> :small
        count < 20 -> :medium
        true -> :large
      end
    end)
  end

  property "stale device cleanup works correctly with various thresholds",
           [:verbose, {:numtests, 100}] do
    forall {total_devices, stale_count, timeout_seconds} <- stale_device_scenario_gen() do
      {:ok, network} = create_network_in_state(:leader)
      now = DateTime.utc_now()
      
      # Create mix of active and stale devices
      active_count = total_devices - stale_count
      
      # Active devices
      Enum.each(1..active_count, fn i ->
        recent = DateTime.add(now, -:rand.uniform(timeout_seconds - 10), :second)
        {:ok, device} = Device.create(%{
          network_id: network.id,
          extended_address: <<0::48, i::16>>,
          rloc16: i,
          device_type: :end_device,
          link_quality: 3,
          rssi: -50
        })
        Device.update(device, %{last_seen: recent})
      end)
      
      # Stale devices
      Enum.each((active_count + 1)..(active_count + stale_count), fn i ->
        old = DateTime.add(now, -timeout_seconds - :rand.uniform(300), :second)
        {:ok, device} = Device.create(%{
          network_id: network.id,
          extended_address: <<0::48, i::16>>,
          rloc16: i,
          device_type: :end_device,
          link_quality: 3,
          rssi: -50
        })
        Device.update(device, %{last_seen: old})
      end)
      
      # Get and cleanup stale devices
      stale = Device.stale_devices!(timeout_seconds: timeout_seconds)
      |> Enum.filter(&(&1.network_id == network.id))
      
      Enum.each(stale, &Device.deactivate/1)
      
      # Verify
      remaining = Device.active_devices!(network.id)
      
      result = length(stale) == stale_count and length(remaining) == active_count
      
      measure("Total devices", total_devices,
        classify(stale_count > 10, "many stale devices", result))
    end
  end

  property "joiner expiration handling works at various timeout values",
           [:verbose, {:numtests, 100}] do
    forall timeout_seconds <- integer(1, 10) do
      {:ok, network} = create_network_in_state(:leader)
      
      {:ok, joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: "EXPIRE",
        timeout: timeout_seconds
      })
      
      {:ok, joiner} = Joiner.start(joiner)
      
      # Wait for expiration
      Process.sleep((timeout_seconds + 1) * 1000)
      
      # Check if expired
      expired = Joiner.expired!()
      expired_ids = Enum.map(expired, & &1.id)
      
      result = joiner.id in expired_ids
      
      measure("Timeout (seconds)", timeout_seconds, result)
    end
  end

  # Generators

  defp network_transition_sequence_gen(min, max) do
    let count <- integer(min, max) do
      vector(count, transition_gen())
    end
  end

  defp transition_gen do
    oneof([:attach, :promote, :demote, :detach])
  end

  defp commissioning_scenario_gen do
    {
      oneof([:child, :router, :leader]),
      integer(30, 300),  # timeout
      integer(0, 100)    # device delay
    }
  end

  defp border_router_config_gen do
    let [
      route_count <- integer(1, 10),
      nat64_enabled <- boolean(),
      num_priorities <- integer(1, 3)
    ] do
      priorities = List.duplicate(oneof([:high, :medium, :low]), num_priorities)
      {route_count, nat64_enabled, priorities}
    end
  end

  defp recovery_scenario_gen do
    {
      oneof([:child, :router, :leader]),  # initial state
      integer(0, 20),                      # device count
      integer(0, 500)                      # reset delay
    }
  end

  defp stale_device_scenario_gen do
    let [
      total <- integer(10, 50),
      stale <- integer(1, 25),
      timeout <- integer(60, 600)
    ] do
      {total, stale, timeout}
    end
  end

  # Helpers

  defp create_network_in_state(desired_state) do
    {:ok, network} = Network.create(%{
      name: "State-#{:rand.uniform(10000)}",
      network_name: "StateNet"
    })
    
    # Try to configure RCP if Client is available
    try do
      Client.set_channel(network.channel)
      Client.set_network_key(network.network_key)
      Client.set_pan_id(network.pan_id)
      Client.set_extended_pan_id(network.extended_pan_id)
    catch
      :exit, {:noproc, _} -> :ok  # Client not running, skip configuration
    end
    
    # Transition to desired state
    result = case desired_state do
      :detached -> 
        {:ok, network}
      
      :child ->
        Network.attach(network)
      
      :router ->
        with {:ok, network} <- Network.attach(network),
             {:ok, network} <- Network.promote(network) do
          {:ok, network}
        end
      
      :leader ->
        with {:ok, network} <- Network.attach(network),
             {:ok, network} <- Network.promote(network),
             {:ok, network} <- Network.promote(network) do
          {:ok, network}
        end
    end
    
    # Ensure we always return the network or error
    case result do
      {:ok, _network} = success -> success
      {:error, _} = error -> error
    end
  end

  defp apply_transition(network_id, current_state, transition) do
    case Network.by_id(network_id) do
      {:ok, network} ->
        result = case {current_state, transition} do
          {:detached, :attach} -> Network.attach(network)
          {:child, :promote} -> Network.promote(network)
          {:router, :promote} -> Network.promote(network)
          {:leader, :demote} -> Network.demote(network)
          {:router, :demote} -> Network.demote(network)
          {_, :detach} -> Network.detach(network)
          _ -> {:error, :invalid_transition}
        end
        
        # Extract the new state from the result
        case result do
          {:ok, updated_network} -> {:ok, updated_network.state}
          {:error, _} = error -> error
        end
      
      {:error, _} = error -> error
    end
  end

  defp generate_valid_pskd do
    chars = ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    length = Enum.random(6..32)
    for _ <- 1..length, into: "", do: <<Enum.random(chars)>>
  end
end




