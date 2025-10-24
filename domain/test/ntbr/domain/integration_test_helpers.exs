defmodule NTBR.Domain.IntegrationTestHelpers do
  @moduledoc """
  Test helpers for integration testing NetworkManager, Spinel.Client,
  and Ash resources together.
  
  Provides utilities for:
  - Setting up test environments
  - Creating mock RCP responses
  - Simulating Spinel events
  - Verifying state synchronization
  """

  alias NTBR.Domain.Resources.{Network, Device, Joiner, BorderRouter}
  alias NTBR.Domain.Thread.NetworkManager
  alias NTBR.Domain.Spinel.Client

  @doc """
  Creates a complete test network with all resources.
  
  Returns a map with:
    - `:network` - The network resource
    - `:border_router` - The border router resource
    - `:devices` - List of device resources
    - `:joiners` - List of joiner resources
  """
  def create_test_network(opts \\ []) do
    # Create network
    {:ok, network} =
      Network.create(%{
        name: Keyword.get(opts, :name, "TestNetwork"),
        network_name: Keyword.get(opts, :network_name, "TestNet"),
        channel: Keyword.get(opts, :channel, 15)
      })

    # Create border router if requested
    border_router =
      if Keyword.get(opts, :with_border_router, false) do
        {:ok, br} =
          BorderRouter.create(%{
            network_id: network.id,
            infrastructure_interface: "eth0",
            enable_nat64: true
          })

        br
      end

    # Create devices if requested
    devices =
      if device_count = Keyword.get(opts, :device_count, 0) do
        Enum.map(1..device_count, fn i ->
          {:ok, device} =
            Device.create(%{
              network_id: network.id,
              extended_address: :crypto.strong_rand_bytes(8),
              rloc16: 0x0800 + i,
              device_type: if(rem(i, 3) == 0, do: :router, else: :end_device),
              link_quality: rem(i, 3) + 1,
              rssi: -(30 + rem(i, 40))
            })

          device
        end)
      else
        []
      end

    # Create joiners if requested
    joiners =
      if joiner_count = Keyword.get(opts, :joiner_count, 0) do
        Enum.map(1..joiner_count, fn i ->
          {:ok, joiner} =
            Joiner.create(%{
              network_id: network.id,
              eui64: :crypto.strong_rand_bytes(8),
              pskd: "JOINER#{i}",
              timeout: 300
            })

          joiner
        end)
      else
        []
      end

    %{
      network: network,
      border_router: border_router,
      devices: devices,
      joiners: joiners
    }
  end

  @doc """
  Simulates a Spinel event by broadcasting on PubSub.
  """
  def simulate_spinel_event(event_type, data) do
    Phoenix.PubSub.broadcast(
      NTBR.PubSub,
      "spinel:events",
      {:spinel_event, event_type, data}
    )
  end

  @doc """
  Simulates a complete network formation sequence.
  
  Returns the final network state.
  """
  def simulate_network_formation(network_id) do
    # Simulate state transitions
    states = [:detached, :child, :router, :leader]

    Enum.each(states, fn state ->
      simulate_spinel_event(:state_changed, state)
      Process.sleep(50)
    end)

    # Simulate role change to leader
    simulate_spinel_event(:role_changed, :leader)
    Process.sleep(50)

    Network.by_id!(network_id)
  end

  @doc """
  Simulates device discovery by sending topology updates.
  """
  def simulate_device_discovery(network_id, device_count) do
    devices =
      Enum.map(1..device_count, fn i ->
        %{
          extended_address: :crypto.strong_rand_bytes(8),
          rloc16: 0x0800 + i,
          device_type: if(rem(i, 3) == 0, do: :router, else: :end_device),
          link_quality: rem(i, 3) + 1,
          rssi: -(30 + rem(i, 40))
        }
      end)

    # Trigger topology update with mock data
    # This would normally come from Spinel.Client
    Enum.each(devices, fn device_info ->
      {:ok, _device} = Device.create(Map.put(device_info, :network_id, network_id))
    end)

    Device.by_network(network_id)
  end

  @doc """
  Simulates a joiner commissioning flow.
  """
  def simulate_joiner_commissioning(joiner) do
    # Start commissioning
    simulate_spinel_event(:joiner_start, joiner.eui64)
    Process.sleep(50)

    # Complete commissioning
    simulate_spinel_event(:joiner_complete, joiner.eui64)
    Process.sleep(50)

    Joiner.by_id!(joiner.id)
  end

  @doc """
  Waits for a condition to be true, with timeout.
  """
  def wait_until(fun, timeout \\ 1000, interval \\ 10) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_wait_until(fun, deadline, interval)
      else
        {:error, :timeout}
      end
    end
  end

  @doc """
  Verifies that network state matches RCP state.
  """
  def verify_state_sync(network_id, expected_state) do
    network = Network.by_id!(network_id)
    assert network.state == expected_state
  end

  @doc """
  Cleans up all test data for a network.
  """
  def cleanup_network(network_id) do
    # Delete all devices
    Device.by_network(network_id)
    |> Enum.each(&Device.delete/1)

    # Delete all joiners
    Joiner.by_network(network_id)
    |> Enum.each(&Joiner.delete/1)

    # Delete border router if exists
    case BorderRouter.by_network(network_id) do
      {:ok, [br | _]} -> BorderRouter.delete(br)
      _ -> :ok
    end

    # Delete network
    Network.by_id!(network_id)
    |> Network.delete()
  end
