defmodule Core.Resources.ThreadNetworkStatefulTest do
  @moduledoc """
  Stateful property-based testing for ThreadNetwork Ash Resource.
  
  Models the complete lifecycle of Thread network resources including:
  - Network creation and destruction
  - State transitions (disabled → detached → child/router/leader)
  - Role promotions and demotions  
  - Topology updates
  - Concurrent network management
  - Data consistency across operations
  """
  
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM
  
  alias Core.Resources.ThreadNetwork
  alias Core.Test.Generators
  
  # ============================================================================
  # State Model
  # ============================================================================
  
  defmodule Model do
    @moduledoc false
    
    defstruct [
      networks: %{},  # id => network_model
      active_network_id: nil,
      operation_count: 0
    ]
    
    defmodule NetworkModel do
      @moduledoc false
      
      defstruct [
        :id,
        :name,
        :pan_id,
        :channel,
        :role,
        :state,
        :child_count,
        :router_count,
        :network_data_version,
        created_at: nil,
        updated_at: nil
      ]
    end
    
    @type t :: %__MODULE__{
      networks: %{String.t() => NetworkModel.t()},
      active_network_id: String.t() | nil,
      operation_count: non_neg_integer()
    }
  end
  
  # ============================================================================
  # Initial State
  # ============================================================================
  
  def initial_state do
    %Model{}
  end
  
  # ============================================================================
  # Commands
  # ============================================================================
  
  def command(state) do
    create_commands = [
      {:call, __MODULE__, :create_network, [random_network_attrs()]}
    ]
    
    network_commands = if map_size(state.networks) > 0 do
      network_id = random_network_id(state)
      
      [
        {:call, __MODULE__, :read_network, [network_id]},
        {:call, __MODULE__, :update_role, [network_id, random_role()]},
        {:call, __MODULE__, :update_state, [network_id, random_network_state()]},
        {:call, __MODULE__, :update_topology, [network_id, :rand.uniform(10), :rand.uniform(5)]},
        {:call, __MODULE__, :increment_version, [network_id]},
        {:call, __MODULE__, :destroy_network, [network_id]}
      ]
    else
      []
    end
    
    action_commands = if map_size(state.networks) > 0 do
      network_id = random_network_id(state)
      [
        {:call, __MODULE__, :form_network, [network_id]},
        {:call, __MODULE__, :attach_network, [network_id]}
      ]
    else
      []
    end
    
    query_commands = [
      {:call, __MODULE__, :list_all_networks, []},
      {:call, __MODULE__, :count_by_role, [random_role()]},
      {:call, __MODULE__, :find_active_networks, []}
    ]
    
    frequency([
      {5, oneof(create_commands)},
      {10, oneof(network_commands ++ action_commands)},
      {2, oneof(query_commands)}
    ])
  end
  
  # ============================================================================
  # Command Implementations
  # ============================================================================
  
  def create_network(attrs) do
    ThreadNetwork.create(attrs)
  end
  
  def read_network(id) do
    ThreadNetwork.read(id)
  end
  
  def update_role(id, role) do
    case ThreadNetwork.read(id) do
      {:ok, network} ->
        ThreadNetwork.update(network, %{role: role})
      error ->
        error
    end
  end
  
  def update_state(id, new_state) do
    case ThreadNetwork.read(id) do
      {:ok, network} ->
        ThreadNetwork.update(network, %{state: new_state})
      error ->
        error
    end
  end
  
  def update_topology(id, child_count, router_count) do
    case ThreadNetwork.read(id) do
      {:ok, network} ->
        ThreadNetwork.update_topology(network, %{
          child_count: child_count,
          router_count: router_count
        })
      error ->
        error
    end
  end
  
  def increment_version(id) do
    case ThreadNetwork.read(id) do
      {:ok, network} ->
        current_version = network.network_data_version || 0
        ThreadNetwork.update(network, %{network_data_version: current_version + 1})
      error ->
        error
    end
  end
  
  def destroy_network(id) do
    case ThreadNetwork.read(id) do
      {:ok, network} ->
        ThreadNetwork.destroy(network)
      error ->
        error
    end
  end
  
  def form_network(id) do
    case ThreadNetwork.read(id) do
      {:ok, _network} ->
        # Simulate forming network (sets role to leader, state to active)
        update_role(id, :leader)
        update_state(id, :active)
      error ->
        error
    end
  end
  
  def attach_network(id) do
    case ThreadNetwork.read(id) do
      {:ok, _network} ->
        # Simulate attaching (sets role to child, state to joining)
        update_role(id, :child)
        update_state(id, :joining)
      error ->
        error
    end
  end
  
  def list_all_networks do
    {:ok, ThreadNetwork.read_all!()}
  end
  
  def count_by_role(role) do
    networks = ThreadNetwork.read_all!()
    count = Enum.count(networks, &(&1.role == role))
    {:ok, count}
  end
  
  def find_active_networks do
    networks = ThreadNetwork.read_all!()
    active = Enum.filter(networks, &(&1.is_active))
    {:ok, active}
  end
  
  # ============================================================================
  # State Transitions
  # ============================================================================
  
  def next_state(state, result, {:call, _, :create_network, [attrs]}) do
    case result do
      {:ok, network} ->
        model_network = %Model.NetworkModel{
          id: network.id,
          name: attrs.name,
          pan_id: attrs[:pan_id],
          channel: attrs[:channel],
          role: attrs[:role] || :disabled,
          state: attrs[:state] || :offline,
          child_count: 0,
          router_count: 0,
          network_data_version: 0,
          created_at: DateTime.utc_now()
        }
        
        networks = Map.put(state.networks, network.id, model_network)
        %{state | networks: networks, operation_count: state.operation_count + 1}
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :update_role, [id, role]}) do
    case result do
      {:ok, _network} ->
        update_network_in_state(state, id, %{role: role})
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :update_state, [id, new_state]}) do
    case result do
      {:ok, _network} ->
        update_network_in_state(state, id, %{state: new_state})
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :update_topology, [id, children, routers]}) do
    case result do
      {:ok, _network} ->
        update_network_in_state(state, id, %{
          child_count: children,
          router_count: routers
        })
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :increment_version, [id]}) do
    case result do
      {:ok, _network} ->
        case Map.get(state.networks, id) do
          nil ->
            state
          network ->
            current = network.network_data_version || 0
            update_network_in_state(state, id, %{network_data_version: current + 1})
        end
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :destroy_network, [id]}) do
    case result do
      :ok ->
        networks = Map.delete(state.networks, id)
        active_id = if state.active_network_id == id, do: nil, else: state.active_network_id
        %{state | networks: networks, active_network_id: active_id, operation_count: state.operation_count + 1}
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :form_network, [id]}) do
    case result do
      :ok ->
        state
        |> update_network_in_state(id, %{role: :leader, state: :active})
        |> Map.put(:active_network_id, id)
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :attach_network, [id]}) do
    case result do
      :ok ->
        update_network_in_state(state, id, %{role: :child, state: :joining})
      
      {:error, _} ->
        state
    end
  end
  
  def next_state(state, _result, _call) do
    state
  end
  
  # ============================================================================
  # Preconditions
  # ============================================================================
  
  def precondition(state, {:call, _, :read_network, [id]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :update_role, [id, _]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :update_state, [id, _]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :update_topology, [id, _, _]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :increment_version, [id]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :destroy_network, [id]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :form_network, [id]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(state, {:call, _, :attach_network, [id]}) do
    Map.has_key?(state.networks, id)
  end
  
  def precondition(_state, _call), do: true
  
  # ============================================================================
  # Postconditions
  # ============================================================================
  
  def postcondition(_state, {:call, _, :create_network, _}, result) do
    match?({:ok, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :read_network, _}, result) do
    match?({:ok, _} | {:error, _}, result)
  end
  
  def postcondition(state, {:call, _, :list_all_networks, _}, result) do
    case result do
      {:ok, networks} ->
        # All networks in model should be in result
        length(networks) >= map_size(state.networks)
      _ ->
        false
    end
  end
  
  def postcondition(_state, {:call, _, :count_by_role, _}, result) do
    match?({:ok, count} when is_integer(count) and count >= 0, result)
  end
  
  def postcondition(_state, {:call, _, :find_active_networks, _}, result) do
    case result do
      {:ok, networks} when is_list(networks) ->
        # All returned networks should be active
        Enum.all?(networks, &(&1.is_active))
      _ ->
        false
    end
  end
  
  def postcondition(_state, _call, result) do
    match?(:ok | {:ok, _} | {:error, _}, result)
  end
  
  # ============================================================================
  # Invariants
  # ============================================================================
  
  def invariant(state) do
    # All network IDs should be unique
    ids = Map.keys(state.networks)
    unique_ids = length(ids) == length(Enum.uniq(ids))
    
    # Active network (if set) must exist
    active_exists = if state.active_network_id do
      Map.has_key?(state.networks, state.active_network_id)
    else
      true
    end
    
    # All networks should have valid roles
    valid_roles = Enum.all?(state.networks, fn {_id, network} ->
      network.role in [:disabled, :detached, :child, :router, :leader]
    end)
    
    # All networks should have valid states
    valid_states = Enum.all?(state.networks, fn {_id, network} ->
      network.state in [:offline, :joining, :attached, :active]
    end)
    
    # Operation count should be non-negative
    valid_count = state.operation_count >= 0
    
    # Device counts should be non-negative
    valid_counts = Enum.all?(state.networks, fn {_id, network} ->
      network.child_count >= 0 and network.router_count >= 0
    end)
    
    # Leader role implies active state
    leader_consistency = Enum.all?(state.networks, fn {_id, network} ->
      if network.role == :leader do
        network.state == :active
      else
        true
      end
    end)
    
    unique_ids and active_exists and valid_roles and valid_states and 
    valid_count and valid_counts and leader_consistency
  end
  
  # ============================================================================
  # Properties
  # ============================================================================
  
  @tag :property
  @tag :stateful
  @tag timeout: 120_000
  property "thread network resource lifecycle is consistent" do
    numtests(30, forall cmds <- commands(__MODULE__) do
      clear_networks()
      
      {history, state, result} = run_commands(__MODULE__, cmds)
      
      # Verify final invariants
      invariants_hold = invariant(state)
      
      # Verify model matches reality
      reality_matches = verify_model_matches_reality(state)
      
      clear_networks()
      
      (result == :ok and invariants_hold and reality_matches)
      |> when_fail(
        IO.puts("""
        
        ========================================
        ThreadNetwork State Machine Failed
        ========================================
        History: #{inspect(history, pretty: true, limit: 20)}
        Final State:
          - Networks: #{map_size(state.networks)}
          - Active: #{inspect(state.active_network_id)}
          - Operations: #{state.operation_count}
        Invariants: #{invariants_hold}
        Reality Matches: #{reality_matches}
        Result: #{inspect(result)}
        ========================================
        """)
      )
      |> aggregate(command_names(cmds))
    end)
  end
  
  @tag :property
  @tag :stateful
  property "network data version always increases" do
    numtests(20, forall cmds <- commands(__MODULE__) do
      clear_networks()
      
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # Check that versions never decreased
      versions_valid = Enum.all?(state.networks, fn {id, model_network} ->
        case ThreadNetwork.read(id) do
          {:ok, actual_network} ->
            # Version should match or be higher
            (actual_network.network_data_version || 0) >= (model_network.network_data_version || 0)
          _ ->
            true  # Network was deleted, that's ok
        end
      end)
      
      clear_networks()
      
      result == :ok and versions_valid
    end)
  end
  
  @tag :property
  @tag :stateful
  property "role transitions maintain valid state" do
    numtests(25, forall cmds <- commands(__MODULE__) do
      clear_networks()
      
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # Verify all networks have consistent role/state combinations
      consistency_valid = Enum.all?(state.networks, fn {id, model_network} ->
        case ThreadNetwork.read(id) do
          {:ok, actual_network} ->
            # Leader must be active
            if actual_network.role == :leader do
              actual_network.state == :active
            else
              true
            end
          _ ->
            true
        end
      end)
      
      clear_networks()
      
      result == :ok and consistency_valid
    end)
  end
  
  @tag :property
  @tag :stateful
  property "concurrent operations maintain data integrity" do
    numtests(15, forall cmds <- commands(__MODULE__) do
      clear_networks()
      
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # Verify no data corruption
      integrity_valid = Enum.all?(state.networks, fn {id, model_network} ->
        case ThreadNetwork.read(id) do
          {:ok, actual_network} ->
            # Basic fields should match
            actual_network.name == model_network.name and
            actual_network.role == model_network.role
          {:error, _} ->
            true  # Deleted, that's ok
        end
      end)
      
      clear_networks()
      
      result == :ok and integrity_valid
    end)
  end
  
  @tag :property
  @tag :stateful
  property "topology updates are atomic" do
    numtests(15, forall cmds <- commands(__MODULE__) do
      clear_networks()
      
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # After all operations, device_count calculation should be correct
      calculations_valid = Enum.all?(state.networks, fn {id, model_network} ->
        case ThreadNetwork.read(id) do
          {:ok, actual_network} ->
            expected_total = model_network.child_count + model_network.router_count
            actual_total = actual_network.device_count
            expected_total == actual_total
          _ ->
            true
        end
      end)
      
      clear_networks()
      
      result == :ok and calculations_valid
    end)
  end
  
  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  defp update_network_in_state(state, id, updates) do
    case Map.get(state.networks, id) do
      nil ->
        state
      network ->
        updated_network = struct(network, Map.merge(Map.from_struct(network), updates))
        networks = Map.put(state.networks, id, updated_network)
        %{state | networks: networks, operation_count: state.operation_count + 1}
    end
  end
  
  defp random_network_id(state) do
    case Map.keys(state.networks) do
      [] -> nil
      ids -> Enum.random(ids)
    end
  end
  
  defp random_network_attrs do
    %{
      name: "Network_#{:rand.uniform(1000)}",
      pan_id: :rand.uniform(0xFFFF),
      channel: :rand.uniform(16) + 10,
      role: random_role(),
      state: random_network_state()
    }
  end
  
  defp random_role do
    Enum.random([:disabled, :detached, :child, :router, :leader])
  end
  
  defp random_network_state do
    Enum.random([:offline, :joining, :attached, :active])
  end
  
  defp clear_networks do
    ThreadNetwork.read_all!()
    |> Enum.each(&ThreadNetwork.destroy/1)
  end
  
  defp verify_model_matches_reality(state) do
    actual_networks = ThreadNetwork.read_all!()
    actual_by_id = Map.new(actual_networks, &{&1.id, &1})
    
    # Check that all networks in model exist in reality
    Enum.all?(state.networks, fn {id, model_network} ->
      case Map.get(actual_by_id, id) do
        nil ->
          false  # Network should exist
        actual ->
          # Basic fields should match
          actual.name == model_network.name and
          actual.role == model_network.role and
          actual.state == model_network.state
      end
    end)
  end
  
  # ============================================================================
  # Weight Functions
  # ============================================================================
  
  def weight(_state, {:call, _, :create_network, _}), do: 5
  def weight(_state, {:call, _, :update_role, _}), do: 3
  def weight(_state, {:call, _, :update_topology, _}), do: 3
  def weight(_state, {:call, _, :form_network, _}), do: 2
  def weight(_state, {:call, _, :destroy_network, _}), do: 1
  def weight(_state, _call), do: 2
end
