defmodule NTBR.Web.NetworkLive.Index do
  @moduledoc """
  Main dashboard for Thread Border Router network management.
  Uses DaisyUI components for styling.
  """
  use NTBR.Web, :live_view

  alias NTBR.Domain

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NTBR.PubSub, "spinel:events")
      :timer.send_interval(5_000, self(), :refresh)
    end

    socket =
      socket
      |> assign(:page_title, "Thread Network")
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Networks")
    |> assign(:show_form, false)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Network")
    |> assign(:show_form, true)
  end

  @impl true
  def handle_event("delete_network", %{"id" => id}, socket) do
    network = Domain.Network.read!(id)
    {:ok, _} = Domain.Network.destroy(network)

    socket =
      socket
      |> put_flash(:info, "Network deleted successfully")
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("attach_network", %{"id" => id}, socket) do
    case Domain.NetworkManager.attach_network(id) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Attaching to network...")
          |> load_data()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to attach: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("detach_network", _params, socket) do
    :ok = Domain.NetworkManager.detach_network()

    socket =
      socket
      |> put_flash(:info, "Network detached")
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_form", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/networks")}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:spinel_event, _type, _data}, socket) do
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    networks = Domain.Network.read!()
    active_network = Domain.Network.active_network() |> Enum.at(0)
    devices = if active_network, do: Domain.Device.by_network(active_network.id), else: []
    border_router = if active_network, do: Domain.BorderRouter.by_network(active_network.id) |> Enum.at(0), else: nil
    active_joiners = Domain.Joiner.active()

    socket
    |> assign(:networks, networks)
    |> assign(:active_network, active_network)
    |> assign(:devices, devices)
    |> assign(:border_router, border_router)
    |> assign(:active_joiners, active_joiners)
    |> assign(:manager_state, Domain.NetworkManager.get_state())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4 space-y-6">
      <!-- Header -->
      <div class="flex justify-between items-center">
        <h1 class="text-4xl font-bold">Thread Border Router</h1>
        <.link patch={~p"/networks/new"} class="btn btn-primary gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
          </svg>
          New Network
        </.link>
      </div>

      <!-- Stats Cards -->
      <div class="stats stats-vertical lg:stats-horizontal shadow w-full">
        <div class="stat">
          <div class="stat-figure text-primary">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
            </svg>
          </div>
          <div class="stat-title">Network Status</div>
          <div class={"stat-value #{if @active_network, do: "text-success", else: "text-base-content/50"}"}>
            <%= if @active_network, do: format_state(@active_network.state), else: "Detached" %>
          </div>
          <div class="stat-desc">
            <%= if @active_network, do: "Role: #{@active_network.role}", else: "No active network" %>
          </div>
        </div>

        <div class="stat">
          <div class="stat-figure text-secondary">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
            </svg>
          </div>
          <div class="stat-title">Connected Devices</div>
          <div class="stat-value text-secondary"><%= length(@devices) %></div>
          <div class="stat-desc">
            <%= Enum.count(@devices, & &1.device_type in [:router, :leader]) %> routers
          </div>
        </div>

        <div class="stat">
          <div class="stat-figure text-accent">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-8 h-8 stroke-current">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"></path>
            </svg>
          </div>
          <div class="stat-title">Active Joiners</div>
          <div class="stat-value text-accent"><%= length(@active_joiners) %></div>
          <div class="stat-desc">Commissioning devices</div>
        </div>
      </div>

      <!-- Networks Card -->
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
            </svg>
            Networks
          </h2>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Network Name</th>
                  <th>Channel</th>
                  <th>PAN ID</th>
                  <th>State</th>
                  <th>Role</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= if @networks == [] do %>
                  <tr>
                    <td colspan="7" class="text-center text-base-content/50 py-8">
                      No networks configured. Create one to get started!
                    </td>
                  </tr>
                <% else %>
                  <%= for network <- @networks do %>
                    <tr>
                      <td>
                        <div class="font-bold"><%= network.name %></div>
                        <div class="text-sm opacity-50">
                          <%= Calendar.strftime(network.created_at, "%Y-%m-%d %H:%M") %>
                        </div>
                      </td>
                      <td><%= network.network_name %></td>
                      <td><span class="badge badge-outline"><%= network.channel %></span></td>
                      <td><code class="text-xs"><%= "0x#{String.upcase(Integer.to_string(network.pan_id, 16))}" %></code></td>
                      <td>
                        <div class={"badge #{state_badge_class(network.state)}"}>
                          <%= format_state(network.state) %>
                        </div>
                      </td>
                      <td>
                        <div class="badge badge-ghost">
                          <%= format_role(network.role) %>
                        </div>
                      </td>
                      <td>
                        <div class="flex gap-2 justify-end">
                          <%= if network.state == :detached do %>
                            <button
                              phx-click="attach_network"
                              phx-value-id={network.id}
                              class="btn btn-success btn-sm gap-2"
                            >
                              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-8.707l-3-3a1 1 0 00-1.414 1.414L10.586 9H7a1 1 0 100 2h3.586l-1.293 1.293a1 1 0 101.414 1.414l3-3a1 1 0 000-1.414z" clip-rule="evenodd" />
                              </svg>
                              Attach
                            </button>
                          <% else %>
                            <button
                              phx-click="detach_network"
                              class="btn btn-warning btn-sm gap-2"
                            >
                              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                              </svg>
                              Detach
                            </button>
                          <% end %>
                          <button
                            phx-click="delete_network"
                            phx-value-id={network.id}
                            data-confirm="Are you sure you want to delete this network?"
                            class="btn btn-error btn-sm btn-outline"
                          >
                            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                              <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
                            </svg>
                          </button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%= if @active_network do %>
        <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <!-- Devices Card -->
          <.device_card devices={@devices} />

          <!-- Joiners Card -->
          <.joiner_card joiners={@active_joiners} network_id={@active_network.id} />
        </div>

        <%= if @border_router do %>
          <.border_router_card border_router={@border_router} />
        <% end %>
      <% end %>

      <!-- Network Form Modal -->
      <%= if @show_form do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <.live_component
              module={NTBRWeb.NetworkLive.FormComponent}
              id={:new}
              title="Create New Network"
              action={:new}
              patch={~p"/networks"}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Component Functions

  defp device_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-xl">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
          </svg>
          Devices (<%= length(@devices) %>)
        </h2>
        <div class="overflow-x-auto">
          <%= if @devices == [] do %>
            <div class="alert alert-info">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <span>No devices discovered yet. Waiting for topology updates...</span>
            </div>
          <% else %>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>RLOC16</th>
                  <th>Type</th>
                  <th>Link Quality</th>
                  <th>RSSI</th>
                  <th>Last Seen</th>
                </tr>
              </thead>
              <tbody>
                <%= for device <- @devices do %>
                  <tr class={unless device.active, do: "opacity-50"}>
                    <td>
                      <code class="text-xs font-mono">
                        <%= "0x#{String.upcase(String.pad_leading(Integer.to_string(device.rloc16, 16), 4, "0"))}" %>
                      </code>
                    </td>
                    <td>
                      <div class={"badge #{device_type_badge_class(device.device_type)}"}>
                        <%= format_device_type(device.device_type) %>
                      </div>
                    </td>
                    <td>
                      <%= if device.link_quality do %>
                        <div class="flex items-center gap-2">
                          <progress class="progress progress-success w-16" value={device.link_quality} max="3"></progress>
                          <span class="text-xs"><%= device.link_quality %></span>
                        </div>
                      <% else %>
                        <span class="text-base-content/50">N/A</span>
                      <% end %>
                    </td>
                    <td>
                      <%= if device.rssi do %>
                        <span class={"badge badge-sm #{rssi_badge_class(device.rssi)}"}>
                          <%= device.rssi %> dBm
                        </span>
                      <% else %>
                        <span class="text-base-content/50">N/A</span>
                      <% end %>
                    </td>
                    <td>
                      <div class="text-xs">
                        <%= Calendar.strftime(device.last_seen, "%H:%M:%S") %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp joiner_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-xl">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
          </svg>
          Active Joiners (<%= length(@joiners) %>)
        </h2>
        <div class="overflow-x-auto">
          <%= if @joiners == [] do %>
            <div class="alert">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-info shrink-0 w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <div>
                <h3 class="font-bold">No active joiners</h3>
                <div class="text-xs">Add a joiner to allow devices to join the network</div>
              </div>
              <button class="btn btn-sm btn-primary">Add Joiner</button>
            </div>
          <% else %>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>EUI64</th>
                  <th>State</th>
                  <th>Time Left</th>
                  <th>Vendor</th>
                </tr>
              </thead>
              <tbody>
                <%= for joiner <- @joiners do %>
                  <tr>
                    <td>
                      <%= if joiner.eui64 do %>
                        <code class="text-xs font-mono"><%= String.slice(Base.encode16(joiner.eui64), 0..15) %></code>
                      <% else %>
                        <div class="badge badge-ghost badge-sm">
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3 mr-1" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clip-rule="evenodd" />
                          </svg>
                          Wildcard
                        </div>
                      <% end %>
                    </td>
                    <td>
                      <div class={"badge badge-sm #{joiner_state_badge_class(joiner.state)}"}>
                        <%= format_joiner_state(joiner.state) %>
                      </div>
                    </td>
                    <td>
                      <div class="flex items-center gap-2">
                        <span class="text-xs"><%= format_time_remaining(joiner.expires_at) %></span>
                        <%= if joiner.state == :joining do %>
                          <span class="loading loading-spinner loading-xs"></span>
                        <% end %>
                      </div>
                    </td>
                    <td>
                      <div class="text-xs">
                        <%= joiner.vendor_name || "Unknown" %>
                        <%= if joiner.vendor_model, do: " - #{joiner.vendor_model}" %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp border_router_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-xl mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
          </svg>
          Border Router Configuration
          <%= if @border_router.operational do %>
            <div class="badge badge-success gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
              </svg>
              Operational
            </div>
          <% else %>
            <div class="badge badge-ghost gap-2">Not Operational</div>
          <% end %>
        </h2>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Infrastructure</div>
            <div class="stat-value text-2xl"><%= @border_router.infrastructure_interface %></div>
            <div class="stat-desc">Network interface</div>
          </div>

          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">On-Mesh Prefix</div>
            <div class="stat-value text-sm font-mono"><%= String.slice(@border_router.on_mesh_prefix, 0..19) %></div>
            <div class="stat-desc"><%= String.slice(@border_router.on_mesh_prefix, 20..-1) %></div>
          </div>

          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Active Services</div>
            <div class="stat-value text-2xl">
              <%= Enum.count([
                @border_router.enable_nat64,
                @border_router.enable_mdns,
                @border_router.enable_srp_server
              ], & &1) %>
            </div>
            <div class="stat-desc">of 3 enabled</div>
          </div>
        </div>

        <div class="divider">Services</div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div class={"alert #{if @border_router.enable_nat64, do: "alert-success", else: "alert-ghost"}"}>
            <div>
              <div class="font-bold flex items-center gap-2">
                <%= if @border_router.enable_nat64 do %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                  </svg>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                  </svg>
                <% end %>
                NAT64
              </div>
              <div class="text-xs">IPv4/IPv6 translation</div>
            </div>
          </div>

          <div class={"alert #{if @border_router.enable_mdns, do: "alert-success", else: "alert-ghost"}"}>
            <div>
              <div class="font-bold flex items-center gap-2">
                <%= if @border_router.enable_mdns do %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                  </svg>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                  </svg>
                <% end %>
                mDNS
              </div>
              <div class="text-xs">Service discovery</div>
            </div>
          </div>

          <div class={"alert #{if @border_router.enable_srp_server, do: "alert-success", else: "alert-ghost"}"}>
            <div>
              <div class="font-bold flex items-center gap-2">
                <%= if @border_router.enable_srp_server do %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                  </svg>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                  </svg>
                <% end %>
                SRP Server
              </div>
              <div class="text-xs">Port <%= @border_router.srp_server_port %></div>
            </div>
          </div>

          <div class={"alert #{if @border_router.enable_dhcpv6_pd, do: "alert-success", else: "alert-ghost"}"}>
            <div>
              <div class="font-bold flex items-center gap-2">
                <%= if @border_router.enable_dhcpv6_pd do %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                  </svg>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                  </svg>
                <% end %>
                DHCPv6-PD
              </div>
              <div class="text-xs">Prefix delegation</div>
            </div>
          </div>
        </div>

        <%= if @border_router.external_routes != [] do %>
          <div class="divider">External Routes</div>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Prefix</th>
                  <th>Preference</th>
                  <th>Stable</th>
                </tr>
              </thead>
              <tbody>
                <%= for route <- @border_router.external_routes do %>
                  <tr>
                    <td><code class="text-xs"><%= route.prefix %></code></td>
                    <td>
                      <div class={"badge badge-sm #{route_preference_badge_class(route.preference)}"}>
                        <%= route.preference %>
                      </div>
                    </td>
                    <td>
                      <%= if route.stable do %>
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" viewBox="0 0 20 20" fill="currentColor">
                          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                        </svg>
                      <% else %>
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-base-content/30" viewBox="0 0 20 20" fill="currentColor">
                          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                        </svg>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp state_badge_class(:detached), do: "badge-ghost"
  defp state_badge_class(:child), do: "badge-info"
  defp state_badge_class(:router), do: "badge-success"
  defp state_badge_class(:leader), do: "badge-secondary"
  defp state_badge_class(:disabled), do: "badge-error"
  defp state_badge_class(_), do: "badge-ghost"

  defp format_state(state), do: state |> to_string() |> String.capitalize()
  defp format_role(role), do: role |> to_string() |> String.capitalize()

  defp device_type_badge_class(:end_device), do: "badge-ghost"
  defp device_type_badge_class(:router), do: "badge-success"
  defp device_type_badge_class(:leader), do: "badge-primary"
  defp device_type_badge_class(:reed), do: "badge-info"

  defp format_device_type(:end_device), do: "End Device"
  defp format_device_type(:router), do: "Router"
  defp format_device_type(:leader), do: "Leader"
  defp format_device_type(:reed), do: "REED"

  defp rssi_badge_class(rssi) when rssi >= -60, do: "badge-success"
  defp rssi_badge_class(rssi) when rssi >= -80, do: "badge-warning"
  defp rssi_badge_class(_), do: "badge-error"

  defp joiner_state_badge_class(:pending), do: "badge-warning"
  defp joiner_state_badge_class(:joining), do: "badge-info"
  defp joiner_state_badge_class(:joined), do: "badge-success"
  defp joiner_state_badge_class(:failed), do: "badge-error"
  defp joiner_state_badge_class(:expired), do: "badge-ghost"

  defp format_joiner_state(state), do: state |> to_string() |> String.capitalize()

  defp route_preference_badge_class(:high), do: "badge-success"
  defp route_preference_badge_class(:medium), do: "badge-warning"
  defp route_preference_badge_class(:low), do: "badge-ghost"

  defp format_time_remaining(nil), do: "N/A"

  defp format_time_remaining(expires_at) do
    diff = DateTime.diff(expires_at, DateTime.utc_now())

    cond do
      diff < 0 -> "Expired"
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
      true -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
    end
  end
