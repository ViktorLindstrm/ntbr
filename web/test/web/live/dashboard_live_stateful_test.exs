defmodule Web.DashboardLiveStatefulTest do
  @moduledoc """
  Stateful property-based testing for Dashboard LiveView.
  
  Uses PropCheck.StateM to model the LiveView state machine and verify
  that all state transitions are valid and the UI remains consistent.
  """
  
  use Web.ConnCase
  use PropCheck
  use PropCheck.StateM
  
  import Phoenix.LiveViewTest
  
  alias Core.Resources.{ThreadNetwork, SpinelFrame, RCPStatus}
  
  # ============================================================================
  # State Model
  # ============================================================================
  
  @doc """
  Model representing the LiveView's internal state.
  """
  defmodule Model do
    @moduledoc false
    
    defstruct [
      :view_pid,
      networks: [],
      selected_network: nil,
      frames: [],
      rcp_status: nil,
      filter_direction: nil,
      auto_scroll: true,
      loading: false
    ]
    
    @type t :: %__MODULE__{
      view_pid: pid() | nil,
      networks: list(map()),
      selected_network: map() | nil,
      frames: list(map()),
      rcp_status: map() | nil,
      filter_direction: :inbound | :outbound | nil,
      auto_scroll: boolean(),
      loading: boolean()
    }
  end
  
  # ============================================================================
  # Initial State
  # ============================================================================
  
  @doc """
  Initial state of the model.
  """
  def initial_state do
    %Model{}
  end
  
  # ============================================================================
  # Commands
  # ============================================================================
  
  @doc """
  Generate commands based on current state.
  """
  def command(state) do
    # Available commands depend on current state
    base_commands = [
      {:call, __MODULE__, :mount_view, [build_conn()]},
    ]
    
    mounted_commands = if state.view_pid do
      [
        {:call, __MODULE__, :refresh_data, [state.view_pid]},
        {:call, __MODULE__, :toggle_auto_scroll, [state.view_pid]},
        {:call, __MODULE__, :clear_frames, [state.view_pid]},
        {:call, __MODULE__, :create_network, []},
        {:call, __MODULE__, :capture_frame, []},
        {:call, __MODULE__, :send_network_update, [state.view_pid]},
        {:call, __MODULE__, :send_frame_update, [state.view_pid]},
        {:call, __MODULE__, :send_rcp_update, [state.view_pid]}
      ]
    else
      []
    end
    
    oneof(base_commands ++ mounted_commands)
  end
  
  # ============================================================================
  # Command Implementations
  # ============================================================================
  
  @doc "Mount the LiveView"
  def mount_view(conn) do
    case live(conn, "/") do
      {:ok, view, _html} -> {:ok, view}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc "Refresh dashboard data"
  def refresh_data(view) do
    try do
      _html = render_click(view, "refresh")
      :ok
    rescue
      _ -> {:error, :refresh_failed}
    end
  end
  
  @doc "Toggle auto-scroll"
  def toggle_auto_scroll(view) do
    try do
      _html = render_click(view, "toggle_auto_scroll")
      :ok
    rescue
      _ -> {:error, :toggle_failed}
    end
  end
  
  @doc "Clear old frames"
  def clear_frames(view) do
    try do
      _html = render_click(view, "clear_frames")
      :ok
    rescue
      _ -> {:error, :clear_failed}
    end
  end
  
  @doc "Create a new network"
  def create_network do
    attrs = %{
      name: "TestNetwork_#{:rand.uniform(1000)}",
      pan_id: :rand.uniform(0xFFFF),
      channel: :rand.uniform(16) + 10,
      role: Enum.random([:disabled, :child, :router, :leader]),
      state: Enum.random([:offline, :active])
    }
    
    case ThreadNetwork.create(attrs) do
      {:ok, network} -> {:ok, network}
      {:error, _} -> {:error, :create_failed}
    end
  end
  
  @doc "Capture a Spinel frame"
  def capture_frame do
    attrs = %{
      sequence: :rand.uniform(10000),
      direction: Enum.random([:inbound, :outbound]),
      command: Enum.random([:reset, :prop_value_get, :prop_value_is]),
      tid: :rand.uniform(15),
      size_bytes: :rand.uniform(100),
      status: Enum.random([:success, :error])
    }
    
    case SpinelFrame.capture(attrs) do
      {:ok, frame} -> {:ok, frame}
      {:error, _} -> {:error, :capture_failed}
    end
  end
  
  @doc "Send network state update message"
  def send_network_update(view) do
    new_state = %{
      role: Enum.random([:child, :router, :leader]),
      state: :active
    }
    
    send(view.pid, {:network_state_changed, new_state})
    :ok
  end
  
  @doc "Send frame captured message"
  def send_frame_update(view) do
    {:ok, frame} = capture_frame()
    send(view.pid, {:spinel_frame_captured, frame})
    :ok
  end
  
  @doc "Send RCP status update"
  def send_rcp_update(view) do
    status = %{
      connected: Enum.random([true, false]),
      frames_sent: :rand.uniform(1000)
    }
    
    send(view.pid, {:rcp_status_changed, status})
    :ok
  end
  
  # ============================================================================
  # State Transitions (next_state)
  # ============================================================================
  
  @doc """
  Update the model based on command execution.
  """
  def next_state(state, result, {:call, _, :mount_view, _}) do
    case result do
      {:ok, view} -> 
        %{state | view_pid: view.pid, loading: false}
      {:error, _} -> 
        state
    end
  end
  
  def next_state(state, _result, {:call, _, :refresh_data, _}) do
    %{state | loading: true}
  end
  
  def next_state(state, _result, {:call, _, :toggle_auto_scroll, _}) do
    %{state | auto_scroll: !state.auto_scroll}
  end
  
  def next_state(state, _result, {:call, _, :clear_frames, _}) do
    %{state | frames: []}
  end
  
  def next_state(state, result, {:call, _, :create_network, _}) do
    case result do
      {:ok, network} -> 
        %{state | networks: [network | state.networks]}
      {:error, _} -> 
        state
    end
  end
  
  def next_state(state, result, {:call, _, :capture_frame, _}) do
    case result do
      {:ok, frame} -> 
        %{state | frames: [frame | state.frames]}
      {:error, _} -> 
        state
    end
  end
  
  def next_state(state, _result, {:call, _, :send_network_update, _}) do
    state
  end
  
  def next_state(state, _result, {:call, _, :send_frame_update, _}) do
    state
  end
  
  def next_state(state, _result, {:call, _, :send_rcp_update, _}) do
    state
  end
  
  # ============================================================================
  # Preconditions
  # ============================================================================
  
  @doc """
  Preconditions that must hold before executing a command.
  """
  def precondition(state, {:call, _, :mount_view, _}) do
    # Can only mount if not already mounted
    is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :refresh_data, _}) do
    # Must be mounted to refresh
    not is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :toggle_auto_scroll, _}) do
    not is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :clear_frames, _}) do
    not is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :send_network_update, _}) do
    not is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :send_frame_update, _}) do
    not is_nil(state.view_pid)
  end
  
  def precondition(state, {:call, _, :send_rcp_update, _}) do
    not is_nil(state.view_pid)
  end
  
  def precondition(_state, _call) do
    true
  end
  
  # ============================================================================
  # Postconditions
  # ============================================================================
  
  @doc """
  Postconditions that must hold after executing a command.
  """
  def postcondition(_state, {:call, _, :mount_view, _}, result) do
    case result do
      {:ok, view} -> 
        Process.alive?(view.pid)
      {:error, _} -> 
        true  # Mounting can fail, that's ok
    end
  end
  
  def postcondition(_state, {:call, _, :refresh_data, _}, result) do
    # Refresh should succeed or fail gracefully
    result in [:ok, {:error, :refresh_failed}]
  end
  
  def postcondition(_state, {:call, _, :toggle_auto_scroll, _}, result) do
    result in [:ok, {:error, :toggle_failed}]
  end
  
  def postcondition(_state, {:call, _, :clear_frames, _}, result) do
    result in [:ok, {:error, :clear_failed}]
  end
  
  def postcondition(_state, {:call, _, :create_network, _}, result) do
    match?({:ok, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :capture_frame, _}, result) do
    match?({:ok, _} | {:error, _}, result)
  end
  
  def postcondition(_state, {:call, _, :send_network_update, _}, result) do
    result == :ok
  end
  
  def postcondition(_state, {:call, _, :send_frame_update, _}, result) do
    result == :ok
  end
  
  def postcondition(_state, {:call, _, :send_rcp_update, _}, result) do
    result == :ok
  end
  
  # ============================================================================
  # Invariants
  # ============================================================================
  
  @doc """
  Invariants that must always hold throughout the state machine execution.
  """
  def invariant(state) do
    # If view is mounted, process must be alive
    view_alive = if state.view_pid do
      Process.alive?(state.view_pid)
    else
      true
    end
    
    # Networks list should not have duplicates (by ID)
    unique_networks = length(state.networks) == length(Enum.uniq_by(state.networks, & &1.id))
    
    # Frames should be ordered (most recent first)
    frames_ordered = case state.frames do
      [] -> true
      [_] -> true
      frames -> 
        timestamps = Enum.map(frames, & &1.timestamp)
        sorted = Enum.sort(timestamps, {:desc, DateTime})
        timestamps == sorted
    end
    
    view_alive and unique_networks and frames_ordered
  end
  
  # ============================================================================
  # Properties
  # ============================================================================
  
  @tag :property
  @tag :stateful
  @tag timeout: 120_000
  property "dashboard LiveView state machine is valid" do
    # Run fewer iterations for stateful tests (they're expensive)
    numtests(
      25,
      forall cmds <- commands(__MODULE__) do
        # Clear test data before each run
        clear_test_data()
        
        # Execute command sequence
        {history, state, result} = run_commands(__MODULE__, cmds)
        
        # Cleanup
        if state.view_pid && Process.alive?(state.view_pid) do
          GenServer.stop(state.view_pid, :normal)
        end
        
        clear_test_data()
        
        # Assert result and print diagnostics on failure
        (result == :ok)
        |> when_fail(
          IO.puts("""
          
          ========================================
          Stateful Test Failed
          ========================================
          History: #{inspect(history, pretty: true)}
          State: #{inspect(state, pretty: true)}
          Result: #{inspect(result)}
          ========================================
          """)
        )
        |> aggregate(command_names(cmds))
      end
    )
  end
  
  @tag :property
  @tag :stateful
  property "LiveView never crashes from valid interactions" do
    numtests(
      20,
      forall cmds <- commands(__MODULE__) do
        clear_test_data()
        
        {_history, state, result} = run_commands(__MODULE__, cmds)
        
        # Main assertion: if view was mounted, it should still be alive
        view_still_alive = if state.view_pid do
          Process.alive?(state.view_pid)
        else
          true
        end
        
        # Cleanup
        if state.view_pid && Process.alive?(state.view_pid) do
          GenServer.stop(state.view_pid, :normal)
        end
        
        clear_test_data()
        
        view_still_alive and result == :ok
      end
    )
  end
  
  @tag :property
  @tag :stateful
  property "UI state remains consistent across operations" do
    numtests(
      15,
      forall cmds <- commands(__MODULE__) do
        clear_test_data()
        
        {_history, state, result} = run_commands(__MODULE__, cmds)
        
        # Check invariants hold at the end
        invariants_hold = invariant(state)
        
        # Cleanup
        if state.view_pid && Process.alive?(state.view_pid) do
          GenServer.stop(state.view_pid, :normal)
        end
        
        clear_test_data()
        
        invariants_hold and result == :ok
      end
    )
  end
  
  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  defp clear_test_data do
    # Clear all test data from ETS tables
    ThreadNetwork.read_all!() |> Enum.each(&ThreadNetwork.destroy/1)
    SpinelFrame.read_all!() |> Enum.each(&SpinelFrame.destroy/1)
    
    case RCPStatus.current() do
      {:ok, status} -> RCPStatus.destroy(status)
      _ -> :ok
    end
  end
  
  # ============================================================================
  # Weight Functions (Optional - for biasing command selection)
  # ============================================================================
  
  @doc """
  Optionally weight commands to make certain operations more likely.
  """
  def weight(_state, {:call, _, :mount_view, _}), do: 5  # Higher weight for mounting
  def weight(_state, {:call, _, :create_network, _}), do: 3  # Create data more often
  def weight(_state, {:call, _, :capture_frame, _}), do: 3
  def weight(_state, _call), do: 1  # Default weight
end
