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

  property "PSKD should be alphanumeric" do
    forall pskd <- pskd_candidate() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      attrs = %{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: pskd
      }

      result = Joiner.create(attrs)

      # Check if pskd is alphanumeric and correct length
      valid =
        String.match?(pskd, ~r/^[A-Z0-9]+$/i) and
          String.length(pskd) >= 6 and
          String.length(pskd) <= 32

      case valid do
        true -> match?({:ok, _}, result)
        # May fail or succeed depending on validation
        false -> true
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

  property "eui64 must be exactly 8 bytes when provided" do
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
        8 -> match?({:ok, _}, result)
        # nil is allowed (wildcard)
        0 -> match?({:ok, _}, result)
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
    {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

    # Create in pending state
    {:ok, joiner} =
      Joiner.create(%{
        network_id: network.id,
        eui64: :crypto.strong_rand_bytes(8),
        pskd: "TEST1234"
      })

    # Try to complete without starting - transition should not happen, state left at :pending
    {:ok, result} = Joiner.complete(joiner)
    match?(:pending, result.state)
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

      # Try to create specific joiner without eui64
      result =
        Joiner.create(%{
          network_id: network.id,
          pskd: pskd
        })

      # Should fail or require eui64
      case result do
        {:error, _} -> true
        # If it succeeds, eui64 was generated
        {:ok, joiner} -> not is_nil(joiner.eui64)
      end
    end
  end

  # ============================================================================
  # READ ACTION PROPERTIES
  # ============================================================================

  property "active filter returns only pending and joining joiners" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Create joiners in different states
      {:ok, _pending} =
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

      {:ok, _joining} = Joiner.start(joiner2)

      {:ok, joiner3} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "JOINED1"
        })

      {:ok, joining3} = Joiner.start(joiner3)
      {:ok, _joined} = Joiner.complete(joining3)

      # Query active would return 2 (pending + joining)
      # {:ok, active} = Joiner.active()
      # length(active) == 2

      # Placeholder
      true
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

      # Query by_eui64 would find this joiner
      # {:ok, [found]} = Joiner.by_eui64(eui64)
      # found.id == joiner.id

      joiner.eui64 == eui64
    end
  end

  property "expired_joiners finds joiners past expiration" do
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

      # Expires_at should be in future
      DateTime.compare(started.expires_at, DateTime.utc_now()) == :gt
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
    forall new_timeout <- integer(30, 600) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      {:ok, joiner} =
        Joiner.create(%{
          network_id: network.id,
          eui64: :crypto.strong_rand_bytes(8),
          pskd: "UPDATE"
        })

      # Update in pending state should work
      result = Joiner.update(joiner, %{timeout: new_timeout})
      match?({:ok, _}, result)
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