end

defmodule NTBR.Web.NetworkLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing Thread networks.
  Uses DaisyUI form components.
  """
  use NTBR.Web, :live_component

  alias NTBR.Domain

  @impl true
  def update(%{action: action} = assigns, socket) do
    changeset = Ash.Changeset.for_create(Domain.Network, :create, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:action, action)}
  end

  @impl true
  def handle_event("validate", %{"network" => network_params}, socket) do
    changeset =
      Domain.Network
      |> Ash.Changeset.for_create(:create, network_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"network" => network_params}, socket) do
    case Domain.Network.create(network_params) do
      {:ok, _network} ->
        {:noreply,
         socket
         |> put_flash(:info, "Network created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
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
        <h3 class="text-2xl font-bold"><%= @title %></h3>
        <button phx-click="close" phx-target={@myself} class="btn btn-sm btn-circle btn-ghost">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <form phx-change="validate" phx-submit="save" phx-target={@myself} class="space-y-4">
        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-semibold">Network Name <span class="text-error">*</span></span>
            <span class="label-text-alt">Display name for this network</span>
          </label>
          <input
            type="text"
            name="network[name]"
            placeholder="e.g., Home Network"
            class="input input-bordered w-full"
            required
          />
          <label class="label">
            <span class="label-text-alt text-base-content/60">1-16 characters</span>
          </label>
        </div>

        <div class="form-control w-full">
          <label class="label">
            <span class="label-text font-semibold">Thread Network Name <span class="text-error">*</span></span>
            <span class="label-text-alt">Name visible to Thread devices</span>
          </label>
          <input
            type="text"
            name="network[network_name]"
            placeholder="e.g., MyHome"
            class="input input-bordered w-full"
            required
          />
          <label class="label">
            <span class="label-text-alt text-base-content/60">1-16 characters, no spaces</span>
          </label>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-semibold">Channel</span>
              <span class="label-text-alt">802.15.4 channel</span>
            </label>
            <input
              type="number"
              name="network[channel]"
              placeholder="15"
              min="11"
              max="26"
              class="input input-bordered w-full"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/60">11-26 (default: 15)</span>
            </label>
          </div>

          <div class="form-control w-full">
            <label class="label">
              <span class="label-text font-semibold">PAN ID</span>
              <span class="label-text-alt">Personal Area Network ID</span>
            </label>
            <input
              type="number"
              name="network[pan_id]"
              placeholder="Auto-generated"
              min="0"
              max="65534"
              class="input input-bordered w-full"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/60">0-65534 (auto if empty)</span>
            </label>
          </div>
        </div>

        <div class="alert alert-info">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <div>
            <h4 class="font-bold">Security Credentials</h4>
            <div class="text-xs">Network keys and Extended PAN ID will be auto-generated securely</div>
          </div>
        </div>

        <div class="divider"></div>

        <div class="modal-action">
          <button type="button" phx-click="close" phx-target={@myself} class="btn btn-ghost">
            Cancel
          </button>
          <button type="submit" class="btn btn-primary gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
            </svg>
            Create Network
          </button>
        </div>
      </form>
    </div>
    """
  end
end
