defmodule NTBR.Web.JoinerLive.FormComponent do
  @moduledoc """
  LiveComponent for adding joiners to the network.
  """
  use NTBR.Web, :live_component

  alias NTBR.Domain

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:joiner_type, :specific)
     |> assign(:form_errors, [])}
  end

  @impl true
  def handle_event("change_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :joiner_type, String.to_atom(type))}
  end

  @impl true
  def handle_event("save", %{"joiner" => params}, socket) do
    result =
      case socket.assigns.joiner_type do
        :wildcard ->
          Domain.Joiner.create_any(%{
            network_id: socket.assigns.network_id,
            pskd: params["pskd"],
            timeout: String.to_integer(params["timeout"] || "120")
          })

        :specific ->
          eui64 = parse_eui64(params["eui64"])

          Domain.Joiner.create(%{
            network_id: socket.assigns.network_id,
            eui64: eui64,
            pskd: params["pskd"],
            timeout: String.to_integer(params["timeout"] || "120"),
            vendor_name: params["vendor_name"],
            vendor_model: params["vendor_model"]
          })
      end

    case result do
      {:ok, _joiner} ->
        {:noreply,
         socket
         |> put_flash(:info, "Joiner added successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :form_errors, ["Failed to create joiner"])}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, push_patch(socket, to: socket.assigns.patch)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-start mb-6">
        <h3 class="text-2xl font-bold">Add Joiner</h3>
        <button phx-click="close" phx-target={@myself} class="btn btn-sm btn-circle btn-ghost">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <div class="tabs tabs-boxed mb-6">
        <button
          phx-click="change_type"
          phx-value-type="specific"
          phx-target={@myself}
          class={"tab #{if @joiner_type == :specific, do: "tab-active"}"}
        >
          Specific Device
        </button>
        <button
          phx-click="change_type"
          phx-value-type="wildcard"
          phx-target={@myself}
          class={"tab #{if @joiner_type == :wildcard, do: "tab-active"}"}
        >
          Wildcard (Any Device)
        </button>
      </div>

      <form phx-submit="save" phx-target={@myself} class="space-y-4">
        <%= if @form_errors != [] do %>
          <div class="alert alert-error">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span><%= Enum.join(@form_errors, ", ") %></span>
          </div>
        <% end %>

        <%= if @joiner_type == :specific do %>
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-semibold">EUI-64 Address <span class="text-error">*</span></span>
              <span class="label-text-alt">16 hex characters</span>
            </label>
            <input
              type="text"
              name="joiner[eui64]"
              placeholder="00124B0014B5B5B5"
              class="input input-bordered w-full font-mono"
              pattern="[0-9A-Fa-f]{16}"
              required
            />
            <label class="label">
              <span class="label-text-alt text-base-content/60">Example: 00124B0014B5B5B5</span>
            </label>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="form-control w-full">
              <label class="label">
                <span class="label-text font-semibold">Vendor Name</span>
              </label>
              <input
                type="text"
                name="joiner[vendor_name]"
                placeholder="e.g., Acme Corp"
                class="input input-bordered w-full"
              />
            </div>

            <div class="form-control w-full">
              <label class="label">
                <span class="label-text font-semibold">Vendor Model</span>
              </label>
              <input
                type="text"
                name="joiner[vendor_model]"
                placeholder="e.g., SmartPlug-100"
                class="input input-bordered w-full"
              />
            </div>
          </div>
        <% else %>
          <div class="alert alert-warning">
            <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <div>
              <h4 class="font-bold">Security Warning</h4>
              <div class="text-xs">Wildcard joiners allow ANY device to join your network during the timeout period</div>
            </div>
          </div>
        <% end %>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-semibold">Pre-Shared Key (PSKd) <span class="text-error">*</span></span>
            <span class="label-text-alt">6-32 characters</span>
          </label>
          <input
            type="text"
            name="joiner[pskd]"
            placeholder="J01NME"
            class="input input-bordered w-full font-mono"
            minlength="6"
            maxlength="32"
            required
          />
          <label class="label">
            <span class="label-text-alt text-base-content/60">This is the commissioning credential</span>
          </label>
        </div>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-semibold">Timeout (seconds)</span>
          </label>
          <input
            type="range"
            name="joiner[timeout]"
            min="30"
            max="600"
            value="120"
            class="range range-primary"
            step="30"
          />
          <div class="w-full flex justify-between text-xs px-2 mt-1">
            <span>30s</span>
            <span>2m</span>
            <span>5m</span>
            <span>10m</span>
          </div>
        </div>

        <div class="divider"></div>

        <div class="modal-action">
          <button type="button" phx-click="close" phx-target={@myself} class="btn btn-ghost">
            Cancel
          </button>
          <button type="submit" class="btn btn-primary gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M8 9a3 3 0 100-6 3 3 0 000 6zM8 11a6 6 0 016 6H2a6 6 0 016-6zM16 7a1 1 0 10-2 0v1h-1a1 1 0 100 2h1v1a1 1 0 102 0v-1h1a1 1 0 100-2h-1V7z" />
            </svg>
            Add Joiner
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp parse_eui64(hex_string) do
    hex_string
    |> String.replace(~r/[^0-9A-Fa-f]/, "")
    |> String.upcase()
    |> Base.decode16!()
  end
end

defmodule NTBR.Web.Components.NetworkTopology do
  @moduledoc """
  Component for visualizing Thread network topology.
  """
  use Phoenix.Component

  def topology_graph(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-xl">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zM14 16a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z" />
          </svg>
          Network Topology
        </h2>

        <div class="flex flex-wrap gap-4 justify-center p-8">
          <%= for device <- @devices do %>
            <.device_node device={device} />
          <% end %>
        </div>

        <div class="flex gap-4 justify-center text-xs">
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-primary"></div>
            <span>Leader</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-success"></div>
            <span>Router</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-base-300"></div>
            <span>End Device</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp device_node(assigns) do
    ~H"""
    <div class="tooltip" data-tip={"RLOC16: 0x#{Integer.to_string(@device.rloc16, 16)}"}>
      <div class={[
        "avatar placeholder",
        if(@device.device_type == :leader, do: "ring ring-primary ring-offset-base-100 ring-offset-2"),
        if(@device.device_type == :router, do: "ring ring-success ring-offset-base-100 ring-offset-2")
      ]}>
        <div class={[
          "w-16 rounded-full",
          case @device.device_type do
            :leader -> "bg-primary text-primary-content"
            :router -> "bg-success text-success-content"
            _ -> "bg-base-300 text-base-content"
          end
        ]}>
          <span class="text-xs font-bold">
            <%= String.slice(Integer.to_string(@device.rloc16, 16), -4..-1) %>
          </span>
        </div>
      </div>
    </div>
    """
  end
end

defmodule NTBR.Web.Components.NetworkStats do
  @moduledoc """
  Real-time statistics component for network health.
  """
  use Phoenix.Component

  def stats_panel(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <div class="stat bg-base-200 rounded-box shadow">
        <div class="stat-figure text-primary">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
          </svg>
        </div>
        <div class="stat-title">Avg Link Quality</div>
        <div class="stat-value text-primary"><%= @avg_link_quality %></div>
        <div class="stat-desc">↗︎ Last 5 minutes</div>
      </div>

      <div class="stat bg-base-200 rounded-box shadow">
        <div class="stat-figure text-secondary">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
          </svg>
        </div>
        <div class="stat-title">Avg RSSI</div>
        <div class="stat-value text-secondary"><%= @avg_rssi %> dBm</div>
        <div class="stat-desc">Signal strength</div>
      </div>

      <div class="stat bg-base-200 rounded-box shadow">
        <div class="stat-figure text-accent">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <div class="stat-title">Network Uptime</div>
        <div class="stat-value text-accent"><%= @uptime %></div>
        <div class="stat-desc">Since last restart</div>
      </div>

      <div class="stat bg-base-200 rounded-box shadow">
        <div class="stat-figure text-info">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-8 h-8" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
          </svg>
        </div>
        <div class="stat-title">Data Rate</div>
        <div class="stat-value text-info"><%= @data_rate %></div>
        <div class="stat-desc">Packets/sec</div>
      </div>
    </div>
    """
  end
end

defmodule NTBR.Web.Components.Alerts do
  @moduledoc """
  Toast notifications and alert components using DaisyUI.
  """
  use Phoenix.Component

  def flash_group(assigns) do
    ~H"""
    <div class="toast toast-top toast-end z-50">
      <%= if @flash["info"] do %>
        <div class="alert alert-info shadow-lg">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <span><%= @flash["info"] %></span>
        </div>
      <% end %>

      <%= if @flash["error"] do %>
        <div class="alert alert-error shadow-lg">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span><%= @flash["error"] %></span>
        </div>
      <% end %>

      <%= if @flash["warning"] do %>
        <div class="alert alert-warning shadow-lg">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <span><%= @flash["warning"] %></span>
        </div>
      <% end %>

      <%= if @flash["success"] do %>
        <div class="alert alert-success shadow-lg">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span><%= @flash["success"] %></span>
        </div>
      <% end %>
    </div>
    """
  end

  def connection_status(assigns) do
    ~H"""
    <div class="indicator">
      <span class={"indicator-item badge badge-sm #{if @connected, do: "badge-success", else: "badge-error"}"}>
        <%= if @connected, do: "●", else: "○" %>
      </span>
      <div class="tooltip tooltip-bottom" data-tip={if @connected, do: "Connected", else: "Disconnected"}>
        <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
        </svg>
      </div>
    </div>
    """
  end
end

defmodule NTBR.Web.Components.LoadingStates do
  @moduledoc """
  Loading and skeleton components.
  """
  use Phoenix.Component

  def loading_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex flex-col gap-4">
          <div class="skeleton h-8 w-1/2"></div>
          <div class="skeleton h-4 w-full"></div>
          <div class="skeleton h-4 w-3/4"></div>
          <div class="skeleton h-4 w-5/6"></div>
        </div>
      </div>
    </div>
    """
  end

  def loading_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table w-full">
        <thead>
          <tr>
            <th><div class="skeleton h-4 w-20"></div></th>
            <th><div class="skeleton h-4 w-20"></div></th>
            <th><div class="skeleton h-4 w-20"></div></th>
          </tr>
        </thead>
        <tbody>
          <%= for _ <- 1..5 do %>
            <tr>
              <td><div class="skeleton h-4 w-24"></div></td>
              <td><div class="skeleton h-4 w-16"></div></td>
              <td><div class="skeleton h-4 w-20"></div></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  def spinner(assigns) do
    assigns = assign_new(assigns, :size, fn -> "md" end)

    ~H"""
    <span class={"loading loading-spinner loading-#{@size}"}></span>
    """
  end
end

defmodule NTBR.Web.Components.Navigation do
  @moduledoc """
  Navigation components using DaisyUI.
  """
  use Phoenix.Component
  import Phoenix.LiveView.Helpers

  def navbar(assigns) do
    ~H"""
    <div class="navbar bg-base-200 shadow-lg">
      <div class="navbar-start">
        <div class="dropdown">
          <label tabindex="0" class="btn btn-ghost lg:hidden">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h8m-8 6h16" />
            </svg>
          </label>
          <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
            <li><.link navigate={~p"/networks"}>Networks</.link></li>
            <li><.link navigate={~p"/devices"}>Devices</.link></li>
            <li><.link navigate={~p"/joiners"}>Joiners</.link></li>
            <li><.link navigate={~p"/settings"}>Settings</.link></li>
          </ul>
        </div>
        <.link navigate={~p"/"} class="btn btn-ghost normal-case text-xl gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clip-rule="evenodd" />
          </svg>
          NTBR
        </.link>
      </div>

      <div class="navbar-center hidden lg:flex">
        <ul class="menu menu-horizontal px-1">
          <li><.link navigate={~p"/networks"} class="btn btn-ghost">Networks</.link></li>
          <li><.link navigate={~p"/devices"} class="btn btn-ghost">Devices</.link></li>
          <li><.link navigate={~p"/joiners"} class="btn btn-ghost">Joiners</.link></li>
          <li><.link navigate={~p"/settings"} class="btn btn-ghost">Settings</.link></li>
        </ul>
      </div>

      <div class="navbar-end gap-2">
        <div class="tooltip tooltip-bottom" data-tip="Documentation">
          <button class="btn btn-ghost btn-circle">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </button>
        </div>

        <div class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-ghost btn-circle">
            <div class="indicator">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              <%= if @pending_count > 0 do %>
                <span class="badge badge-xs badge-primary indicator-item"><%= @pending_count %></span>
              <% end %>
            </div>
          </label>
          <ul tabindex="0" class="mt-3 z-[1] p-2 shadow menu menu-sm dropdown-content bg-base-100 rounded-box w-52">
            <li><a>Theme</a></li>
            <li><a>Settings</a></li>
            <li><a>Logs</a></li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  def breadcrumbs(assigns) do
    ~H"""
    <div class="text-sm breadcrumbs">
      <ul>
        <%= for crumb <- @items do %>
          <li>
            <%= if crumb.link do %>
              <.link navigate={crumb.link}><%= crumb.name %></.link>
            <% else %>
              <%= crumb.name %>
            <% end %>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end
end

defmodule NTBRWeb.Components.Modals do
  @moduledoc """
  Modal dialog components.
  """
  use Phoenix.Component

  def confirm_modal(assigns) do
    ~H"""
    <dialog id={@id} class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg"><%= @title %></h3>
        <p class="py-4"><%= @message %></p>
        <div class="modal-action">
          <form method="dialog">
            <button class="btn btn-ghost">Cancel</button>
            <button phx-click={@confirm_action} class="btn btn-error">
              <%= @confirm_text || "Confirm" %>
            </button>
          </form>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
