defmodule Web.Router do
  use Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # GraphQL API
  pipeline :graphql do
    plug :accepts, ["json"]
    plug AshGraphql.Plug
  end

  scope "/", Web do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/spinel", SpinelLive, :index
    live "/spinel/:id", SpinelLive, :show
    live "/network", NetworkLive, :index
  end

  # JSON:API Routes
  scope "/api" do
    pipe_through :api
    
    forward "/", AshJsonApi.Router,
      domain: Core.AshDomain,
      json_schema: "/json_schema",
      open_api: "/open_api"
  end

  # GraphQL API
  scope "/graphql" do
    pipe_through :graphql
    
    forward "/", Absinthe.Plug,
      schema: Web.GraphQL.Schema,
      interface: :playground
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Web.Telemetry
    end
  end
end
