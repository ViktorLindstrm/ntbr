defmodule NTBR.Web.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for the NTBR Border Router.
  
  Displays real-time Thread network status, RCP connection health,
  and recent Spinel protocol activity.
  """
  
  use NTBR.Web, :live_view
  
  alias Core.Resources.{ThreadNetwork, RCPStatus, SpinelFrame}

  @refresh_interval 2_000  # 2 seconds

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to updates (in real implementation)
      # Phoenix.PubSub.subscribe(Web.PubSub, "network:updates")
      # Phoenix.PubSub.subscribe(Web.PubSub, "rcp:status")
      # Phoenix.PubSub.subscribe(Web.PubSub, "spinel:frames")
      
      # Schedule periodic refresh
      Process.send_after(self(), :refresh, @refresh_interval)
    end
    
    {:ok, load_data(socket)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("reset_rcp", _params, socket) do
    # In real implementation, would call Core.RCPManager.reset()
    socket = put_flash(socket, :info, "RCP reset command sent")
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("clear_frames", _params, socket) do
    # Clear old frames
    SpinelFrame.clear_old_frames!(older_than_minutes: 60)
    socket = put_flash(socket, :info, "Cleared frames older than 1 hour")
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:network_state_changed, _state}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:rcp_status_changed, _status}, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:spinel_frame_captured, _frame}, socket) do
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    # Load current state via Ash resources
    network = ThreadNetwork.read_all!() |> List.first()
    rcp_status = RCPStatus.current!()
    recent_frames = SpinelFrame.recent!(limit: 20, direction: nil)
    
    # Calculate statistics
    stats = calculate_stats(recent_frames)
    
    socket
    |> assign(:network, network)
    |> assign(:rcp_status, rcp_status)
    |> assign(:recent_frames, recent_frames)
    |> assign(:stats, stats)
    |> assign(:page_title, "Dashboard")
  end

  defp calculate_stats(frames) do
    total = length(frames)
    outbound = Enum.count(frames, &(&1.direction == :outbound))
    inbound = Enum.count(frames, &(&1.direction == :inbound))
    errors = Enum.count(frames, &(&1.status != :success))
    
    %{
      total: total,
      outbound: outbound,
      inbound: inbound,
      errors: errors,
      error_rate: if(total > 0, do: errors / total * 100, else: 0)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow-sm">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-3">
              <div class="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center">
                <span class="text-white font-bold text-xl">N</span>
              </div>
              <div>
                <h1 class="text-2xl font-bold text-gray-900">NTBR Border Router</h1>
                <p class="text-sm text-gray-500">Thread Network Management</p>
              </div>
            </div>
            
            <div class="flex items-center space-x-4">
              <button
                phx-click="refresh"
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Refresh
              </button>
              
              <%= if @rcp_status && @rcp_status.connected do %>
                <div class="flex items-center space-x-2 text-green-600">
                  <span class="relative flex h-3 w-3">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
                  </span>
                  <span class="text-sm font-medium">Connected</span>
                </div>
              <% else %>
                <div class="flex items-center space-x-2 text-red-600">
                  <span class="h-3 w-3 rounded-full bg-red-500"></span>
                  <span class="text-sm font-medium">Disconnected</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </header>

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Status Cards Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
          <!-- Network Status Card -->
          <.network_status_card network={@network} />
          
          <!-- RCP Status Card -->
          <.rcp_status_card rcp_status={@rcp_status} />
          
          <!-- Statistics Card -->
          <.statistics_card stats={@stats} />
        </div>

        <!-- Spinel Frames Section -->
        <div class="bg-white rounded-lg shadow-sm">
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-gray-900">Recent Spinel Frames</h2>
                <p class="text-sm text-gray-500 mt-1">Last 20 protocol frames</p>
              </div>
              <button
                phx-click="clear_frames"
                class="px-3 py-1 text-sm text-gray-600 hover:text-gray-900"
              >
                Clear Old
              </button>
            </div>
          </div>
          
          <.spinel_frames_table frames={@recent_frames} />
        </div>
      </main>
    </div>
    """
  end

  # Network Status Card Component
  defp network_status_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-sm font-medium text-gray-500">Thread Network</h3>
        <%= if @network && @network.is_active do %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
            Active
          </span>
        <% else %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
            Inactive
          </span>
        <% end %>
      </div>
      
      <%= if @network do %>
        <div class="space-y-3">
          <div>
            <p class="text-2xl font-bold text-gray-900"><%= @network.name %></p>
            <p class="text-sm text-gray-500 mt-1">Network Name</p>
          </div>
          
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= format_role(@network.role) %>
              </p>
              <p class="text-xs text-gray-500">Role</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                Channel <%= @network.channel || "—" %>
              </p>
              <p class="text-xs text-gray-500">IEEE 802.15.4</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= format_pan_id(@network.pan_id) %>
              </p>
              <p class="text-xs text-gray-500">PAN ID</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= @network.device_count || 0 %>
              </p>
              <p class="text-xs text-gray-500">Devices</p>
            </div>
          </div>
        </div>
      <% else %>
        <div class="text-center py-8">
          <p class="text-gray-500">No network configured</p>
        </div>
      <% end %>
    </div>
    """
  end

  # RCP Status Card Component
  defp rcp_status_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-sm font-medium text-gray-500">RCP Status</h3>
        <%= if @rcp_status && @rcp_status.is_healthy do %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
            Healthy
          </span>
        <% else %>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
            Error
          </span>
        <% end %>
      </div>
      
      <%= if @rcp_status do %>
        <div class="space-y-3">
          <div>
            <p class="text-2xl font-bold text-gray-900">
              <%= @rcp_status.port || "—" %>
            </p>
            <p class="text-sm text-gray-500 mt-1">Serial Port</p>
          </div>
          
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= format_number(@rcp_status.frames_sent) %>
              </p>
              <p class="text-xs text-gray-500">Frames Sent</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= format_number(@rcp_status.frames_received) %>
              </p>
              <p class="text-xs text-gray-500">Frames Received</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= format_number(@rcp_status.frames_errored) %>
              </p>
              <p class="text-xs text-gray-500">Errors</p>
            </div>
            
            <div>
              <p class="text-sm font-medium text-gray-900">
                <%= Float.round(@rcp_status.uptime_hours || 0, 1) %>h
              </p>
              <p class="text-xs text-gray-500">Uptime</p>
            </div>
          </div>
          
          <%= if @rcp_status.last_error do %>
            <div class="mt-3 p-2 bg-red-50 rounded">
              <p class="text-xs text-red-700"><%= @rcp_status.last_error %></p>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8">
          <p class="text-gray-500">RCP not initialized</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Statistics Card Component
  defp statistics_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-sm font-medium text-gray-500">Frame Statistics</h3>
        <span class="text-xs text-gray-400">Last 20 frames</span>
      </div>
      
      <div class="space-y-3">
        <div>
          <p class="text-2xl font-bold text-gray-900"><%= @stats.total %></p>
          <p class="text-sm text-gray-500 mt-1">Total Frames</p>
        </div>
        
        <div class="grid grid-cols-2 gap-4">
          <div>
            <p class="text-sm font-medium text-blue-600">
              <%= @stats.outbound %>
            </p>
            <p class="text-xs text-gray-500">Outbound</p>
          </div>
          
          <div>
            <p class="text-sm font-medium text-green-600">
              <%= @stats.inbound %>
            </p>
            <p class="text-xs text-gray-500">Inbound</p>
          </div>
        </div>
        
        <div class="mt-4">
          <div class="flex items-center justify-between text-sm mb-1">
            <span class="text-gray-500">Error Rate</span>
            <span class={[
              "font-medium",
              if(@stats.error_rate > 5, do: "text-red-600", else: "text-green-600")
            ]}>
              <%= Float.round(@stats.error_rate, 1) %>%
            </span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div
              class={[
                "h-2 rounded-full",
                if(@stats.error_rate > 5, do: "bg-red-500", else: "bg-green-500")
              ]}
              style={"width: #{min(@stats.error_rate, 100)}%"}
            >
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Spinel Frames Table Component
  defp spinel_frames_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Time
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Direction
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Command
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Property
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              TID
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Size
            </th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Status
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= for frame <- @frames do %>
            <tr class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= format_timestamp(frame.timestamp) %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  direction_color(frame.direction)
                ]}>
                  <%= frame.direction %>
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900">
                <%= format_command(frame.command) %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= frame.property || "—" %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= frame.tid %>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <%= frame.size_bytes %> B
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                  status_color(frame.status)
                ]}>
                  <%= frame.status %>
                </span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
      
      <%= if Enum.empty?(@frames) do %>
        <div class="text-center py-12">
          <p class="text-gray-500">No frames captured yet</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions
  defp format_role(role), do: role |> to_string() |> String.capitalize()
  
  defp format_pan_id(nil), do: "—"
  defp format_pan_id(pan_id), do: "0x#{Integer.to_string(pan_id, 16) |> String.pad_leading(4, "0")}"
  
  defp format_number(num), do: Number.Delimit.number_to_delimited(num, precision: 0)
  
  defp format_timestamp(nil), do: "—"
  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%H:%M:%S.%f")
    |> String.slice(0..-4)  # Remove last 3 microsecond digits
  end
  
  defp format_command(cmd), do: cmd |> to_string() |> String.upcase()
  
  defp direction_color(:outbound), do: "bg-blue-100 text-blue-800"
  defp direction_color(:inbound), do: "bg-green-100 text-green-800"
  
  defp status_color(:success), do: "bg-green-100 text-green-800"
  defp status_color(:error), do: "bg-red-100 text-red-800"
  defp status_color(:timeout), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:malformed), do: "bg-red-100 text-red-800"
end
