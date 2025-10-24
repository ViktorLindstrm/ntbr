  # Configure PropCheck
  PropCheck.start()

  # Configure ExUnit
  ExUnit.start(
    exclude: [:skip, :pending],
    formatters: [ExUnit.CLIFormatter],
    max_cases: System.schedulers_online() * 2,
    timeout: :infinity
  )

# Helper module for common test utilities
defmodule Core.TestHelpers do
  @moduledoc """
  Common test utilities for NTBR tests.
  """
  
  alias Core.Resources.{ThreadNetwork, SpinelFrame, RCPStatus}
  
  # Configure test tags
  ExUnit.configure(
    exclude: [
      property: false,      # Include property tests by default
      integration: false,   # Include integration tests
      slow: false          # Include slow tests
    ]
  )

  # Property test configuration
  Application.put_env(:propcheck, :verbose, true)
  Application.put_env(:propcheck, :numtests, 100)  # Run 100 iterations per property
  Application.put_env(:propcheck, :max_size, 50)   # Maximum size for generated data

  # Seed for reproducibility (comment out for randomness)
  # :rand.seed(:exsplus, {1, 2, 3})

  @doc """
  Creates a test network with default or custom attributes.
  """
  def create_test_network(attrs \\ %{}) do
    default_attrs = %{
      name: "TestNetwork",
      pan_id: 0x1234,
      channel: 15,
      extended_pan_id: :crypto.strong_rand_bytes(8),
      network_key: :crypto.strong_rand_bytes(16),
      role: :disabled,
      state: :offline
    }
    
    ThreadNetwork.create(Map.merge(default_attrs, attrs))
  end
  
  @doc """
  Creates an active test network (as leader).
  """
  def create_active_network(attrs \\ %{}) do
    default_attrs = %{
      name: "ActiveNetwork",
      pan_id: 0x5678,
      channel: 20,
      role: :leader,
      state: :active,
      child_count: 3,
      router_count: 2
    }
    
    create_test_network(Map.merge(default_attrs, attrs))
  end
  
  @doc """
  Creates a test Spinel frame with default or custom attributes.
  """
  def create_test_frame(attrs \\ %{}) do
    default_attrs = %{
      sequence: :rand.uniform(10000),
      direction: :outbound,
      command: :prop_value_get,
      tid: :rand.uniform(15),
      property: :protocol_version,
      size_bytes: 3,
      status: :success,
      timestamp: DateTime.utc_now()
    }
    
    SpinelFrame.capture(Map.merge(default_attrs, attrs))
  end
  
  @doc """
  Creates a request/response frame pair.
  """
  def create_frame_pair(tid \\ nil) do
    tid = tid || :rand.uniform(15)
    
    {:ok, request} = create_test_frame(%{
      direction: :outbound,
      command: :prop_value_get,
      tid: tid,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, response} = create_test_frame(%{
      direction: :inbound,
      command: :prop_value_is,
      tid: tid,
      timestamp: DateTime.add(DateTime.utc_now(), 10, :millisecond)
    })
    
    {request, response}
  end
  
  @doc """
  Creates test RCP status.
  """
  def create_test_rcp_status(attrs \\ %{}) do
    default_attrs = %{
      port: "/dev/ttyUSB0",
      baudrate: 115200
    }
    
    {:ok, status} = RCPStatus.initialize(Map.merge(default_attrs, attrs))
    
    # Mark as connected by default
    RCPStatus.mark_connected(status, %{
      protocol_version: "4.0",
      ncp_version: "OpenThread/1.0",
      capabilities: [:config, :net],
      hardware_address: :crypto.strong_rand_bytes(8)
    })
  end
  
  @doc """
  Clears all test data from ETS tables.
  """
  def clear_all_test_data do
    # Clear networks
    ThreadNetwork.read_all!()
    |> Enum.each(&ThreadNetwork.destroy/1)
    
    # Clear frames
    SpinelFrame.read_all!()
    |> Enum.each(&SpinelFrame.destroy/1)
    
    # Clear RCP status
    case RCPStatus.current() do
      {:ok, status} -> RCPStatus.destroy(status)
      _ -> :ok
    end
  end
  
  @doc """
  Waits for a condition to be true, with timeout.
  """
  def wait_until(fun, timeout \\ 5000) do
    wait_until(fun, timeout, System.monotonic_time(:millisecond))
  end
  
  defp wait_until(fun, timeout, start_time) do
    if fun.() do
      :ok
    else
      current_time = System.monotonic_time(:millisecond)
      elapsed = current_time - start_time
      
      if elapsed >= timeout do
        raise "Timeout waiting for condition"
      else
        Process.sleep(10)
        wait_until(fun, timeout, start_time)
      end
    end
  end
  
  @doc """
  Asserts that two maps are equal, ignoring specified keys.
  """
  def assert_maps_equal(map1, map2, ignore_keys \\ [:id, :inserted_at, :updated_at]) do
    map1_filtered = Map.drop(map1, ignore_keys)
    map2_filtered = Map.drop(map2, ignore_keys)
    
    assert map1_filtered == map2_filtered
  end
  
  @doc """
  Generates a unique network name for tests.
  """
  def unique_network_name do
    "TestNetwork_#{System.unique_integer([:positive])}"
  end
  
  @doc """
  Creates multiple test frames with incrementing sequence numbers.
  """
  def create_test_frames(count, attrs \\ %{}) do
    for seq <- 1..count do
      frame_attrs = Map.merge(attrs, %{
        sequence: seq,
        timestamp: DateTime.add(DateTime.utc_now(), seq, :millisecond)
      })
      
      {:ok, frame} = create_test_frame(frame_attrs)
      frame
    end
  end
  
  @doc """
  Simulates time passing (for testing time-based features).
  """
  def simulate_time_passing(seconds) do
    # In real implementation, might use a time mock library
    # For now, just sleep
    Process.sleep(seconds * 1000)
  end
end

# Make test helpers available to all tests
Code.require_file("support/generators.ex", __DIR__)

# Setup test database/storage
# (Add ETS table initialization if needed)

# Print test configuration
IO.puts("\n")
IO.puts("🧪 NTBR Test Suite Configuration")
IO.puts("=================================")
IO.puts("PropCheck iterations: #{Application.get_env(:propcheck, :numtests, 100)}")
IO.puts("Max size: #{Application.get_env(:propcheck, :max_size, 50)}")
IO.puts("Schedulers: #{System.schedulers_online()}")
IO.puts("Max concurrent cases: #{System.schedulers_online() * 2}")
IO.puts("\n")
IO.puts("Test Tags:")
IO.puts("  - Run all: mix test")
IO.puts("  - Property tests only: mix test --only property")
IO.puts("  - Integration tests: mix test --only integration")
IO.puts("  - Skip slow tests: mix test --exclude slow")
IO.puts("\n")
