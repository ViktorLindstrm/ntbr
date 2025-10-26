defmodule NTBR.Domain.Resources.JoinerPropertyTest do
  @moduledoc false
  # Property-based tests for Joiner resource.
  #
  # Tests commissioning workflow and state machine transitions.
  #
  # Progression:
  # 1. Basic CRUD operations
  # 2. PSKD validation
  # 3. State machine transitions
  # 4. Timeout/expiration logic
  # 5. Wildcard vs specific joiners
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Resources.{Joiner, Network}

  @moduletag :property
  @moduletag :joiner

  # ============================================================================
  # BASIC PROPERTIES - CRUD
  # ============================================================================

  property "joiner can be created with valid attributes" do
    forall attrs <- valid_joiner_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      case Joiner.create(attrs) do
        {:ok, joiner} ->
          pskd_match = joiner.pskd == attrs.pskd
          eui_match = joiner.eui64 == attrs.eui64
          state_match = joiner.state == :pending
          timeout_match = joiner.timeout == attrs.timeout

          pskd_match and eui_match and state_match and timeout_match

        {:error, _} ->
          false
      end
    end
  end

  property "joiner starts in pending state" do
    forall attrs <- minimal_joiner_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      {:ok, joiner} = Joiner.create(attrs)
      joiner.state == :pending
    end
  end

  property "joiner uses default timeout when not specified" do
    forall pskd <- valid_pskd() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: pskd
        })

      # Default
      joiner.timeout == 120
    end
  end

  property "joiner can be destroyed" do
    forall attrs <- valid_joiner_attrs() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      attrs = Map.put(attrs, :network_id, network.id)

      {:ok, joiner} = Joiner.create(attrs)

      case Joiner.destroy(joiner) do
        :ok -> true
        {:ok, _} -> true
        {:error, _} -> false
      end
    end
  end

  # ============================================================================
  # PSKD CONSTRAINT PROPERTIES
  # ============================================================================

  property "PSKD must be between 6 and 32 characters" do
    forall pskd_len <- integer(0, 50) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      pskd = random_alphanumeric(pskd_len)

      attrs = %{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: pskd
      }

      result = Joiner.create(attrs)

      case pskd_len do
        n when n >= 6 and n <= 32 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "PSKD validation matches implementation constraints" do
    forall pskd <- pskd_candidate() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      attrs = %{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: pskd
      }

      result = Joiner.create(attrs)

      # Implementation only validates length (joiner.ex:82)
      # NOTE: Description says "base32" but no character validation is implemented
      pskd_len = String.length(pskd)
      valid_length = pskd_len >= 6 and pskd_len <= 32

      case valid_length do
        true -> match?({:ok, _}, result)
        false -> match?({:error, _}, result)
      end
    end
  end

  property "timeout must be between 30 and 600 seconds" do
    forall timeout <- integer(-10, 1000) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      attrs = %{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: "VALID123",
        timeout: timeout
      }

      result = Joiner.create(attrs)

      case timeout do
        t when t >= 30 and t <= 600 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "eui64 must be exactly 8 bytes for create action" do
    forall eui_size <- integer(0, 16) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      eui64 = if eui_size > 0, do: :crypto.strong_rand_bytes(eui_size), else: nil

      attrs = %{
        network_id: network.id,
        eui64: eui64,
        pskd: "VALID123"
      }

      result = Joiner.create(attrs)

      case eui_size do
        # Only 8 bytes is valid for :create action (joiner.ex:315-319)
        8 -> match?({:ok, _}, result)
        # nil requires :create_any action for wildcard joiners
        _ -> match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # STATE MACHINE PROPERTIES
  # ============================================================================

  property "start transition sets started_at and expires_at" do
    forall {pskd, timeout} <- {valid_pskd(), integer(30, 600)} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: pskd,
          timeout: timeout
        })

      {:ok, started} = Joiner.start(joiner)

      state_match = started.state == :joining
      has_started = not is_nil(started.started_at)
      has_expires = not is_nil(started.expires_at)
      timeout_correct = DateTime.diff(started.expires_at, started.started_at, :second) == timeout

      state_match and has_started and has_expires and timeout_correct
    end
  end

  property "complete transition sets completed_at" do
    forall pskd <- valid_pskd() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: pskd
        })

      {:ok, joining} = Joiner.start(joiner)
      {:ok, completed} = Joiner.complete(joining)

      state_match = completed.state == :joined
      has_completed = not is_nil(completed.completed_at)

      state_match and has_completed
    end
  end

  property "fail transition is valid from pending or joining" do
    forall initial_state <- oneof([:pending, :joining]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "TEST1234"
        })

      # Get to initial state
      joiner =
        case initial_state do
          :pending ->
            joiner

          :joining ->
            {:ok, j} = Joiner.start(joiner)
            j
        end

      {:ok, failed} = Joiner.fail(joiner)
      failed.state == :failed
    end
  end

  property "expire transition is valid from pending or joining" do
    forall initial_state <- oneof([:pending, :joining]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, initial_joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "TEST1234"
        })

      # Get to initial state
      joiner =
        case initial_state do
          :pending ->
            initial_joiner

          :joining ->
            {:ok, joining_joiner} = Joiner.start(initial_joiner)
            joining_joiner
        end

      {:ok, expired} = Joiner.expire(joiner)
      expired.state == :expired
    end
  end

  property "complete is only valid from joining state" do
    forall invalid_state <- oneof([:pending, :failed, :expired, :joined]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create joiner
      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "TEST1234"
        })

      # Put joiner in invalid state for complete transition
      joiner =
        case invalid_state do
          :pending ->
            # Already in pending
            joiner

          :failed ->
            {:ok, failed} = Joiner.fail(joiner)
            failed

          :expired ->
            {:ok, expired} = Joiner.expire(joiner)
            expired

          :joined ->
            # Start then complete to get to joined state
            {:ok, joining} = Joiner.start(joiner)
            {:ok, joined} = Joiner.complete(joining)
            joined
        end

      # Try to complete from invalid state - should fail
      result = Joiner.complete(joiner)
      match?({:error, _}, result)
    end
  end

  # ============================================================================
  # WILDCARD JOINER PROPERTIES
  # ============================================================================

  property "create_any creates wildcard joiner with nil eui64" do
    forall pskd <- valid_pskd() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create_any(%{
          network_id: network.id,
          pskd: pskd,
          timeout: 120
        })

      is_nil(joiner.eui64)
    end
  end

  property "specific joiner requires eui64" do
    forall pskd <- valid_pskd() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Try to create specific joiner without eui64 - should fail
      result =
        Joiner.create(%{
          network_id: network.id,
          pskd: pskd
        })

      # Must fail with error - eui64 is required for create action (joiner.ex:315-316)
      # Use create_any for wildcard joiners
      match?({:error, _}, result)
    end
  end

  # ============================================================================
  # READ ACTION PROPERTIES
  # ============================================================================

  property "active filter returns only pending and joining joiners" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create joiners in different states
      {:ok, pending} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "PENDING1"
        })

      {:ok, joiner2} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "JOINING1"
        })

      {:ok, joining} = Joiner.start(joiner2)

      {:ok, joiner3} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "JOINED1"
        })

      {:ok, joining3} = Joiner.start(joiner3)
      {:ok, _joined} = Joiner.complete(joining3)

      # Query active joiners - should return only pending and joining (not joined)
      {:ok, active} = Joiner.active()

      # Should have exactly 2 active joiners
      count_match = length(active) == 2

      # Should contain our pending and joining joiners
      active_ids = Enum.map(active, & &1.id) |> MapSet.new()
      has_pending = MapSet.member?(active_ids, pending.id)
      has_joining = MapSet.member?(active_ids, joining.id)

      # All active joiners should be in pending or joining state
      all_active_states = Enum.all?(active, fn j -> j.state in [:pending, :joining] end)

      count_match and has_pending and has_joining and all_active_states
    end
  end

  property "by_eui64 finds specific joiner" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      eui64 = :crypto.strong_rand_bytes(8)

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: eui64,
          pskd: "FINDME"
        })

      # Create another joiner with different EUI-64 to ensure query is specific
      {:ok, _other} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "OTHER"
        })

      # Query by_eui64 should find only the specific joiner
      {:ok, found} = Joiner.by_eui64(eui64)

      # Should find exactly one joiner
      count_match = length(found) == 1

      # Should be the correct joiner
      first = List.first(found)
      id_match = first.id == joiner.id
      eui_match = first.eui64 == eui64

      count_match and id_match and eui_match
    end
  end

  property "start action sets expires_at to future time based on timeout" do
    forall timeout <- integer(30, 600) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "EXPIRE",
          timeout: timeout
        })

      {:ok, started} = Joiner.start(joiner)

      # Expires_at should be in future (started_at + timeout)
      in_future = DateTime.compare(started.expires_at, DateTime.utc_now()) == :gt

      # Verify expires_at is correctly calculated from timeout
      expected_diff = timeout
      actual_diff = DateTime.diff(started.expires_at, started.started_at, :second)
      correct_timeout = actual_diff == expected_diff

      in_future and correct_timeout
    end
  end

  # ============================================================================
  # ADVANCED PROPERTIES - Commissioning Workflow
  # ============================================================================

  property "complete commissioning workflow maintains data integrity" do
    forall {pskd, timeout, vendor_info} <-
             {valid_pskd(), integer(30, 600), vendor_info_gen()} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      eui64 = :crypto.strong_rand_bytes(8)

      # Create joiner
      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: eui64,
          pskd: pskd,
          timeout: timeout,
          vendor_name: vendor_info.name,
          vendor_model: vendor_info.model
        })

      # Start joining
      {:ok, joining} = Joiner.start(joiner)

      # Complete joining
      {:ok, completed} = Joiner.complete(joining)

      # Verify data preserved through transitions
      eui_match = completed.eui64 == eui64
      pskd_match = completed.pskd == pskd
      vendor_name_match = completed.vendor_name == vendor_info.name
      vendor_model_match = completed.vendor_model == vendor_info.model
      timeout_match = completed.timeout == timeout

      eui_match and pskd_match and vendor_name_match and vendor_model_match and timeout_match
    end
  end

  property "joiner can be updated only in active states" do
    forall {state_type, new_timeout} <- {oneof([:active, :inactive]), integer(30, 600)} do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "UPDATE"
        })

      # Get joiner into the desired state
      joiner =
        case state_type do
          :active ->
            # Test both active states: pending (already there) or joining
            if :rand.uniform(2) == 1 do
              joiner  # Keep in pending
            else
              {:ok, joining} = Joiner.start(joiner)
              joining
            end

          :inactive ->
            # Test inactive states: joined, failed, or expired
            case :rand.uniform(3) do
              1 ->
                {:ok, joining} = Joiner.start(joiner)
                {:ok, joined} = Joiner.complete(joining)
                joined

              2 ->
                {:ok, failed} = Joiner.fail(joiner)
                failed

              3 ->
                {:ok, expired} = Joiner.expire(joiner)
                expired
            end
        end

      # Try to update
      result = Joiner.update(joiner, %{timeout: new_timeout})

      # Verify according to state (joiner.ex:389-397)
      case state_type do
        :active -> match?({:ok, _}, result)
        :inactive -> match?({:error, _}, result)
      end
    end
  end

  property "multiple joiners can coexist for same network" do
    forall count <- integer(2, 10) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      joiners =
        Enum.map(1..count, fn i ->
          {:ok, joiner} =
            Joiner.create(%{
              network_id: network.id,
              eui64: :crypto.strong_rand_bytes(8),
              pskd: "JOINER#{i}"
            })

          joiner
        end)

      # All have unique IDs
      ids = Enum.map(joiners, & &1.id)
      unique_ids = length(ids) == length(Enum.uniq(ids))

      # All have unique EUI64s
      eui64s = Enum.map(joiners, & &1.eui64)
      unique_eui64s = length(eui64s) == length(Enum.uniq(eui64s))

      unique_ids and unique_eui64s
    end
  end

  # ============================================================================
  # GENERATORS
  # ============================================================================

  defp valid_joiner_attrs do
    let {pskd, timeout} <- {valid_pskd(), integer(30, 600)} do
      %{
        eui64: :crypto.strong_rand_bytes(8),
        pskd: pskd,
        timeout: timeout
      }
    end
  end

  defp minimal_joiner_attrs do
    %{
      eui64: :crypto.strong_rand_bytes(8),
      pskd: "MINIMAL123"
    }
  end

  defp valid_pskd do
    let len <- integer(6, 32) do
      random_alphanumeric(len)
    end
  end

  defp pskd_candidate do
    oneof([
      valid_pskd(),
      # Too short
      "SHORT",
      # Too long
      String.duplicate("A", 50),
      # Special chars
      "INVALID!@#",
      # Spaces
      "SPACE HERE",
      # Empty
      ""
    ])
  end

  defp vendor_info_gen do
    let {name_len, model_len} <- {integer(5, 20), integer(5, 20)} do
      %{
        name: random_alphanumeric(name_len),
        model: random_alphanumeric(model_len)
      }
    end
  end

  defp random_alphanumeric(len) do
    chars = ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    chars
    |> Enum.shuffle()
    |> Enum.take(len)
    |> to_string()
  end
end

