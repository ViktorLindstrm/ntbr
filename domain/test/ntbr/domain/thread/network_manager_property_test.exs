defmodule NTBR.Domain.Thread.NetworkManagerPropertyTest do
  @moduledoc """
  Property-based tests for NetworkManager using PropCheck 1.5.

  Tests verify that NetworkManager correctly:
  - Manages network lifecycle transitions
  - Handles concurrent operations safely
  - Synchronizes state between RCP and domain
  - Processes topology updates correctly
  - Monitors joiner sessions reliably
  """
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Thread.NetworkManager
  alias NTBR.Domain.Resources.{Network, Device, Joiner}
  alias NTBR.Domain.Spinel.Client

  # Test setup with mocks
  setup do
    # Start test supervision tree
    start_supervised!({Phoenix.PubSub, name: NTBR.PubSub})

    # Mock Spinel Client
    Mox.defmock(SpinelClientMock, for: NTBR.Domain.Spinel.ClientBehaviour)

    # Start NetworkManager with mock
    {:ok, manager} =
      start_supervised({NetworkManager, spinel_client: SpinelClientMock})

    %{manager: manager}
  end

  @moduletag :property
  @moduletag :thread
  @moduletag :network_manager

  # ============================================================================
  # Lifecycle Properties
  # ============================================================================

  property "attach and detach operations are always idempotent",
           [:verbose, {:numtests, 100}] do
    forall {network_attrs, attach_count, detach_count} <-
             {network_attrs_gen(), integer(1, 5), integer(1, 5)} do
      # Create network
      {:ok, network} = Network.create(network_attrs)

      # Mock successful RCP configuration
      setup_successful_attach_mock()

      # Multiple attaches should succeed but only attach once
      attach_results =
        Enum.map(1..attach_count, fn _ ->
          NetworkManager.attach_network(network.id)
        end)

      # First attach succeeds, subsequent might return already attached
      assert Enum.at(attach_results, 0) in [:ok, {:error, :already_attached}]

      # Manager should be attached
      assert NetworkManager.attached?()

      # Multiple detaches should succeed
      detach_results =
        Enum.map(1..detach_count, fn _ ->
          NetworkManager.detach_network()
        end)

      # All detaches should succeed
      assert Enum.all?(detach_results, &(&1 == :ok))

      # Manager should not be attached
      refute NetworkManager.attached?()

      # Cleanup
      Network.delete(network)
      true
    end
  end

  #  property "network state transitions follow valid paths",
  #           [:verbose, {:numtests, 100}] do
  #    forall {network_attrs, transitions} <-
  #             {network_attrs_gen(), state_transition_sequence_gen(3, 10)} do
  #      # Create network with generated attrs
  #      {:ok, network} = Network.create(network_attrs)
  #
  #      # Your test logic here
  #      result = do_test_stuff(network, transitions)
  #
  #      # Clean up
  #      Network.destroy(network)
  #
  #      # Return boolean result
  #      result == :expected
  #    end
  #  end

  property "concurrent attach/detach operations are safe",
           [:verbose, {:numtests, 50}] do
    forall {network_attrs, op_count} <- {network_attrs_gen(), integer(5, 20)} do
      {:ok, network} = Network.create(network_attrs)

      # Test concurrent operations
      tasks =
        Enum.map(1..op_count, fn _ ->
          Task.async(fn ->
            if rem(:rand.uniform(100), 2) == 0 do
              NetworkManager.attach_network(network.id)
            else
              NetworkManager.detach_network()
            end
          end)
        end)

      results = Task.await_many(tasks, 5000)

      Network.destroy(network)
      # All completed without crashing
      true
    end
  end

  # ============================================================================
  # Topology Discovery Properties
  # ============================================================================

  property "topology updates correctly process all device types",
           [:verbose, {:numtests, 100}] do
    forall {network_attrs, router_list, child_list} <-
             {network_attrs_gen(), router_list_gen(), child_list_gen()} do
      {:ok, network} = Network.create(network_attrs)

      setup_successful_attach_mock()
      setup_topology_mock(router_list, child_list)

      :ok = NetworkManager.attach_network(network.id)

      # Trigger topology update
      :ok = NetworkManager.update_topology()
      Process.sleep(100)

      # Verify devices created
      devices = Device.by_network(network.id)

      # Should have routers + children
      expected_count = length(router_list) + length(child_list)
      assert length(devices) == expected_count

      # Verify router types
      routers = Enum.filter(devices, &(&1.device_type == :router))
      assert length(routers) == length(router_list)

      # Verify end device types
      end_devices = Enum.filter(devices, &(&1.device_type == :end_device))
      assert length(end_devices) == length(child_list)

      # All devices should have valid RSSI
      assert Enum.all?(devices, fn d ->
               d.rssi >= -100 and d.rssi <= 0
             end)

      # All devices should have valid link quality
      assert Enum.all?(devices, fn d ->
               d.link_quality in 0..3
             end)

      NetworkManager.detach_network()
      Network.delete(network)
      true
    end
    |> collect(:device_count, fn {_, routers, children} ->
      total = length(routers) + length(children)

      cond do
        total < 5 -> :few
        total < 20 -> :moderate
        total < 50 -> :many
        true -> :very_many
      end
    end)
  end

  property "topology updates handle device changes correctly",
           [:verbose, {:numtests, 100}] do
    forall {network_attrs, topology_updates} <-
             {network_attrs_gen(), topology_update_sequence_gen(5, 15)} do
      {:ok, network} = Network.create(network_attrs)

      # Apply topology updates
      Enum.each(topology_updates, fn {routers, children} ->
        NetworkManager.process_topology_update(network.id, routers, children)
      end)

      # Verify state
      devices = Device.by_network(network.id)
      valid = length(devices) > 0

      Network.destroy(network)
      valid
    end
  end

  # ============================================================================
  # Joiner Management Properties
  # ============================================================================

  #  # property "joiner lifecycle events update domain state correctly",
  #           [:verbose, {:numtests, 100}] do
  #    forall joiners <- joiner_list_gen(1, 10) do
  #      {:ok, network} = Network.create(network_attrs_gen() |> generate())
  #
  #      setup_successful_attach_mock()
  #      :ok = NetworkManager.attach_network(network.id)
  #
  #      # Create joiners
  #      created_joiners =
  #        Enum.map(joiners, fn joiner_attrs ->
  #          {:ok, joiner} =
  #            Joiner.create(Map.put(joiner_attrs, :network_id, network.id))
  #
  #          joiner
  #        end)
  #
  #      # Simulate joiner events
  #      Enum.each(created_joiners, fn joiner ->
  #        # Start event
  #        Phoenix.PubSub.broadcast(
  #          NTBR.PubSub,
  #          "spinel:events",
  #          {:spinel_event, :joiner_start, joiner.eui64}
  #        )
  #
  #        Process.sleep(10)
  #
  #        # Verify state changed to joining
  #        updated = Joiner.by_id!(joiner.id)
  #        assert updated.state == :joining
  #
  #        # Complete event
  #        Phoenix.PubSub.broadcast(
  #          NTBR.PubSub,
  #          "spinel:events",
  #          {:spinel_event, :joiner_complete, joiner.eui64}
  #        )
  #
  #        Process.sleep(10)
  #
  #        # Verify state changed to joined
  #        completed = Joiner.by_id!(joiner.id)
  #        assert completed.state == :joined
  #        assert not is_nil(completed.completed_at)
  #      end)
  #
  #      NetworkManager.detach_network()
  #      Network.delete(network)
  #      true
  #    end
  #  end

  property "expired joiners are cleaned up automatically",
           [:verbose, {:numtests, 50}] do
    forall {network_attrs, expired_count, active_count} <-
             {network_attrs_gen(), integer(1, 10), integer(1, 10)} do
      {:ok, network} = Network.create(network_attrs)

      setup_successful_attach_mock()
      :ok = NetworkManager.attach_network(network.id)

      # Create expired joiners (in the past)
      expired_time = DateTime.add(DateTime.utc_now(), -120, :second)

      expired_joiners =
        Enum.map(1..expired_count, fn i ->
          {:ok, joiner} =
            Joiner.create(%{
              network_id: network.id,
              eui64: :crypto.strong_rand_bytes(8),
              pskd: "EXPIRD#{i}",
              timeout: 60,
              expires_at: expired_time
            })

          joiner
        end)

      # Create active joiners
      active_joiners =
        Enum.map(1..active_count, fn i ->
          {:ok, joiner} =
            Joiner.create(%{
              network_id: network.id,
              eui64: :crypto.strong_rand_bytes(8),
              pskd: "ACTIVE#{i}",
              timeout: 3600
            })

          joiner
        end)

      # Trigger joiner check (via sending message directly)
      send(NetworkManager, :check_joiners)
      Process.sleep(100)

      # Verify expired joiners marked as expired
      Enum.each(expired_joiners, fn joiner ->
        updated = Joiner.by_id!(joiner.id)
        assert updated.state == :expired
      end)

      # Verify active joiners unchanged
      Enum.each(active_joiners, fn joiner ->
        updated = Joiner.by_id!(joiner.id)
        assert updated.state == :pending
      end)

      NetworkManager.detach_network()
      Network.delete(network)
      true
    end
  end

  # ============================================================================
  # Error Handling Properties
  # ============================================================================

  #  property "RCP errors are handled gracefully without crashing",
  #           [:verbose, {:numtests, 100}] do
  #    forall error_scenario <- error_scenario_gen() do
  #      {:ok, network} = Network.create(network_attrs_gen() |> generate())
  #
  #      # Setup mock to return errors
  #      setup_error_mock(error_scenario)
  #
  #      result = NetworkManager.attach_network(network.id)
  #
  #      # Should return error but not crash
  #      assert match?({:error, _}, result)
  #
  #      # Manager should still be responsive
  #      state = NetworkManager.get_state()
  #      assert is_map(state)
  #
  #      # Should not be attached
  #      refute NetworkManager.attached?()
  #
  #      Network.delete(network)
  #      true
  #    end
  #  end

  # ============================================================================
  # Generators
  # ============================================================================

  defp network_attrs_gen do
    let {name_len, netname_len, channel} <-
          {integer(5, 32), integer(5, 16), integer(11, 26)} do
      %{
        name: random_string(name_len),
        network_name: random_string(netname_len),
        channel: channel,
        network_key: :crypto.strong_rand_bytes(16),
        pan_id: :rand.uniform(0xFFFE) + 1,
        extended_pan_id: :crypto.strong_rand_bytes(8)
      }
    end
  end

  defp state_transition_sequence_gen(min, max) do
    let count <- integer(min, max) do
      vector(count, oneof([:detached, :child, :router, :leader]))
    end
  end

  defp operation_sequence_gen(min, max) do
    let count <- integer(min, max) do
      vector(
        count,
        frequency([
          {3, :attach},
          {3, :detach},
          {1, {:sleep, integer(1, 50)}}
        ])
      )
    end
  end

  defp router_list_gen do
    let count <- integer(0, 20) do
      Enum.map(1..count, fn _ ->
        %{
          extended_address: :crypto.strong_rand_bytes(8),
          rloc16: :rand.uniform(0xFFFF),
          router_id: :rand.uniform(63),
          next_hop: :rand.uniform(63),
          path_cost: :rand.uniform(10),
          link_quality: :rand.uniform(3),
          age: :rand.uniform(100),
          device_type: :router
        }
      end)
    end
  end

  defp child_list_gen do
    let count <- integer(0, 50) do
      Enum.map(1..count, fn _ ->
        %{
          extended_address: :crypto.strong_rand_bytes(8),
          rloc16: :rand.uniform(0xFFFF),
          mode: :rand.uniform(0xFF),
          link_quality: :rand.uniform(3),
          rssi: -(:rand.uniform(70) + 30),
          device_type: :end_device
        }
      end)
    end
  end

  defp topology_update_sequence_gen(min, max) do
    let count <- integer(min, max) do
      vector(count, {router_list_gen(), child_list_gen()})
    end
  end

  defp joiner_list_gen(min, max) do
    let count <- integer(min, max) do
      Enum.map(1..count, fn i ->
        %{
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "JOINER#{i}#{:rand.uniform(9999)}",
          timeout: :rand.uniform(3600)
        }
      end)
    end
  end

  defp error_scenario_gen do
    oneof([
      :uart_write_error,
      :timeout,
      :invalid_response,
      :rcp_reset,
      :property_not_found
    ])
  end

  # ============================================================================
  # Mock Helpers
  # ============================================================================

  defp setup_successful_attach_mock do
    Mox.stub(SpinelClientMock, :set_network_key, fn _ -> :ok end)
    Mox.stub(SpinelClientMock, :set_pan_id, fn _ -> :ok end)
    Mox.stub(SpinelClientMock, :set_extended_pan_id, fn _ -> :ok end)
    Mox.stub(SpinelClientMock, :set_channel, fn _ -> :ok end)
    Mox.stub(SpinelClientMock, :set_network_name, fn _ -> :ok end)
    Mox.stub(SpinelClientMock, :interface_up, fn -> :ok end)
    Mox.stub(SpinelClientMock, :thread_start, fn -> :ok end)
    Mox.stub(SpinelClientMock, :thread_stop, fn -> :ok end)
    Mox.stub(SpinelClientMock, :interface_down, fn -> :ok end)
  end

  defp setup_topology_mock(routers, children) do
    Mox.stub(SpinelClientMock, :get_router_table, fn -> {:ok, routers} end)
    Mox.stub(SpinelClientMock, :get_child_table, fn -> {:ok, children} end)
  end

  defp setup_error_mock(scenario) do
    error = {:error, scenario}

    Mox.stub(SpinelClientMock, :set_network_key, fn _ -> error end)
    Mox.stub(SpinelClientMock, :set_pan_id, fn _ -> error end)
    Mox.stub(SpinelClientMock, :set_extended_pan_id, fn _ -> error end)
    Mox.stub(SpinelClientMock, :set_channel, fn _ -> error end)
    Mox.stub(SpinelClientMock, :set_network_name, fn _ -> error end)
    Mox.stub(SpinelClientMock, :interface_up, fn -> error end)
    Mox.stub(SpinelClientMock, :thread_start, fn -> error end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16()
    |> String.slice(0, length)
  end

  defp map_spinel_to_domain(:detached), do: :detached
  defp map_spinel_to_domain(:child), do: :child
  defp map_spinel_to_domain(:router), do: :router
  defp map_spinel_to_domain(:leader), do: :leader
  defp map_spinel_to_domain(_), do: :detached
end
