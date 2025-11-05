# PropCheck configuration for property-based tests
# Note: PropCheck 1.5 starts automatically - no need to call PropCheck.start()
Application.put_env(:propcheck, :verbose, true)
Application.put_env(:propcheck, :numtests, System.get_env("PROPCHECK_NUMTESTS", "100") |> String.to_integer())
Application.put_env(:propcheck, :search_steps, System.get_env("PROPCHECK_SEARCH_STEPS", "10000") |> String.to_integer())

# Define Mox mocks for testing
Mox.defmock(NTBR.Domain.Spinel.ClientMock, for: NTBR.Domain.Spinel.ClientBehaviour)

# Start test infrastructure
{:ok, _} = Application.ensure_all_started(:phoenix_pubsub)

# Ensure the domain application is started (which starts PubSub)
# If already started, this is a no-op
case Application.ensure_all_started(:ntbr_domain) do
  {:ok, _} -> :ok
  {:error, {:already_started, :ntbr_domain}} -> :ok
  {:error, reason} ->
    # If app fails to start, continue anyway but log warning
    IO.puts("Warning: Could not start :ntbr_domain application: #{inspect(reason)}")
    # Start PubSub directly as fallback
    case Phoenix.PubSub.start_link(name: NTBR.PubSub) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
end

# Start a mock Spinel Client process for integration tests that expect it to exist
# This prevents :noproc errors when tests call Client functions directly
defmodule NTBR.Domain.Test.MockSpinelClient do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: NTBR.Domain.Spinel.Client)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  # Handle all Client calls with stub responses
  @impl true
  def handle_call({:set_property, _property, _value}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_property, property}, _from, state) do
    response = case property do
      :phy_chan -> {:ok, <<15>>}
      :net_role -> {:ok, <<0>>}  # disabled
      :ncp_version -> {:ok, "OPENTHREAD/1.0.0"}
      :caps -> {:ok, [:net, :mac, :config]}
      :thread_router_table -> {:ok, <<>>}
      :thread_child_table -> {:ok, <<>>}
      _ -> {:ok, <<>>}
    end
    {:reply, response, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end
end

# Start the mock client
case NTBR.Domain.Test.MockSpinelClient.start_link() do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
end

ExUnit.start()

IO.puts("\n=== Domain Test Configuration ===")
IO.puts("PropCheck iterations: #{Application.get_env(:propcheck, :numtests)}")
IO.puts("Search steps: #{Application.get_env(:propcheck, :search_steps)}")
IO.puts("Mock Spinel Client: Started")
IO.puts("PubSub: Started")
IO.puts("=================================\n")
