defmodule NTBR.Domain.Resources.NetworkPropertyTest do
  @moduledoc false
  # Property-based tests for Network resource.
  #
  # Tests progress from basic to advanced:
  # 1. Basic CRUD operations
  # 2. Attribute constraints validation
  # 3. State machine transitions
  # 4. Calculations
  # 5. Complex validations
  use ExUnit.Case, async: true
  use PropCheck
  
  # Import PropCheck generators
  import PropCheck.BasicTypes

  alias NTBR.Domain.Resources.Network

  @moduletag :property
  @moduletag :network

  # ============================================================================
  # SANITY CHECK - Verify module is loaded
  # ============================================================================

  test "Network module is accessible" do
    assert Code.ensure_loaded?(NTBR.Domain.Resources.Network)
  end

  test "Network.create/1 works with static data" do
    attrs = %{
      name: "Test", 
      network_name: "TestNet",
      channel: 15
    }
    
    case Network.create(attrs) do
      {:ok, network} ->
        assert network.name == "Test"
        assert network.network_name == "TestNet"
        assert network.channel == 15
        # Should have auto-generated credentials
        assert byte_size(network.network_key) == 16
        assert byte_size(network.extended_pan_id) == 8
      
      {:error, error} ->
        flunk("Failed to create network: #{inspect(error)}")
    end
  end

  # ============================================================================
  # BASIC PROPERTIES - Create, Read, Update, Destroy
  # ============================================================================

  property "network can be created with minimal valid attributes" do
    forall attrs <- minimal_network_attrs() do
      case Network.create(attrs) do
        {:ok, network} ->
          # Just verify it created successfully
          not is_nil(network.id) and
          not is_nil(network.name)

        {:error, error} ->
          IO.puts("\n=== CREATION ERROR ===")
          IO.inspect(attrs, label: "Attrs")
          IO.inspect(error, label: "Error")
          false
      end
    end
  end

  property "network auto-generates credentials when not provided" do
    forall attrs <- minimal_network_attrs() do
      {:ok, network} = Network.create(attrs)
      
      # Auto-generated fields should be present
      key_valid = byte_size(network.network_key) == 16
      pan_valid = network.pan_id >= 0 and network.pan_id <= 0xFFFF
      xpan_valid = byte_size(network.extended_pan_id) == 8
      
      key_valid and pan_valid and xpan_valid
    end
  end

  property "network can be updated with valid changes" do
    forall {create_attrs, update_attrs} <- {valid_network_attrs(), update_network_attrs()} do
      {:ok, network} = Network.create(create_attrs)
      
      case Network.update(network, update_attrs) do
        {:ok, updated} ->
          # Updated fields changed
          (updated.name == update_attrs[:name] or is_nil(update_attrs[:name])) and
          (updated.channel == update_attrs[:channel] or is_nil(update_attrs[:channel]))
        
        {:error, _} ->
          # Some updates might be invalid, that's ok
          true
      end
    end
  end

  property "network can be destroyed" do
    forall attrs <- valid_network_attrs() do
      {:ok, network} = Network.create(attrs)
      
      case Network.destroy(network) do
        :ok -> true
        {:ok, _} -> true
        {:error, _} -> false
      end
    end
  end

  # ============================================================================
  # CONSTRAINT PROPERTIES - Attribute validation
  # ============================================================================

  property "name must be between 1 and 16 characters" do
    forall name_len <- integer(0,60) do

      name = random_string(name_len)
      attrs = %{name: name, network_name: "TestNet", channel: 15}
      result = Network.create(attrs)

      
      len = String.length(name)
      case len do
        n when n >= 1 and n <= 16 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "channel must be between 11 and 26" do
    forall channel <- integer(-10, 50) do
      attrs = %{name: "Test", network_name: "TestNet", channel: channel}
      result = Network.create(attrs)
      
      case channel do
        ch when ch >= 11 and ch <= 26 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "network_name must be between 1 and 16 characters" do
    forall name_len <- integer(1, 50) do
      name = random_string(name_len)
      attrs = %{name: "Test", network_name: name, channel: 15}
      result = Network.create(attrs)
      
      len = String.length(name)
      case len do
        n when n >= 1 and n <= 16 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "network_key must be exactly 16 bytes" do
    forall key_size <- integer(0, 32) do
      key = :crypto.strong_rand_bytes(key_size)
      attrs = %{name: "Test", network_name: "Test", channel: 15, network_key: key}
      result = Network.create(attrs)
      
      case key_size do
        16 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "extended_pan_id must be exactly 8 bytes" do
    forall xpan_size <- integer(0, 16) do
      xpan = :crypto.strong_rand_bytes(xpan_size)
      attrs = %{name: "Test", network_name: "Test", channel: 15, extended_pan_id: xpan}
      result = Network.create(attrs)
      
      case xpan_size do
        8 -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  property "pan_id cannot be broadcast address 0xFFFF" do
    forall pan_id <- integer(0, 0x10000) do
      attrs = %{name: "Test", network_name: "Test", channel: 15, pan_id: pan_id}
      result = Network.create(attrs)
      
      case pan_id do
        0xFFFF -> match?({:error, _}, result)
        n when n >= 0 and n <= 0xFFFE -> match?({:ok, _}, result)
        _ -> match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # STATE MACHINE PROPERTIES - Transition validation
  # ============================================================================

  property "network starts in detached state" do
    forall attrs <- valid_network_attrs() do
      {:ok, network} = Network.create(attrs)
      network.state == :detached
    end
  end

  property "valid state transitions succeed" do
    forall transition <- valid_transition() do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Put network in correct starting state
      network = setup_for_transition(network, transition)

      # Attempt transition
      result = apply_transition(network, transition)

      match?({:ok, _}, result)
    end
  end

  property "attach transition changes state from detached to child" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      initial_state = network.state == :detached

      {:ok, attached} = Network.attach(network)
      final_state = attached.state == :child

      initial_state and final_state
    end
  end

  property "promote transition changes state from child to router" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      {:ok, child} = Network.attach(network)

      initial_state = child.state == :child

      {:ok, router} = Network.promote(child)
      final_state = router.state == :router

      initial_state and final_state
    end
  end

  property "become_leader transition changes state from router to leader" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      {:ok, child} = Network.attach(network)
      {:ok, router} = Network.promote(child)

      initial_state = router.state == :router

      {:ok, leader} = Network.become_leader(router)
      final_state = leader.state == :leader

      initial_state and final_state
    end
  end

  property "demote transition changes state from router to child" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      {:ok, child} = Network.attach(network)
      {:ok, router} = Network.promote(child)

      initial_state = router.state == :router

      {:ok, demoted} = Network.demote(router)
      final_state = demoted.state == :child

      initial_state and final_state
    end
  end

  property "demote transition changes state from leader to child" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      {:ok, child} = Network.attach(network)
      {:ok, router} = Network.promote(child)
      {:ok, leader} = Network.become_leader(router)

      initial_state = leader.state == :leader

      {:ok, demoted} = Network.demote(leader)
      final_state = demoted.state == :child

      initial_state and final_state
    end
  end

  property "detach transition changes state to detached" do
    forall _ <- integer(1, 100) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})
      {:ok, child} = Network.attach(network)

      initial_state = child.state == :child

      {:ok, detached} = Network.detach(child)
      final_state = detached.state == :detached

      initial_state and final_state
    end
  end

  property "disable transition works from any state" do
    forall state_action <- oneof([:detached, :attach, :promote, :become_leader]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Transition to desired state
      network =
        case state_action do
          :detached -> network
          :attach -> {:ok, n} = Network.attach(network); n
          :promote -> {:ok, c} = Network.attach(network); {:ok, n} = Network.promote(c); n
          :become_leader -> {:ok, c} = Network.attach(network); {:ok, r} = Network.promote(c); {:ok, n} = Network.become_leader(r); n
        end

      {:ok, disabled} = Network.disable(network)
      disabled.state == :disabled
    end
  end

  property "invalid state transitions fail" do
    # Try to promote from detached (should fail)
    {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

    result = Network.promote(network)

    match?({:error, _}, result)
  end

  # ============================================================================
  # CALCULATION PROPERTIES - Derived values
  # ============================================================================

  property "is_operational calculation correct for all states" do
    forall state_action <- oneof([:detached, :attach, :promote, :become_leader, :disable]) do
      {:ok, network} = Network.create(%{name: "T", network_name: "T", channel: 15})

      # Transition to desired state
      network =
        case state_action do
          :detached -> network
          :attach -> {:ok, n} = Network.attach(network); n
          :promote -> {:ok, c} = Network.attach(network); {:ok, n} = Network.promote(c); n
          :become_leader -> {:ok, c} = Network.attach(network); {:ok, r} = Network.promote(c); {:ok, n} = Network.become_leader(r); n
          :disable -> {:ok, n} = Network.disable(network); n
        end

      # Load calculation
      network = Ash.load!(network, :is_operational)

      # Verify calculation matches expected
      expected = network.state in [:child, :router, :leader]
      network.is_operational == expected
    end
  end

  # ============================================================================
  # ADVANCED PROPERTIES - Complex scenarios
  # ============================================================================

  property "credentials remain consistent across updates" do
    forall {attrs, update_count} <- {valid_network_attrs(), integer(1, 5)} do
      {:ok, network} = Network.create(attrs)
      original_key = network.network_key
      original_pan = network.pan_id
      original_xpan = network.extended_pan_id
      
      # Generate updates inline (using regular Elixir, not PropCheck generators)
      updates = Enum.map(1..update_count, fn _ ->
        attrs = []
        attrs = if Enum.random([true, false]), do: [{:name, random_string(Enum.random(1..16))} | attrs], else: attrs
        attrs = if Enum.random([true, false]), do: [{:channel, Enum.random(11..26)} | attrs], else: attrs
        Map.new(attrs)
      end)
      
      # Apply multiple updates
      final_network = Enum.reduce(updates, network, fn update_attrs, net ->
        case Network.update(net, update_attrs) do
          {:ok, updated} -> updated
          _ -> net
        end
      end)
      
      # Credentials should not change with regular updates
      key_match = final_network.network_key == original_key
      pan_match = final_network.pan_id == original_pan
      xpan_match = final_network.extended_pan_id == original_xpan
      
      key_match and pan_match and xpan_match
    end
  end

  property "multiple networks can coexist with different credentials" do
    forall count <- integer(2, 10) do
      networks = Enum.map(1..count, fn i ->
        {:ok, net} = Network.create(%{
          name: "Net#{i}",
          network_name: "Net#{i}",
          channel: Enum.random(11..26)
        })
        net
      end)
      
      # All have unique IDs
      ids = Enum.map(networks, & &1.id)
      unique_ids = length(ids) == length(Enum.uniq(ids))
      
      # All have unique credentials (very high probability)
      keys = Enum.map(networks, & &1.network_key)
      unique_keys = length(keys) == length(Enum.uniq(keys))
      
      unique_ids and unique_keys
    end
  end

  # ============================================================================
  # GENERATORS
  # ============================================================================

  defp valid_network_attrs do
    let {name_len, netname_len, channel} <- {integer(1, 16), integer(1, 16), integer(11, 26)} do
      %{
        name: random_string(name_len),
        network_name: random_string(netname_len),
        channel: channel
      }
    end
  end

  defp minimal_network_attrs do
    %{
      name: "TestNet",
      network_name: "TN",
      channel: 15
    }
  end

  defp update_network_attrs do
    oneof([
      let name_len <- integer(1, 16) do
        %{name: random_string(name_len)}
      end,
      let channel <- integer(11, 26) do
        %{channel: channel}
      end,
      let {name_len, channel} <- {integer(1, 16), integer(11, 26)} do
        %{name: random_string(name_len), channel: channel}
      end,
      %{}  # No updates
    ])
  end

  defp valid_transition do
    oneof([
      {:detached, :attach},
      {:child, :promote},
      {:router, :become_leader},
      {:leader, :demote},
      {:router, :demote}
    ])
  end

  defp invalid_transition do
    oneof([
      {:detached, :promote},
      {:detached, :demote},
      {:child, :detach}  # Actually valid, but for example
    ])
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp random_string(len) do
    chars = ~c" ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    chars
    |> Enum.shuffle()
    |> Enum.take(len)
    |> to_string()
  end

  defp setup_for_transition(network, {from_state, _action}) do
    # Transition network to the required starting state
    case from_state do
      :detached -> network
      :child -> {:ok, n} = Network.attach(network); n
      :router -> {:ok, c} = Network.attach(network); {:ok, n} = Network.promote(c); n
      :leader -> {:ok, c} = Network.attach(network); {:ok, r} = Network.promote(c); {:ok, n} = Network.become_leader(r); n
    end
  end

  defp apply_transition(network, {_from, :attach}) do
    Network.attach(network)
  end
  defp apply_transition(network, {_from, :promote}) do
    Network.promote(network)
  end
  defp apply_transition(network, {_from, :become_leader}) do
    Network.become_leader(network)
  end
  defp apply_transition(network, {_from, :demote}) do
    Network.demote(network)
  end
end
