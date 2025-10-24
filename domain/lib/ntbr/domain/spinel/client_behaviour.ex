# ==============================================================================
# File: domain/lib/ntbr/domain/spinel/client_behaviour.ex
# ==============================================================================

defmodule NTBR.Domain.Spinel.ClientBehaviour do
  @moduledoc """
  Behaviour definition for Spinel.Client.
  
  This defines the contract that any Spinel client implementation must follow.
  Used for mocking in tests with Mox.
  
  ## Usage in Tests
  
      # In test_helper.exs
      Mox.defmock(NTBR.Domain.Spinel.ClientMock, 
        for: NTBR.Domain.Spinel.ClientBehaviour)
      
      # In a test
      setup do
        Mox.stub_with(NTBR.Domain.Spinel.ClientMock, 
          NTBR.Domain.Spinel.ClientStub)
        :ok
      end
  """

  @doc "Start the Spinel client"
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc "Set the network key (16 bytes)"
  @callback set_network_key(binary()) :: :ok | {:error, term()}

  @doc "Set the PAN ID"
  @callback set_pan_id(non_neg_integer()) :: :ok | {:error, term()}

  @doc "Set the Extended PAN ID (8 bytes)"
  @callback set_extended_pan_id(binary()) :: :ok | {:error, term()}

  @doc "Set the channel (11-26)"
  @callback set_channel(11..26) :: :ok | {:error, term()}

  @doc "Set the network name"
  @callback set_network_name(String.t()) :: :ok | {:error, term()}

  @doc "Bring the network interface up"
  @callback interface_up() :: :ok | {:error, term()}

  @doc "Bring the network interface down"
  @callback interface_down() :: :ok | {:error, term()}

  @doc "Start Thread networking"
  @callback thread_start() :: :ok | {:error, term()}

  @doc "Stop Thread networking"
  @callback thread_stop() :: :ok | {:error, term()}

  @doc "Reset the RCP"
  @callback reset() :: :ok | {:error, term()}

  @doc "Get the current channel"
  @callback get_channel() :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "Get the current network role"
  @callback get_net_role() :: {:ok, atom()} | {:error, term()}

  @doc "Get the router table"
  @callback get_router_table() :: {:ok, list()} | {:error, term()}

  @doc "Get the child table"
  @callback get_child_table() :: {:ok, list()} | {:error, term()}

  @doc "Get NCP version"
  @callback get_ncp_version() :: {:ok, String.t()} | {:error, term()}

  @doc "Get NCP capabilities"
  @callback get_caps() :: {:ok, list()} | {:error, term()}

  @doc "Set a property value"
  @callback set_property(term(), binary()) :: :ok | {:error, term()}

  @doc "Get a property value"
  @callback get_property(term()) :: {:ok, binary()} | {:error, term()}
end

# ==============================================================================
# File: domain/lib/ntbr/domain/spinel/client_stub.ex
# ==============================================================================

defmodule NTBR.Domain.Spinel.ClientStub do
  @moduledoc """
  Stub implementation of Spinel.Client for testing.
  
  Provides reasonable default responses for all client operations.
  Use this as a base for test mocks or override specific functions with Mox.
  
  ## Usage
  
      # Use all defaults
      Mox.stub_with(ClientMock, NTBR.Domain.Spinel.ClientStub)
      
      # Override specific functions
      Mox.stub(ClientMock, :set_channel, fn _channel -> :ok end)
  """
  @behaviour NTBR.Domain.Spinel.ClientBehaviour

  @impl true
  def start_link(_opts), do: {:ok, self()}

  @impl true
  def set_network_key(_key), do: :ok

  @impl true
  def set_pan_id(_pan_id), do: :ok

  @impl true
  def set_extended_pan_id(_xpan), do: :ok

  @impl true
  def set_channel(_channel), do: :ok

  @impl true
  def set_network_name(_name), do: :ok

  @impl true
  def interface_up, do: :ok

  @impl true
  def interface_down, do: :ok

  @impl true
  def thread_start, do: :ok

  @impl true
  def thread_stop, do: :ok

  @impl true
  def reset, do: :ok

  @impl true
  def get_channel, do: {:ok, 15}

  @impl true
  def get_net_role, do: {:ok, :detached}

  @impl true
  def get_router_table, do: {:ok, []}

  @impl true
  def get_child_table, do: {:ok, []}

  @impl true
  def get_ncp_version, do: {:ok, "OPENTHREAD/1.0.0; RCP; Oct 16 2025"}

  @impl true
  def get_caps, do: {:ok, [:net, :mac, :config]}

  @impl true
  def set_property(_property, _value), do: :ok

  @impl true
  def get_property(_property), do: {:ok, <<>>}
end
