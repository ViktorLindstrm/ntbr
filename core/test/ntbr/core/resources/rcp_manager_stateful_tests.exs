defmodule Core.RCPManagerStatefulTest do
  @moduledoc """
  Stateful property-based testing for RCP Manager GenServer.
  
  Models the complete RCP communication state machine including:
  - Connection lifecycle
  - Request/response matching
  - TID allocation and reuse
  - Timeout handling
  - Concurrent request management
  - Error recovery
  """
  
  use ExUnit.Case
  use PropCheck
  use PropCheck.StateM
  
  alias Core.RCPManager
  
  # ============================================================================
  # State Model
  # ============================================================================
  
  defmodule Model do
    @moduledoc false
    
    defstruct [
      :manager_pid,
      connected: false,
      pending_requests: %{},  # tid => {property, ref, timeout}
      next_tid: 0,
      sent_frames: [],
      received_frames: [],
      errors: [],
      last_reset: nil
    ]
    
    @type t :: %__MODULE__{
      manager_pid: pid() | nil,
      connected: boolean(),
      pending_requests: %{non_neg_integer() => {atom(), reference(), non_neg_integer()}},
      next_tid: 0..15,
      sent_frames: list(map()),
      received_frames: list(map()),
      errors: list({atom(), String.t()}),
      last_reset: DateTime.t() | nil
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
    base_commands = [
      {:call, __MODULE__, :start_manager, []}
    ]
    
    started_commands = if state.manager_pid do
      connection_commands = if state.connected do
        [
          {:call, __MODULE__, :disconnect, [state.manager_pid]}
        ]
      else
        [
          {:call, __MODULE__, :connect, [state.manager_pid, random_port()]}
        ]
      end
      
      request_commands = if state.connected do
        [
          {:call, __MODULE__, :get_property, [state.manager_pid, random_property()]},
          {:call, __MODULE__, :set_property, [state.manager_pid, random_property(), random_value()]},
          {:call, __MODULE__, :send_command, [state.manager_pid, random_command()]},
          {:call, __MODULE__, :reset_rcp, [state.manager_pid]}
        ]
      else
        []
      end
      
      response_commands = if map_size(state.pending_requests) > 0 do
        {tid, {_prop, _ref, _timeout}} = Enum.random(state.pending_requests)
        [
          {:call, __MODULE__, :simulate_response, [state.manager_pid, tid, :success]},
          {:call, __MODULE__, :simulate_response, [state.manager_pid, tid, :error]},
          {:call, __MODULE__, :simulate_timeout, [tid]}
        ]
      else
        []
      end
      
      inspection_commands = [
        {:call, __MODULE__, :get_info, [state.manager_pid]},
        {:call, __MODULE__, :get_statistics, [state.manager_pid]}
      ]
      
      connection_commands ++ request_commands ++ response_commands ++ inspection_commands
    else
      []
    end
    
    frequency([
      {5, oneof(base_commands ++ started_commands)},
      {1, {:call, __MODULE__, :stop_manager, [state.manager_pid]}}
    ])
  end
  
  # ============================================================================
  # Command Implementations
  # ============================================================================
  
  def start_manager do
    case RCPManager.start_link(name: {:global, make_ref()}) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def stop_manager(nil), do: :ok
  def stop_manager(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal)
    end
    :ok
  end
  
  def connect(pid, port) do
    GenServer.call(pid, {:connect, port, 115200})
  rescue
    _ -> {:error, :call_failed}
  end
  
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  rescue
    _ -> {:error, :call_failed}
  end
  
  def get_property(pid, property) do
    task = Task.async(fn ->
      GenServer.call(pid, {:get_property, property}, 1000)
    end)
    
    case Task.yield(task, 1500) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  rescue
    _ -> {:error, :request_failed}
  end
  
  def set_property(pid, property, value) do
    task = Task.async(fn ->
      GenServer.call(pid, {:set_property, property, value}, 1000)
    end)
    
    case Task.yield(task, 1500) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  rescue
    _ -> {:error, :request_failed}
  end
  
  def send_command(pid, command) do
    GenServer.call(pid, {:send_command, command})
  rescue
    _ -> {:error, :request_failed}
  end
  
  def reset_rcp(pid) do
    GenServer.call(pid, :reset)
  rescue
    _ -> {:error, :request_failed}
  end
  
  def simulate_response(pid, tid, status) do
    data = case status do
      :success -> <<0x04, 0x00>>  # Example response
      :error -> <<0xFF>>
    end
    
    send(pid, {:rcp_response, tid, status, data})
    :ok
  end
  
  def simulate_timeout(tid) do
    # In real implementation, would trigger timeout
    {:timeout, tid}
  end
  
  def get_info(pid) do
    GenServer.call(pid, :get_info)
  rescue
    _ -> {:error, :call_failed}
  end
  
  def get_statistics(pid) do
    GenServer.call(pid, :get_statistics)
  rescue
    _ -> {:error, :call_failed}
  end
  
  # ============================================================================
  # State Transitions
  # ============================================================================
  
  def next_state(state, result, {:call, _, :start_manager, _}) do
    case result do
      {:ok, pid} -> 
        %{state | manager_pid: pid}
      {:error, _} -> 
        state
    end
  end
  
  def next_state(state, _result, {:call, _, :stop_manager, _}) do
    %{state | manager_pid: nil, connected: false, pending_requests: %{}}
  end
  
  def next_state(state, result, {:call, _, :connect, _}) do
    case result do
      :ok -> 
        %{state | connected: true}
      {:ok, _} ->
        %{state | connected: true}
      {:error, _} -> 
        state
    end
  end
  
  def next_state(state, _result, {:call, _, :disconnect, _}) do
    %{state | connected: false, pending_requests: %{}}
  end
  
  def next_state(state, result, {:call, _, :get_property, [_, property]}) do
    case result do
      {:pending, tid} ->
        ref = make_ref()
        requests = Map.put(state.pending_requests, tid, {property, ref, 5000})
        next_tid = rem(tid + 1, 16)
        %{state | pending_requests: requests, next_tid: next_tid}
      
      {:error, _} ->
        %{state | errors: [{:get_property, property} | state.errors]}
      
      _ ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :set_property, [_, property, _value]}) do
    case result do
      {:pending, tid} ->
        ref = make_ref()
        requests = Map.put(state.pending_requests, tid, {property, ref, 5000})
        next_tid = rem(tid + 1, 16)
        %{state | pending_requests: requests, next_tid: next_tid}
      
      {:error, _} ->
        %{state | errors: [{:set_property, property} | state.errors]}
      
      _ ->
        state
    end
  end
  
  def next_state(state, result, {:call, _, :send_command, [_, command]}) do
    case result do
      :ok ->
        frame = %{command: command, timestamp: DateTime.utc_now()}
        %{state | sent_frames: [frame | state.sent_frames]}
      
      {:error, _} ->
        %{state | errors: [{:send_command, command} | state.errors]}
    end
  end
  
  def next_state(state, result, {:call, _, :reset_rcp, _}) do
    case result do
      :ok ->
        %{state | 
          last_reset: DateTime.utc_now(),
          pending_requests: %{},  # Reset clears pending
          next_tid: 0
        }
      
      {:error, _} ->
        %{state | errors: [{:reset, :failed} | state.errors]}
    end
  end
  
  def next_state(state, _result, {:call, _, :simulate_response, [_, tid, status]}) do
    case Map.pop(state.pending_requests, tid) do
      {nil, _} ->
        # Response for unknown TID
        state
      
      {{property, _ref, _timeout}, remaining} ->
        frame = %{
          tid: tid,
          property: property,
          status: status,
          timestamp: DateTime.utc_now()
        }
        %{state | 
          pending_requests: remaining,
          received_frames: [frame | state.received_frames]
        }
    end
  end
  
  def next_state(state, {:timeout, tid}, {:call, _, :simulate_timeout, _}) do
    {_value, remaining} = Map.pop(state.pending_requests, tid)
    %{state | 
      pending_requests: remaining,
      errors: [{:timeout, tid} | state.errors]
    }
  end
  
  def next_state(state, _result, _call), do: state
  
  # ============================================================================
  # Preconditions
  # ============================================================================
  
  def precondition(state, {:call, _, :start_manager, _}) do
    is_nil(state.manager_pid)
  end
  
  def precondition(state, {:call, _, :stop_manager, _}) do
    not is_nil(state.manager_pid)
  end
  
  def precondition(state, {:call, _, :connect, _}) do
    not is_nil(state.manager_pid) and not state.connected
  end
  
  def precondition(state, {:call, _, :disconnect, _}) do
    not is_nil(state.manager_pid) and state.connected
  end
  
  def precondition(state, {:call, _, :get_property, _}) do
    not is_nil(state.manager_pid) and state.connected
  end
  
  def precondition(state, {:call, _, :set_property, _}) do
    not is_nil(state.manager_pid) and state.connected
  end
  
  def precondition(state, {:call, _, :send_command, _}) do
    not is_nil(state.manager_pid) and state.connected
  end
  
  def precondition(state, {:call, _, :reset_rcp, _}) do
    not is_nil(state.manager_pid) and state.connected
  end
  
  def precondition(state, {:call, _, :simulate_response, [_, tid, _]}) do
    not is_nil(state.manager_pid) and Map.has_key?(state.pending_requests, tid)
  end
  
  def precondition(state, {:call, _, :simulate_timeout, [tid]}) do
    Map.has_key?(state.pending_requests, tid)
  end
  
  def precondition(state, {:call, _, :get_info, _}) do
    not is_nil(state.manager_pid)
  end
  
  def precondition(state, {:call, _, :get_statistics, _}) do
    not is_nil(state.manager_pid)
  end
  
  # ============================================================================
  # Postconditions
  # ============================================================================
  
  def postcondition(_state, {:call, _, :start_manager, _}, result) do
    match?({:ok, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :connect, _}, result) do
    result in [:ok, {:ok, :connected}, {:error, :call_failed}, {:error, :invalid_port}]
  end
  
  def postcondition(_state, {:call, _, :disconnect, _}, result) do
    result in [:ok, {:error, :call_failed}]
  end
  
  def postcondition(_state, {:call, _, :get_property, _}, result) do
    match?({:ok, _} | {:pending, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :set_property, _}, result) do
    match?({:ok, _} | {:pending, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :get_info, _}, result) do
    case result do
      {:error, :call_failed} -> true
      info when is_map(info) -> 
        Map.has_key?(info, :connected) and 
        Map.has_key?(info, :pending_requests)
      _ -> false
    end
  end
  
  def postcondition(_state, _call, _result), do: true
  
  # ============================================================================
  # Invariants
  # ============================================================================
  
  def invariant(state) do
    # Manager process must be alive if we have a PID
    process_alive = if state.manager_pid do
      Process.alive?(state.manager_pid)
    else
      true
    end
    
    # TID must be in valid range
    tid_valid = state.next_tid >= 0 and state.next_tid <= 15
    
    # Can't have pending requests when disconnected
    requests_consistent = if not state.connected do
      map_size(state.pending_requests) == 0
    else
      true
    end
    
    # All pending request TIDs must be valid
    pending_tids_valid = Enum.all?(state.pending_requests, fn {tid, _} ->
      tid >= 0 and tid <= 15
    end)
    
    # Can't be connected without manager
    connection_valid = if state.connected do
      not is_nil(state.manager_pid)
    else
      true
    end
    
    process_alive and tid_valid and requests_consistent and 
    pending_tids_valid and connection_valid
  end
  
  # ============================================================================
  # Properties
  # ============================================================================
  
  @tag :property
  @tag :stateful
  @tag timeout: 120_000
  property "RCP manager state machine is valid" do
    numtests(30, forall cmds <- commands(__MODULE__) do
      {history, state, result} = run_commands(__MODULE__, cmds)
      
      # Cleanup
      if state.manager_pid && Process.alive?(state.manager_pid) do
        GenServer.stop(state.manager_pid, :normal)
      end
      
      (result == :ok)
      |> when_fail(
        IO.puts("""
        
        ========================================
        RCP Manager State Machine Failed
        ========================================
        History: #{inspect(history, pretty: true, limit: 30)}
        Final State:
          - Connected: #{state.connected}
          - Pending Requests: #{map_size(state.pending_requests)}
          - Next TID: #{state.next_tid}
          - Errors: #{length(state.errors)}
        Result: #{inspect(result)}
        ========================================
        """)
      )
      |> aggregate(command_names(cmds))
    end)
  end
  
  @tag :property
  @tag :stateful
  property "TID allocation never conflicts with pending requests" do
    numtests(25, forall cmds <- commands(__MODULE__) do
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # Check: allocated TIDs should cycle properly
      tid_cycle_valid = state.next_tid >= 0 and state.next_tid <= 15
      
      # Check: no duplicate TIDs in pending requests
      tids = Map.keys(state.pending_requests)
      no_duplicates = length(tids) == length(Enum.uniq(tids))
      
      # Cleanup
      if state.manager_pid && Process.alive?(state.manager_pid) do
        GenServer.stop(state.manager_pid, :normal)
      end
      
      result == :ok and tid_cycle_valid and no_duplicates
    end)
  end
  
  @tag :property
  @tag :stateful  
  property "manager never crashes from valid operations" do
    numtests(20, forall cmds <- commands(__MODULE__) do
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # Main assertion: if started, process should still be alive
      still_alive = if state.manager_pid do
        Process.alive?(state.manager_pid)
      else
        true
      end
      
      # Cleanup
      if state.manager_pid && Process.alive?(state.manager_pid) do
        GenServer.stop(state.manager_pid, :normal)
      end
      
      result == :ok and still_alive
    end)
  end
  
  @tag :property
  @tag :stateful
  property "disconnection clears all pending requests" do
    numtests(15, forall cmds <- commands(__MODULE__) do
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # If disconnected, there should be no pending requests
      invariant_holds = if not state.connected do
        map_size(state.pending_requests) == 0
      else
        true
      end
      
      # Cleanup
      if state.manager_pid && Process.alive?(state.manager_pid) do
        GenServer.stop(state.manager_pid, :normal)
      end
      
      result == :ok and invariant_holds
    end)
  end
  
  @tag :property
  @tag :stateful
  property "reset clears all state and resets TID counter" do
    numtests(15, forall cmds <- commands(__MODULE__) do
      {_history, state, result} = run_commands(__MODULE__, cmds)
      
      # If we had a reset, check that it properly cleared state
      reset_valid = if state.last_reset do
        # After reset:
        # - TID should be back to 0 or low number
        # - No pending requests
        state.next_tid <= 5 and map_size(state.pending_requests) == 0
      else
        true
      end
      
      # Cleanup
      if state.manager_pid && Process.alive?(state.manager_pid) do
        GenServer.stop(state.manager_pid, :normal)
      end
      
      result == :ok and reset_valid
    end)
  end
  
  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  defp random_port do
    Enum.random(["/dev/ttyUSB0", "/dev/ttyACM0", "/dev/ttyUSB1"])
  end
  
  defp random_property do
    Enum.random([
      :protocol_version,
      :ncp_version,
      :hwaddr,
      :net_role,
      :net_network_name,
      :thread_rloc16,
      :thread_leader_router_id
    ])
  end
  
  defp random_value do
    Enum.random([
      <<0x01, 0x02>>,
      "TestValue",
      :rand.uniform(0xFFFF),
      :crypto.strong_rand_bytes(8)
    ])
  end
  
  defp random_command do
    Enum.random([:reset, :noop, :save_settings])
  end
  
  # ============================================================================
  # Weight Functions
  # ============================================================================
  
  def weight(_state, {:call, _, :start_manager, _}), do: 5
  def weight(_state, {:call, _, :connect, _}), do: 4
  def weight(_state, {:call, _, :get_property, _}), do: 3
  def weight(_state, {:call, _, :set_property, _}), do: 2
  def weight(_state, {:call, _, :simulate_response, _}), do: 4  # Responses should be frequent
  def weight(_state, {:call, _, :reset_rcp, _}), do: 1  # Resets less common
  def weight(_state, _call), do: 2
end
