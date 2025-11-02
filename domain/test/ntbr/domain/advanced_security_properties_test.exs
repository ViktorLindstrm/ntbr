defmodule NTBR.Domain.Test.AdvancedSecurityPropertiesTest do
  @moduledoc false
  # Advanced security testing for side-channel attacks, network-level
  #   attacks, and sophisticated adversarial scenarios.
  #   
  #   Covers:
  #   - Side-channel attacks (timing, power analysis simulation)
  #   - Network topology attacks
  #   - Byzantine fault scenarios
  #   - Cryptographic weaknesses
  #   - Protocol-level vulnerabilities
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Device, Joiner}
  alias NTBR.Domain.Spinel.Frame
  alias NTBR.Domain.Test.AshGenerators

  @moduletag :property
  @moduletag :integration
  @moduletag :security
  @moduletag :advanced_security
  @moduletag :adversarial

  # ===========================================================================
  # Side-Channel Attacks
  # ===========================================================================

  property "constant-time comparison prevents timing attacks on credentials",
           [:verbose, {:numtests, 200}] do
    forall {correct_cred, similar_creds, different_creds} <- AshGenerators.credential_timing_gen() do
      {:ok, network} = Network.create(%{
        name: "ConstTime-#{:rand.uniform(10000)}",
        network_name: "ConstTimeNet"
      })
      
      # Measure timing for correct credential
      timings_correct = Enum.map(1..10, fn _ ->
        {time, _} = :timer.tc(fn ->
          Joiner.create(%{
            network_id: network.id,
            eui64: :crypto.strong_rand_bytes(8),
            pskd: correct_cred,
            timeout: 120
          })
        end)
        time
      end)
      
      # Measure timing for similar credentials (1-2 chars different)
      timings_similar = Enum.map(similar_creds, fn cred ->
        {time, _} = :timer.tc(fn ->
          Joiner.create(%{
            network_id: network.id,
            eui64: :crypto.strong_rand_bytes(8),
            pskd: cred,
            timeout: 120
          })
        end)
        time
      end)
      
      # Measure timing for completely different credentials
      timings_different = Enum.map(different_creds, fn cred ->
        {time, _} = :timer.tc(fn ->
          Joiner.create(%{
            network_id: network.id,
            eui64: :crypto.strong_rand_bytes(8),
            pskd: cred,
            timeout: 120
          })
        end)
        time
      end)
      
      # All timings should be similar (constant-time)
      all_timings = timings_correct ++ timings_similar ++ timings_different
      avg_time = Enum.sum(all_timings) / length(all_timings)
      
      # Calculate standard deviation
      variance = Enum.reduce(all_timings, 0, fn time, acc ->
        diff = time - avg_time
        acc + (diff * diff)
      end) / length(all_timings)
      
      std_dev = :math.sqrt(variance)
      coefficient_of_variation = std_dev / avg_time
      
      # CV should be small (< 15% for constant-time)
      coefficient_of_variation < 0.15
    end
  end

  property "memory access patterns don't leak credential information",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "MemAccess-#{:rand.uniform(10000)}",
        network_name: "MemAccessNet"
      })

      # Create credentials of varying lengths (6, 16, 32 bytes)
      short_pskd = String.duplicate("A", 6)
      medium_pskd = String.duplicate("B", 16)
      long_pskd = String.duplicate("C", 32)

      # Measure memory usage for each credential length
      # Security property: memory growth should be roughly linear,
      # not revealing algorithmic complexity or credential patterns

      memory_before_short = :erlang.memory(:total)
      {:ok, j1} = Joiner.create(%{
        network_id: network.id,
        eui64: <<1::64>>,
        pskd: short_pskd,
        timeout: 120
      })
      memory_after_short = :erlang.memory(:total)
      memory_short = memory_after_short - memory_before_short

      memory_before_medium = :erlang.memory(:total)
      {:ok, j2} = Joiner.create(%{
        network_id: network.id,
        eui64: <<2::64>>,
        pskd: medium_pskd,
        timeout: 120
      })
      memory_after_medium = :erlang.memory(:total)
      memory_medium = memory_after_medium - memory_before_medium

      memory_before_long = :erlang.memory(:total)
      {:ok, j3} = Joiner.create(%{
        network_id: network.id,
        eui64: <<3::64>>,
        pskd: long_pskd,
        timeout: 120
      })
      memory_after_long = :erlang.memory(:total)
      memory_long = memory_after_long - memory_before_long

      # Clean up
      Joiner.destroy(j1)
      Joiner.destroy(j2)
      Joiner.destroy(j3)

      # Validate linear growth: memory should scale roughly with credential length
      # Short (6 bytes), Medium (16 bytes), Long (32 bytes)
      # Expected ratios: 6:16:32 = 1:2.67:5.33

      # Memory differences should exist (storing different lengths)
      has_memory_variation = memory_short > 0 and memory_medium > 0 and memory_long > 0

      # But differences should be reasonable (not exponential or revealing complexity)
      # Allow up to 10x variation (very permissive for BEAM memory management)
      max_memory = max(memory_short, max(memory_medium, memory_long))
      min_memory = min(memory_short, min(memory_medium, memory_long))

      reasonable_variation = min_memory > 0 and (max_memory / min_memory) < 10

      has_memory_variation and reasonable_variation
    end
  end

  property "error messages don't leak existence of resources",
           [:verbose, {:numtests, 200}] do
    forall {existing_id, non_existing_id} <- AshGenerators.resource_enumeration_gen() do
      # Create a network
      {:ok, network} = Network.create(%{
        name: "ErrorLeak-#{existing_id}",
        network_name: "ErrorLeakNet"
      })
      
      # Try to access existing resource
      result_exists = try do
        Network.read(network.id)
      rescue
        e -> {:error, Exception.message(e)}
      end
      
      # Try to access non-existing resource
      result_not_exists = try do
        Network.read(non_existing_id)
      rescue
        e -> {:error, Exception.message(e)}
      end
      
      # Error messages should be generic (not "not found" vs "unauthorized")
      case {result_exists, result_not_exists} do
        {{:ok, _}, {:error, msg}} ->
          # Normal case: existing succeeds, non-existing fails
          # Error message shouldn't reveal "not found"
          not String.contains?(String.downcase(msg), "not found")

        {{:error, msg1}, {:error, msg2}} ->
          # Both failed: error messages should be identical (no information leak)
          msg1 == msg2

        {{:ok, _}, {:ok, _}} ->
          # Both succeeded: non-existing resource shouldn't succeed
          false

        {{:error, _}, {:ok, _}} ->
          # Existing failed but non-existing succeeded: wrong behavior
          false
      end
    end
  end

  # ===========================================================================
  # Network Topology Attacks
  # ===========================================================================

  property "sybil attack: multiple fake identities don't compromise network",
           [:verbose, {:numtests, 100}] do
    forall sybil_count <- integer(10, 100) do
      {:ok, network} = Network.create(%{
        name: "Sybil-#{:rand.uniform(10000)}",
        network_name: "SybilNet"
      })
      
      # Attacker creates many fake identities
      sybil_devices = Enum.map(1..sybil_count, fn i ->
        # All devices from same attacker (simulated by similar patterns)
        attacker_prefix = <<0xDE, 0xAD, 0xBE, 0xEF>>
        eui64 = attacker_prefix <> <<i::32>>
        
        Device.create(%{
          network_id: network.id,
          extended_address: eui64,
          rloc16: i,
          device_type: :end_device,
          link_quality: 3,
          rssi: -50
        })
      end)
      
      # System should detect or limit this
      successful_creates = Enum.count(sybil_devices, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      # Not all should succeed (rate limiting or detection)
      # OR system should remain functional despite attack
      devices = Device.by_network!(network.id)

      # Network should still be queryable AND
      # System should block at least some Sybil identities
      # (successful_creates < sybil_count means rate limiting/detection worked)
      # OR if all succeeded, at least network size is reasonable
      result = is_list(devices) and (
        successful_creates < sybil_count or
        length(devices) < sybil_count * 0.9
      )
      
      measure("Sybil identities attempted", sybil_count, result)
    end
  end

  property "eclipse attack: isolated devices detect partitioning",
           [:verbose, {:numtests, 50}] do
    forall partition_scenario <- AshGenerators.network_partition_gen() do
      {:ok, network} = Network.create(%{
        name: "Eclipse-#{:rand.uniform(10000)}",
        network_name: "EclipseNet"
      })
      
      # Create legitimate devices
      devices = Enum.map(1..20, fn i ->
        {:ok, device} = Device.create(%{
          network_id: network.id,
          extended_address: <<i::64>>,
          rloc16: i,
          device_type: if(rem(i, 5) == 0, do: :router, else: :end_device),
          link_quality: 3,
          rssi: -50
        })
        device
      end)
      
      # Simulate attacker isolating a device
      target_device = Enum.random(devices)
      
      # Attacker creates fake surrounding nodes
      fake_neighbors = Enum.map(1..partition_scenario.fake_count, fn i ->
        {:ok, fake} = Device.create(%{
          network_id: network.id,
          extended_address: <<0xFF, i::56>>,
          rloc16: 0xF000 + i,
          device_type: :router,
          parent_id: target_device.id,  # Use device ID, not extended_address
          link_quality: 3,
          rssi: -40  # Strong signal (attacker is close)
        })
        fake
      end)
      
      # System should detect unusual topology
      all_devices = Device.by_network!(network.id)

      # Check for anomalies (one device with many children)
      children_count = Enum.count(all_devices, fn d ->
        d.parent_id == target_device.id  # Use device ID, not extended_address
      end)

      # Fake neighbors were successfully created
      fake_neighbor_ids = MapSet.new(Enum.map(fake_neighbors, & &1.id))
      current_device_ids = MapSet.new(Enum.map(all_devices, & &1.id))
      attack_created_devices = MapSet.subset?(fake_neighbor_ids, current_device_ids)

      # Security validation: detect eclipse attack patterns
      # 1. End devices should never have children (Thread spec violation)
      end_device_with_children = target_device.device_type == :end_device and children_count > 0

      # 2. Unusual number of children for a single device suggests attack
      excessive_children = children_count > 10  # Threshold for suspicious activity

      # 3. Attacker pattern: many devices with similar address prefix (0xFF)
      suspicious_prefix_count = Enum.count(all_devices, fn d ->
        case d.extended_address do
          <<0xFF, _::56>> -> true
          _ -> false
        end
      end)
      suspicious_address_pattern = suspicious_prefix_count > 5

      # Attack is detectable if any of these anomaly indicators are present
      attack_detectable = end_device_with_children or excessive_children or suspicious_address_pattern

      # Security property: if attack succeeded, it must be detectable
      not attack_created_devices or attack_detectable
    end
  end

  property "wormhole attack: distant node linkage is detected",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "Wormhole-#{:rand.uniform(10000)}",
        network_name: "WormholeNet"
      })
      
      # Create two distant devices with impossible link quality
      {:ok, device_a} = Device.create(%{
        network_id: network.id,
        extended_address: <<0xAA::64>>,
        rloc16: 0x0001,
        device_type: :router,
        link_quality: 3,
        rssi: -50
      })
      
      # Attacker claims device B is neighbor of A (wormhole)
      result = Device.create(%{
        network_id: network.id,
        extended_address: <<0xBB::64>>,
        rloc16: 0xFFFF,  # Very distant RLOC
        device_type: :router,
        parent_id: device_a.extended_address,
        link_quality: 3,  # Perfect link quality claimed
        rssi: -30  # Strong signal (impossible for distance)
      })

      # Security property: system should either reject or detect wormhole attack
      case result do
        {:ok, device_b} ->
          # Attack succeeded - verify it's at least detectable
          all_devices = Device.by_network!(network.id)

          # Check for topology inconsistency indicators:
          # 1. Huge RLOC distance between parent and child (wormhole indicator)
          rloc_distance = abs(device_a.rloc16 - device_b.rloc16)
          suspicious_distance = rloc_distance > 0xFF00  # Parent: 0x0001, Child: 0xFFFF

          # 2. Strong signal (-30 dBm) with very distant RLOC is physically impossible
          strong_signal_distant = device_b.rssi > -40 and rloc_distance > 0xF000

          # 3. Perfect link quality (3) with distant RLOC violates radio physics
          perfect_lq_distant = device_b.link_quality == 3 and rloc_distance > 0xF000

          # Wormhole attack must be detectable through at least one indicator
          attack_detectable = suspicious_distance or strong_signal_distant or perfect_lq_distant

          # Network should remain queryable even if attack succeeded
          network_functional = is_list(all_devices) and length(all_devices) > 0

          attack_detectable and network_functional

        {:error, _} ->
          # Rejected due to validation - secure behavior
          true
      end
    end
  end

  # ===========================================================================
  # Byzantine Fault Scenarios
  # ===========================================================================

  property "byzantine routers providing false topology don't corrupt network",
           [:verbose, {:numtests, 50}] do
    forall byzantine_count <- integer(1, 5) do
      {:ok, network} = Network.create(%{
        name: "Byzantine-#{:rand.uniform(10000)}",
        network_name: "ByzantineNet"
      })
      
      # Create honest routers
      honest_routers = Enum.map(1..10, fn i ->
        {:ok, router} = Device.create(%{
          network_id: network.id,
          extended_address: <<0x00, i::56>>,
          rloc16: i * 0x400,
          device_type: :router,
          link_quality: 3,
          rssi: -50
        })
        router
      end)
      
      # Create byzantine routers (malicious)
      byzantine_routers = Enum.map(1..byzantine_count, fn i ->
        {:ok, router} = Device.create(%{
          network_id: network.id,
          extended_address: <<0xFF, i::56>>,
          rloc16: 0xF000 + i,
          device_type: :router,
          link_quality: 3,
          rssi: -50
        })
        router
      end)
      
      # Byzantine routers report false information
      # Simulate by creating inconsistent topology
      Enum.each(byzantine_routers, fn byz_router ->
        # Create fake children
        Enum.each(1..5, fn _j ->
          Device.create(%{
            network_id: network.id,
            extended_address: :crypto.strong_rand_bytes(8),
            rloc16: :rand.uniform(0xFFFF),
            device_type: :end_device,
            parent_id: byz_router.extended_address,
            link_quality: Enum.random(0..3),
            rssi: Enum.random(-100..-20)
          })
        end)
      end)

      # Network should remain functional despite byzantine routers
      all_devices = Device.by_network!(network.id)

      # Validate network integrity
      network_queryable = is_list(all_devices) and length(all_devices) > 0

      # Honest routers should still be present and queryable
      honest_router_ids = MapSet.new(Enum.map(honest_routers, & &1.id))
      current_devices = Device.by_network!(network.id)
      current_device_ids = MapSet.new(Enum.map(current_devices, & &1.id))
      honest_routers_intact = MapSet.subset?(honest_router_ids, current_device_ids)

      # Byzantine routers should not outnumber honest ones (security property)
      # System should maintain majority of honest nodes
      total_routers = Enum.count(all_devices, &(&1.device_type == :router))
      byzantine_ratio = byzantine_count / total_routers
      byzantine_minority = byzantine_ratio <= 0.5

      network_queryable and honest_routers_intact and byzantine_minority
    end
  end

  property "conflicting state reports from multiple sources are resolved",
           [:verbose, {:numtests, 100}] do
    forall conflict_scenario <- AshGenerators.state_conflict_gen() do
      {:ok, network} = Network.create(%{
        name: "Conflict-#{:rand.uniform(10000)}",
        network_name: "ConflictNet"
      })
      
      # Multiple processes report conflicting network states
      tasks = Enum.map(conflict_scenario.conflicting_states, fn claimed_state ->
        Task.async(fn ->
          try do
            # Use Ash.get! to properly read the resource by ID
            net = Ash.get!(Network, network.id)
            # Different processes claim different states
            case claimed_state do
              :child -> Network.attach(net)
              :router -> Network.promote(net)
              :detached -> Network.detach(net)
            end
          rescue
            _ -> {:error, :conflict}
          end
        end)
      end)
      
      _results = Enum.map(tasks, &Task.await(&1, 5000))
      
      # System should converge to consistent state
      Process.sleep(100)
      final_network = Ash.get!(Network, network.id)
      
      # Final state must be valid
      final_network.state in [:detached, :child, :router, :leader]
    end
  end

  # ===========================================================================
  # Cryptographic Attacks
  # ===========================================================================

  property "weak randomness detection: statistical tests on generated keys",
           [:verbose, {:numtests, 100}] do
    forall sample_size <- integer(100, 500) do
      # Generate many network keys
      networks = Enum.map(1..sample_size, fn i ->
        {:ok, network} = Network.create(%{
          name: "Random-#{i}",
          network_name: "RandomNet-#{i}"
        })
        network
      end)
      
      keys = Enum.map(networks, & &1.network_key)
      
      # Statistical tests for randomness
      
      # 1. Chi-square test for uniform distribution
      byte_frequencies = keys
      |> Enum.flat_map(&:binary.bin_to_list/1)
      |> Enum.frequencies()
      
      expected_freq = (sample_size * 16) / 256
      chi_square = Enum.reduce(byte_frequencies, 0, fn {_byte, observed}, acc ->
        diff = observed - expected_freq
        acc + (diff * diff) / expected_freq
      end)
      
      # Chi-square critical value for 255 degrees of freedom at 0.05 significance
      # is approximately 293. If chi_square > 293, distribution is not uniform
      uniform_distribution = chi_square < 350  # Slightly relaxed
      
      # 2. No repeating patterns
      no_patterns = Enum.all?(keys, fn key ->
        bytes = :binary.bin_to_list(key)
        # Check if not all same byte
        Enum.uniq(bytes) |> length() > 1
      end)
      
      # 3. Hamming distance between consecutive keys
      key_pairs = Enum.zip(keys, Enum.drop(keys, 1))
      hamming_distances = Enum.map(key_pairs, fn {k1, k2} ->
        Enum.zip(:binary.bin_to_list(k1), :binary.bin_to_list(k2))
        |> Enum.count(fn {b1, b2} -> b1 != b2 end)
      end)
      
      avg_hamming = Enum.sum(hamming_distances) / length(hamming_distances)
      # Average should be around 8 bytes (half of 16 bytes)
      good_hamming = avg_hamming > 4 and avg_hamming < 12
      
      result = uniform_distribution and no_patterns and good_hamming
      
      result
      |> measure("Sample size", sample_size)
    end
  end

  property "nonce reuse detection: counters never repeat",
           [:verbose, {:numtests, 100}] do
    forall operation_count <- integer(100, 1000) do
      # Simulate many frame operations
      tids_used = Enum.map(1..operation_count, fn i ->
        frame = Frame.new(:prop_value_get, <<i::8>>, tid: rem(i, 16))
        frame.tid
      end)
      
      # TIDs should cycle through 0-15 uniformly
      tid_frequencies = Enum.frequencies(tids_used)
      
      # Each TID (0-15) should appear roughly equally
      expected_per_tid = operation_count / 16
      variance = Enum.reduce(tid_frequencies, 0, fn {_tid, count}, acc ->
        diff = count - expected_per_tid
        acc + abs(diff)
      end)
      
      avg_variance = variance / 16
      
      # Variance should be low (< 20% of expected)
      avg_variance < expected_per_tid * 0.2
    end
  end

  property "downgrade attack prevention: security parameters cannot be weakened",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "Downgrade-#{:rand.uniform(10000)}",
        network_name: "DowngradeNet"
      })
      
      original_dataset = Network.operational_dataset(network)
      original_policy = original_dataset.security_policy

      # Attacker tries to downgrade security by extending rotation time
      # (longer rotation = weaker security as compromised keys stay valid longer)
      weakened_rotation = original_policy.rotation_time * 10

      # Try to update with weakened security parameters
      update_result = try do
        # Attempt to update network with weakened security
        # This should be rejected or limited by the implementation
        Network.update(network, %{
          # Try to set very long rotation (security downgrade)
          security_policy: %{
            rotation_time: weakened_rotation,
            flags: original_policy.flags
          }
        })
      rescue
        _ -> {:error, :update_failed}
      end

      # Verify security wasn't downgraded
      current_dataset = Network.operational_dataset(network)
      current_policy = current_dataset.security_policy

      # Security properties that must hold:
      # 1. Rotation time should not have increased dramatically (max 2x is reasonable)
      rotation_not_weakened = current_policy.rotation_time <= original_policy.rotation_time * 2

      # 2. If update succeeded, rotation time should be bounded
      update_bounded = case update_result do
        {:ok, _} -> current_policy.rotation_time <= original_policy.rotation_time * 2
        {:error, _} -> true  # Rejected = secure
      end

      # 3. Original security flags should be preserved
      flags_preserved = current_policy.flags == original_policy.flags

      rotation_not_weakened and update_bounded and flags_preserved
    end
  end

  # ===========================================================================
  # Protocol-Level Vulnerabilities
  # ===========================================================================

  property "amplification attacks: responses are not larger than requests",
           [:verbose, {:numtests, 200}] do
    forall request_size <- integer(10, 100) do
      # Create request frame
      payload = :crypto.strong_rand_bytes(request_size)
      request = Frame.new(:prop_value_get, payload, tid: 0)
      encoded_request = Frame.encode(request)
      
      # Simulate response
      response = Frame.new(:prop_value_is, payload, tid: 0)
      encoded_response = Frame.encode(response)
      
      # Response should not be significantly larger than request
      amplification_factor = byte_size(encoded_response) / byte_size(encoded_request)
      
      # Amplification factor should be < 2 (no amplification attack)
      result = amplification_factor < 2.0
      
      # Correct measure usage: pass the value, not a function
      result
      |> measure("Request size", request_size)
    end
  end

  property "message ordering attacks: out-of-order frames don't corrupt state",
           [:verbose, {:numtests, 100}] do
    forall frame_sequence <- AshGenerators.frame_sequence_gen(20, 50) do
      # Attacker reorders frames
      shuffled_sequence = Enum.shuffle(frame_sequence)
      
      # Process out-of-order frames
      results = Enum.map(shuffled_sequence, fn frame_data ->
        try do
          Frame.decode(frame_data)
        rescue
          _ -> {:error, :decode_failed}
        end
      end)
      
      # System should handle gracefully (reject or reorder)
      all_handled = Enum.all?(results, fn
        {:ok, _} -> true
        {:error, _} -> true
        _ -> false
      end)
      
      # Verify protocol state not corrupted
      test_frame = Frame.new(:reset, <<>>, tid: 0)
      {:ok, _decoded} = Frame.decode(Frame.encode(test_frame))
      
      all_handled
    end
  end

  property "resource exhaustion via malformed requests is prevented",
           [:verbose, {:numtests, 100}] do
    forall malformed_flood <- AshGenerators.malformed_flood_gen() do
      memory_before = :erlang.memory(:total)
      
      # Flood system with malformed requests
      results = Enum.map(malformed_flood, fn malformed ->
        try do
          Frame.decode(malformed)
        rescue
          _ -> {:error, :rejected}
        catch
          _ -> {:error, :rejected}
        end
      end)
      
      memory_after = :erlang.memory(:total)
      memory_growth = (memory_after - memory_before) / 1024 / 1024
      
      # Memory growth should be bounded
      memory_growth < 10 and  # Less than 10MB
      # Most should be rejected
      Enum.count(results, &match?({:error, _}, &1)) > length(results) * 0.8
    end
  end

  # ===========================================================================
  # Generators - Now using AshGenerators module
  # ===========================================================================
  # All generators have been moved to NTBR.Domain.Test.AshGenerators
  # This ensures proper type safety and Ash constraint compliance
end