end

defmodule NTBR.Domain.IntegrationTest do
  @moduledoc """
  Integration tests for the complete NTBR stack.
  
  Tests the interaction between:
  - NetworkManager
  - Spinel.Client
  - Ash Resources (Network, Device, Joiner, BorderRouter)
  - PubSub event system
  """
  use ExUnit.Case, async: false
  use PropCheck

  import NTBR.Domain.IntegrationTestHelpers

  alias NTBR.Domain.Thread.NetworkManager
  alias NTBR.Domain.Resources.{Network, Device, Joiner}

  setup do
    # Start test infrastructure
    start_supervised!({Phoenix.PubSub, name: NTBR.PubSub})
    start_supervised!(NetworkManager)

    on_exit(fn ->
      # Cleanup any remaining networks
      if NetworkManager.attached?() do
        NetworkManager.detach_network()
      end
    end)

    :ok
  end

  @moduletag :integration

  # ============================================================================
  # Full Stack Integration Tests
  # ============================================================================

  test "complete network lifecycle: create, attach, form, detach, delete" do
    # Create network resources
    test_env = create_test_network(name: "FullStack", network_name: "FullStackNet")
    network = test_env.network

    # Attach to network
    assert :ok = NetworkManager.attach_network(network.id)
    assert NetworkManager.attached?()

    # Simulate network formation
    formed_network = simulate_network_formation(network.id)
    assert formed_network.state == :leader

    # Verify manager state
    manager_state = NetworkManager.get_state()
    assert manager_state.network_id == network.id

    # Detach from network
    assert :ok = NetworkManager.detach_network()
    refute NetworkManager.attached?()

    # Verify network state updated
    detached_network = Network.by_id!(network.id)
    assert detached_network.state == :detached

    # Cleanup
    cleanup_network(network.id)
  end

  test "topology discovery creates and updates devices" do
    test_env = create_test_network(name: "TopoTest")
    network = test_env.network

    assert :ok = NetworkManager.attach_network(network.id)

    # Simulate device discovery
    devices = simulate_device_discovery(network.id, 10)

    assert length(devices) == 10

    # Verify device types
    routers = Enum.filter(devices, &(&1.device_type == :router))
    end_devices = Enum.filter(devices, &(&1.device_type == :end_device))

    assert length(routers) > 0
    assert length(end_devices) > 0

    # Trigger topology update to verify last_seen updates
    Process.sleep(100)
    NetworkManager.update_topology()
    Process.sleep(100)

    # Verify devices have recent timestamps
    updated_devices = Device.by_network(network.id)

    Enum.each(updated_devices, fn device ->
      assert not is_nil(device.last_seen)
    end)

    NetworkManager.detach_network()
    cleanup_network(network.id)
  end

  test "joiner commissioning flow updates states correctly" do
    test_env = create_test_network(name: "JoinerTest", joiner_count: 3)
    network = test_env.network
    joiners = test_env.joiners

    assert :ok = NetworkManager.attach_network(network.id)

    # Simulate commissioning for each joiner
    Enum.each(joiners, fn joiner ->
      # Start commissioning
      commissioned = simulate_joiner_commissioning(joiner)

      # Verify states
      assert commissioned.state == :joined
      assert not is_nil(commissioned.started_at)
      assert not is_nil(commissioned.completed_at)
    end)

    # Verify all joiners are joined
    all_joiners = Joiner.by_network(network.id)
    assert Enum.all?(all_joiners, &(&1.state == :joined))

    NetworkManager.detach_network()
    cleanup_network(network.id)
  end

  test "concurrent operations on multiple networks" do
    # Create multiple networks
    networks =
      Enum.map(1..3, fn i ->
        test_env = create_test_network(name: "Network#{i}", network_name: "Net#{i}")
        test_env.network
      end)

    # Attach to each network sequentially (only one can be active)
    Enum.each(networks, fn network ->
      assert :ok = NetworkManager.attach_network(network.id)
      assert NetworkManager.attached?()

      # Simulate some activity
      simulate_network_formation(network.id)
      Process.sleep(50)

      assert :ok = NetworkManager.detach_network()
      refute NetworkManager.attached?()
    end)

    # Cleanup
    Enum.each(networks, fn network ->
      cleanup_network(network.id)
    end)
  end

  test "state synchronization between RCP events and domain" do
    test_env = create_test_network(name: "SyncTest")
    network = test_env.network

    assert :ok = NetworkManager.attach_network(network.id)

    # Test each state transition
    states = [:detached, :child, :router, :leader]

    Enum.each(states, fn state ->
      simulate_spinel_event(:state_changed, state)

      # Wait for state to propagate
      assert :ok =
               wait_until(fn ->
                 updated = Network.by_id!(network.id)
                 updated.state == state
               end)
    end)

    # Test role changes
    roles = [:child, :router, :leader]

    Enum.each(roles, fn role ->
      simulate_spinel_event(:role_changed, role)
      Process.sleep(50)

      # Verify role reflected in domain
      updated = Network.by_id!(network.id)

      case role do
        :leader -> assert updated.state == :leader
        :router -> assert updated.state == :router
        :child -> assert updated.state == :child
      end
    end)

    NetworkManager.detach_network()
    cleanup_network(network.id)
  end

  # ============================================================================
  # Property-Based Integration Tests
  # ============================================================================

  property "network lifecycle with random state transitions always maintains consistency",
           [:verbose, {:numtests, 50}] do
    forall state_sequence <- state_sequence_gen(5, 15) do
      test_env = create_test_network(name: "PropTest#{:rand.uniform(10000)}")
      network = test_env.network

      :ok = NetworkManager.attach_network(network.id)

      # Apply state transitions
      Enum.each(state_sequence, fn state ->
        simulate_spinel_event(:state_changed, state)
        Process.sleep(20)
      end)

      # Verify final state is consistent
      final_network = Network.by_id!(network.id)
      final_state = final_network.state

      # State should be one of valid states
      assert final_state in [:detached, :child, :router, :leader]

      # Manager should still be responsive
      manager_state = NetworkManager.get_state()
      assert is_map(manager_state)

      NetworkManager.detach_network()
      cleanup_network(network.id)
      true
    end
  end

  property "device discovery with varying topology sizes always succeeds",
           [:verbose, {:numtests, 50}] do
    forall device_count <- integer(0, 100) do
      test_env = create_test_network(name: "DeviceTest#{:rand.uniform(10000)}")
      network = test_env.network

      :ok = NetworkManager.attach_network(network.id)

      # Simulate device discovery
      devices = simulate_device_discovery(network.id, device_count)

      # Verify device count
      assert length(devices) == device_count

      # All devices should have valid attributes
      assert Enum.all?(devices, fn d ->
               not is_nil(d.extended_address) and
                 not is_nil(d.rloc16) and
                 d.device_type in [:router, :end_device, :leader] and
                 d.link_quality in 0..3 and
                 d.rssi >= -100 and d.rssi <= 0
             end)

      NetworkManager.detach_network()
      cleanup_network(network.id)
      true
    end
    |> collect(:device_count_range, fn count ->
      cond do
        count < 10 -> :small
        count < 30 -> :medium
        count < 60 -> :large
        true -> :very_large
      end
    end)
  end

  property "joiner commissioning with concurrent joins maintains correctness",
           [:verbose, {:numtests, 30}] do
    forall joiner_count <- integer(1, 20) do
      test_env =
        create_test_network(
          name: "JoinerConcurrent#{:rand.uniform(10000)}",
          joiner_count: joiner_count
        )

      network = test_env.network
      joiners = test_env.joiners

      :ok = NetworkManager.attach_network(network.id)

      # Commission all joiners concurrently
      tasks =
        Enum.map(joiners, fn joiner ->
          Task.async(fn ->
            simulate_joiner_commissioning(joiner)
          end)
        end)

      # Wait for all to complete
      commissioned_joiners = Task.await_many(tasks, 5000)

      # Verify all completed successfully
      assert length(commissioned_joiners) == joiner_count

      assert Enum.all?(commissioned_joiners, fn j ->
               j.state == :joined and not is_nil(j.completed_at)
             end)

      NetworkManager.detach_network()
      cleanup_network(network.id)
      true
    end
  end

  # ============================================================================
  # Generators
  # ============================================================================

  defp state_sequence_gen(min, max) do
    let count <- integer(min, max) do
      vector(count, oneof([:detached, :child, :router, :leader]))
    end
  end
end
