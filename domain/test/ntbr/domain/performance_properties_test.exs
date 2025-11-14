defmodule NTBR.Domain.Test.PerformancePropertiesTest do
  @moduledoc false
  # Property-based performance tests with varying workloads.
  #
  # CONVERTED FROM: performance_benchmarks.exs
  #
  # Tests performance characteristics across different scales.
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Device}
  alias NTBR.Domain.Spinel.Frame

  @moduletag :property
  @moduletag :integration
  @moduletag :performance

  property "frame encoding throughput scales linearly with quantity",
           [:verbose, {:numtests, 50}] do
    forall count <- integer(1000, 20_000) do
      frames = Enum.map(1..count, fn i ->
        Frame.new(:prop_value_get, <<rem(i, 256)>>, tid: rem(i, 16))
      end)

      {time_us, _} = :timer.tc(fn ->
        Enum.each(frames, &Frame.encode/1)
      end)

      # Should be < 10 microseconds per frame
      time_per_frame = time_us / count
      result = time_per_frame < 10
      
      result
      |> measure("Frames encoded", count)
      |> measure("Time per frame (μs)", Float.round(time_per_frame, 2))
    end
  end

  property "frame decoding throughput scales linearly",
           [:verbose, {:numtests, 50}] do
    forall count <- integer(1000, 20_000) do
      encoded = Enum.map(1..count, fn i ->
        frame = Frame.new(:prop_value_get, <<rem(i, 256)>>, tid: rem(i, 16))
        Frame.encode(frame)
      end)

      {time_us, _} = :timer.tc(fn ->
        Enum.each(encoded, &Frame.decode/1)
      end)

      time_per_frame = time_us / count
      result = time_per_frame < 10
      
      result
      |> measure("Frames decoded", count)
    end
  end

  property "network creation time scales linearly with quantity",
           [:verbose, {:numtests, 50}] do
    forall count <- integer(10, 200) do
      {time_us, _} = :timer.tc(fn ->
        Enum.each(1..count, fn i ->
          Network.create(%{
            name: "Perf-#{i}",
            network_name: "PerfNet-#{i}"
          })
        end)
      end)

      # Should be < 10ms per network
      time_per_network = time_us / count
      result = time_per_network < 10_000
      
      result
      |> measure("Networks created", count)
      |> classify(count > 100, "large batch")
    end
  end

  property "device creation scales linearly up to 1000 devices",
           [:verbose, {:numtests, 30}] do
    forall count <- integer(100, 1000) do
      {:ok, network} = Network.create(%{
        name: "DevPerf",
        network_name: "DevPerfNet"
      })

      {time_us, _} = :timer.tc(fn ->
        Enum.each(1..count, fn i ->
          Device.create(%{
            network_id: network.id,
            extended_address: :crypto.strong_rand_bytes(8),
            rloc16: rem(i, 0xFFFF),
            device_type: if(rem(i, 3) == 0, do: :router, else: :end_device),
            link_quality: rem(i, 4),
            rssi: -30 - rem(i, 70)
          })
        end)
      end)

      # Should be < 500 microseconds per device
      time_per_device = time_us / count
      result = time_per_device < 500
      
      result
      |> measure("Devices created", count)
    end
  end

  property "device query performance remains constant regardless of network size",
           [:verbose, {:numtests, 30}] do
    forall count <- integer(100, 2000) do
      {:ok, network} = Network.create(%{
        name: "QueryPerf",
        network_name: "QueryPerfNet"
      })
      
      # Setup devices
      Enum.each(1..count, fn i ->
        Device.create(%{
          network_id: network.id,
          extended_address: <<0::48, i::16>>,
          rloc16: rem(i, 0xFFFF),
          device_type: :end_device,
          link_quality: 2,
          rssi: -50
        })
      end)

      # Benchmark query
      {time_us, devices} = :timer.tc(fn ->
        Device.by_network!(network.id)
      end)

      # Should be < 100ms regardless of size
      time_ms = time_us / 1000
      result = time_ms < 100 and length(devices) == count
      
      result
      |> measure("Device count", count)
      |> measure("Query time (ms)", Float.round(time_ms, 2))
    end
  end

  property "memory usage grows linearly with resource count",
           [:verbose, {:numtests, 20}] do
    forall count <- integer(100, 1000) do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)

      Enum.each(1..count, fn i ->
        Network.create(%{
          name: "Mem-#{i}",
          network_name: "MemNet-#{i}"
        })
      end)

      memory_after = :erlang.memory(:total)
      memory_per_network = (memory_after - memory_before) / count

      # Should be < 50KB per network
      result = memory_per_network < 50_000
      
      result
      |> measure("Networks created", count)
    end
  end

  property "concurrent operations complete within reasonable time bounds",
           [:verbose, {:numtests, 30}] do
    forall {operation_count, concurrency_level} <- concurrent_workload_gen() do
      operations = List.duplicate(:create_network, operation_count)
      
      {time_us, _} = :timer.tc(fn ->
        operations
        |> Enum.chunk_every(concurrency_level)
        |> Enum.each(fn chunk ->
          tasks = Enum.map(chunk, fn _ ->
            Task.async(fn ->
              Network.create(%{
                name: "Concurrent-#{:rand.uniform(100000)}",
                network_name: "ConcurrentNet"
              })
            end)
          end)
          Enum.each(tasks, &Task.await(&1, 5000))
        end)
      end)

      # Should complete in reasonable time
      time_ms = time_us / 1000
      time_ms < operation_count * 20  # < 20ms per operation
    end
    |> aggregate(:concurrency, fn {_, level} -> level end)
  end

  defp concurrent_workload_gen do
    {
      integer(10, 100),   # operation count
      integer(5, 25)      # concurrency level
    }
  end
end
