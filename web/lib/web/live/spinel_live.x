defmodule Web.SpinelLive do
  @moduledoc """
  Detailed Spinel protocol viewer LiveView.
  
  Provides in-depth inspection of Spinel frames including:
  - Real-time frame capture with filtering
  - Detailed frame structure breakdown
  - Hex dump of raw payloads
  - Request/response matching
  - Performance analytics
  """
  
  use Web, :live_view
  
  alias Core.Resources.SpinelFrame

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to frame captures
      # Phoenix.PubSub.subscribe(Web.PubSub, "spinel:frames")
    end
    
    socket =
      socket
      |> assign(:page_title, "Spinel Protocol Viewer")
      |> assign(:filter_direction, nil)
      |> assign(:filter_command, nil)
      |> assign(:selected_frame, nil)
      |> assign(:auto_scroll, true)
      |> load_frames()
    
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case SpinelFrame.read(id) do
      {:ok, frame} ->
        {:noreply, assign(socket, :selected_frame, frame)}
      {:error, _} ->
        {:noreply, push_patch(socket, to: ~p"/spinel")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_direction", %{"direction" => ""}, socket) do
    {:noreply, socket |> assign(:filter_direction, nil) |> load_frames()}
  end

  def handle_event("filter_direction", %{"direction" => direction}, socket) do
    dir = String.to_existing_atom(direction)
    {:noreply, socket |> assign(:filter_direction, dir) |> load_frames()}
  end

  @impl true
  def handle_event("filter_command", %{"command" => ""}, socket) do
    {:noreply, socket |> assign(:filter_command, nil) |> load_frames()}
  end

  def handle_event("filter_command", %{"command" => command}, socket) do
    cmd = String.to_existing_atom(command)
    {:noreply, socket |> assign(:filter_command, cmd) |> load_frames()}
  end

  @impl true
  def handle_event("toggle_auto_scroll", _params, socket) do
    {:noreply, assign(socket, :auto_scroll, !socket.assigns.auto_scroll)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      socket
      |> assign(:filter_direction, nil)
      |> assign(:filter_command, nil)
      |> load_frames()
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_frame", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/spinel/#{id}")}
  end

  @impl true
  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/spinel")}
  end

  @impl true
  def handle_event("decode_frame", %{"id" => id}, socket) do
    case SpinelFrame.decode_payload!(frame_id: id) do
      {:ok, _frame} ->
        socket = 
          socket
          |> put_flash(:info, "Frame decoded successfully")
          |> load_frames()
        {:noreply, socket}
      {:error, _} ->
        socket = put_flash(socket, :error, "Failed to decode frame")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:spinel_frame_captured, frame}, socket) do
    if socket.assigns.auto_scroll do
      {:noreply, load_frames(socket)}
    else
      {:noreply, socket}
    end
  end

  defp load_frames(socket) do
    frames = 
      case {socket.assigns.filter_direction, socket.assigns.filter_command} do
        {nil, nil} ->
          SpinelFrame.recent!(limit: 100, direction: nil)
        
        {dir, nil} when dir != nil ->
          SpinelFrame.recent!(limit: 100, direction: dir)
        
        {nil, cmd} when cmd != nil ->
          SpinelFrame.by_command!(command: cmd)
        
        {dir, cmd} ->
          SpinelFrame.by_command!(command: cmd)
          |> Enum.filter(&(&1.direction == dir))
      end
    
    assign(socket, :frames, frames)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow-sm sticky top-0 z-10">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-2xl font-bold text-gray-900">Spinel Protocol Viewer</h1>
              <p class="text-sm text-gray-500 mt-1">Real-time frame inspection and analysis</p>
            </div>
            
            <div class="flex items-center space-x-3">
              <label class="flex items-center space-x-2 text-sm text-gray-700">
                <input
                  type="checkbox"
                  checked={@auto_scroll}
                  phx-click="toggle_auto_scroll"
                  class="rounded border-gray-300"
                />
                <span>Auto-scroll</span>
              </label>
              
              <.link
                navigate={~p"/"}
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Back to Dashboard
              </.link>
            </div>
          </div>
        </div>
      </header>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="flex gap-6">
          <!-- Main Frame List -->
          <div class="flex-1">
            <!-- Filters -->
            <div class="bg-white rounded-lg shadow-sm p-4 mb-6">
              <div class="flex items-center gap-4">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Direction
                  </label>
                  <select
                    phx-change="filter_direction"
                    name="direction"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                  >
                    <option value="">All</option>
                    <option value="outbound" selected={@filter_direction == :outbound}>
                      Outbound
                    </option>
                    <option value="inbound" selected={@filter_direction == :inbound}>
                      Inbound
                    </option>
                  </select>
                </div>
                
                <div class="flex-1">
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Command
                  </label>
                  <select
                    phx-change="filter_command"
                    name="command"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                  >
                    <option value="">All</option>
                    <option value="prop_value_get" selected={@filter_command == :prop_value_get}>
                      PROP_VALUE_GET
                    </option>
                    <option value="prop_value_set" selected={@filter_command == :prop_value_set}>
                      PROP_VALUE_SET
                    </option>
                    <option value="prop_value_is" selected={@filter_command == :prop_value_is}>
                      PROP_VALUE_IS
                    </option>
                    <option value="reset" selected={@filter_command == :reset}>
                      RESET
                    </option>
                  </select>
                </div>
                
                <div class="pt-7">
                  <button
                    phx-click="clear_filters"
                    class="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200"
                  >
                    Clear
                  </button>
                </div>
              </div>
            </div>

            <!-- Frame Table -->
            <div class="bg-white rounded-lg shadow-sm overflow-hidden">
              <div class="overflow-x-auto max-h-[calc(100vh-20rem)] overflow-y-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50 sticky top-0">
                    <tr>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Seq
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Time
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Dir
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Command
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Property
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        TID
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Size
                      </th>
                      <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Status
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for frame <- @frames do %>
                      <tr
                        phx-click="select_frame"
                        phx-value-id={frame.id}
                        class={[
                          "cursor-pointer hover:bg-blue-50 transition-colors",
                          @selected_frame && @selected_frame.id == frame.id && "bg-blue-50"
                        ]}
                      >
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                          #<%= frame.sequence %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500 font-mono">
                          <%= format_time(frame.timestamp) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.direction_badge direction={frame.direction} />
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm font-mono text-gray-900">
                          <%= format_command(frame.command) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-600">
                          <%= format_property(frame.property) %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500 text-center">
                          <%= frame.tid %>
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                          <%= frame.size_bytes %> B
                        </td>
                        <td class="px-4 py-3 whitespace-nowrap">
                          <.status_badge status={frame.status} />
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
                
                <%= if Enum.empty?(@frames) do %>
                  <div class="text-center py-12">
                    <p class="text-gray-500">No frames match the current filters</p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Frame Detail Panel -->
          <%= if @selected_frame do %>
            <div class="w-96 flex-shrink-0">
              <.frame_detail_panel frame={@selected_frame} />
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Frame Detail Panel Component
  defp frame_detail_panel(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm overflow-hidden sticky top-24">
      <!-- Header -->
      <div class="px-4 py-3 bg-gray-50 border-b border-gray-200 flex items-center justify-between">
        <h3 class="text-sm font-semibold text-gray-900">Frame Details</h3>
        <button
          phx-click="close_detail"
          class="text-gray-400 hover:text-gray-600"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Content -->
      <div class="p-4 space-y-4 max-h-[calc(100vh-12rem)] overflow-y-auto">
        <!-- Sequence & Timestamp -->
        <div>
          <h4 class="text-xs font-medium text-gray-500 uppercase mb-2">Metadata</h4>
          <dl class="space-y-2">
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">Sequence:</dt>
              <dd class="text-sm font-medium text-gray-900">#<%= @frame.sequence %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">Timestamp:</dt>
              <dd class="text-sm font-mono text-gray-900">
                <%= format_full_timestamp(@frame.timestamp) %>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">Direction:</dt>
              <dd><.direction_badge direction={@frame.direction} /></dd>
            </div>
          </dl>
        </div>

        <!-- Frame Structure -->
        <div>
          <h4 class="text-xs font-medium text-gray-500 uppercase mb-2">Frame Structure</h4>
          <dl class="space-y-2">
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">Header:</dt>
              <dd class="text-sm font-mono text-gray-900">
                0x<%= Integer.to_string(@frame.header || 0, 16) |> String.pad_leading(2, "0") |> String.upcase() %>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">Command:</dt>
              <dd class="text-sm font-mono text-gray-900">
                <%= format_command(@frame.command) %>
              </dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-sm text-gray-600">TID:</dt>
              <dd class="text-sm font-mono text-gray-900"><%= @frame.tid %></dd>
            </div>
            <%= if @frame.property do %>
              <div class="flex justify-between">
                <dt class="text-sm text-gray-600">Property:</dt>
                <dd class="text-sm font-mono text-gray-900">
                  <%= format_property(@frame.property) %>
                </dd>
              </div>
            <% end %>
            <%= if @frame.property_id do %>
              <div class="flex justify-between">
                <dt class="text-sm text-gray-600">Property ID:</dt>
                <dd class="text-sm font-mono text-gray-900">
                  <%= @frame.property_id %>
                </dd>
              </div>
            <% end %>
          </dl>
        </div>

        <!-- Payload -->
        <%= if @frame.payload && byte_size(@frame.payload) > 0 do %>
          <div>
            <div class="flex items-center justify-between mb-2">
              <h4 class="text-xs font-medium text-gray-500 uppercase">Payload</h4>
              <span class="text-xs text-gray-400">
                <%= byte_size(@frame.payload) %> bytes
              </span>
            </div>
            <div class="bg-gray-900 rounded p-3 overflow-x-auto">
              <pre class="text-xs font-mono text-green-400"><%= format_hex_dump(@frame.payload) %></pre>
            </div>
            
            <%= if !@frame.payload_decoded do %>
              <button
                phx-click="decode_frame"
                phx-value-id={@frame.id}
                class="mt-2 w-full px-3 py-2 text-sm font-medium text-blue-700 bg-blue-50 rounded hover:bg-blue-100"
              >
                Decode Payload
              </button>
            <% end %>
          </div>
        <% end %>

        <!-- Decoded Payload -->
        <%= if @frame.payload_decoded do %>
          <div>
            <h4 class="text-xs font-medium text-gray-500 uppercase mb-2">Decoded Data</h4>
            <div class="bg-gray-50 rounded p-3">
              <pre class="text-xs font-mono text-gray-900"><%= inspect(@frame.payload_decoded, pretty: true) %></pre>
            </div>
          </div>
        <% end %>

        <!-- Status -->
        <div>
          <h4 class="text-xs font-medium text-gray-500 uppercase mb-2">Status</h4>
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600">Frame Status:</span>
            <.status_badge status={@frame.status} />
          </div>
          <%= if @frame.error_message do %>
            <div class="mt-2 p-2 bg-red-50 rounded">
              <p class="text-xs text-red-700"><%= @frame.error_message %></p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Direction Badge Component
  defp direction_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      direction_color(@direction)
    ]}>
      <%= if @direction == :outbound do %>
        ← OUT
      <% else %>
        → IN
      <% end %>
    </span>
    """
  end

  # Status Badge Component
  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium",
      status_color(@status)
    ]}>
      <%= @status %>
    </span>
    """
  end

  # Helper Functions
  defp format_time(nil), do: "—"
  defp format_time(dt) do
    Calendar.strftime(dt, "%H:%M:%S.%f")
    |> String.slice(0..-4)
  end

  defp format_full_timestamp(nil), do: "—"
  defp format_full_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S.%f")
    |> String.slice(0..-4)
  end

  defp format_command(cmd) do
    cmd
    |> to_string()
    |> String.upcase()
    |> String.replace("_", " ")
  end

  defp format_property(nil), do: "—"
  defp format_property(prop) do
    prop
    |> to_string()
    |> String.upcase()
    |> String.replace("_", " ")
  end

  defp format_hex_dump(binary) when byte_size(binary) == 0, do: "(empty)"
  defp format_hex_dump(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      offset = Integer.to_string(idx * 16, 16) |> String.pad_leading(4, "0")
      
      hex = chunk
      |> Enum.map(&(Integer.to_string(&1, 16) |> String.pad_leading(2, "0")))
      |> Enum.join(" ")
      |> String.pad_trailing(47)
      
      ascii = chunk
      |> Enum.map(fn byte ->
        if byte >= 32 and byte <= 126, do: <<byte>>, else: "."
      end)
      |> Enum.join()
      
      "#{offset}  #{hex}  |#{ascii}|"
    end)
    |> Enum.join("\n")
  end

  defp direction_color(:outbound), do: "bg-blue-100 text-blue-800"
  defp direction_color(:inbound), do: "bg-green-100 text-green-800"

  defp status_color(:success), do: "bg-green-100 text-green-800"
  defp status_color(:error), do: "bg-red-100 text-red-800"
  defp status_color(:timeout), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:malformed), do: "bg-red-100 text-red-800"
end