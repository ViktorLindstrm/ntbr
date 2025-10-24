defmodule Core.Resources.ThreadNetwork do
  @moduledoc """
  Ash Resource representing the Thread network state.
  
  This resource tracks the current state of the Thread network including
  network parameters, role, and topology information. Uses ETS for runtime
  state management with real-time updates from the RCP.
  
  ## Examples
  
      # Read current network state
      iex> Core.Resources.ThreadNetwork.read!()
      %Core.Resources.ThreadNetwork{
        name: "MyThreadNetwork",
        role: :leader,
        channel: 15,
        ...
      }
      
      # Form a new network
      iex> dataset = %{
      ...>   name: "MyNetwork",
      ...>   pan_id: 0x1234,
      ...>   channel: 15,
      ...>   network_key: <<...>>
      ...> }
      iex> Core.Resources.ThreadNetwork.form_network!(dataset)
  """
  
  use Ash.Resource,
    domain: Core.AshDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  # ETS table for runtime state
  ets do
    table :thread_network_state
  end

  # GraphQL configuration
  graphql do
    type :thread_network
    
    queries do
      get :get_network, :read
      list :list_networks, :read_all
    end
    
    mutations do
      create :form_network, :form_network
      update :update_network, :update
      create :attach_network, :attach
    end
  end

  # JSON:API configuration
  json_api do
    type "thread_network"
    
    routes do
      base "/api/thread_networks"
      get :read
      index :read_all
      post :form
      patch :update
    end
  end

  attributes do
    uuid_primary_key :id

    # Network Identity
    attribute :name, :string do
      allow_nil? false
      constraints max_length: 16
      description "Thread network name (max 16 chars)"
    end

    attribute :pan_id, :integer do
      constraints min: 0, max: 0xFFFF
      description "PAN ID (0x0000-0xFFFF)"
    end

    attribute :extended_pan_id, :binary do
      constraints max_length: 8, min_length: 8
      description "Extended PAN ID (8 bytes)"
    end

    attribute :channel, :integer do
      constraints min: 11, max: 26
      description "IEEE 802.15.4 channel (11-26)"
    end

    attribute :network_key, :binary do
      sensitive? true
      constraints max_length: 16, min_length: 16
      description "Thread network master key (16 bytes)"
    end

    # Network State
    attribute :role, :atom do
      allow_nil? false
      default :disabled
      constraints one_of: [:disabled, :detached, :child, :router, :leader]
      description "Current device role in Thread network"
    end

    attribute :rloc16, :integer do
      constraints min: 0, max: 0xFFFF
      description "Router/Child location (RLOC16)"
    end

    attribute :partition_id, :integer do
      description "Current partition ID"
    end

    # Connection State
    attribute :state, :atom do
      allow_nil? false
      default :offline
      constraints one_of: [:offline, :joining, :attached, :active]
      description "Overall network connection state"
    end

    attribute :link_quality, :integer do
      constraints min: 0, max: 3
      description "Link quality indicator (0-3)"
    end

    # Topology Information
    attribute :child_count, :integer do
      default 0
      constraints min: 0
      description "Number of child devices"
    end

    attribute :router_count, :integer do
      default 0
      constraints min: 0
      description "Number of routers in partition"
    end

    attribute :leader_router_id, :integer do
      constraints min: 0, max: 0x3F
      description "Leader router ID (6-bit)"
    end

    attribute :network_data_version, :integer do
      default 0
      description "Network data version number"
    end

    timestamps()
  end

  calculations do
    calculate :is_leader, :boolean, expr(role == :leader) do
      description "True if this device is the Thread leader"
    end

    calculate :is_router, :boolean, expr(role == :router) do
      description "True if this device is a router"
    end

    calculate :is_active, :boolean, expr(role in [:child, :router, :leader]) do
      description "True if actively participating in network"
    end

    calculate :is_commissioner, :boolean, expr(role == :leader) do
      description "True if device can commission others (typically leader)"
    end

    calculate :device_count, :integer, expr(child_count + router_count) do
      description "Total number of devices in network"
    end
  end

  actions do
    defaults [:read, :destroy]

    read :read_all do
      description "List all network configurations"
      primary? true
    end

    create :create do
      accept [
        :name,
        :pan_id,
        :extended_pan_id,
        :channel,
        :network_key,
        :role,
        :state
      ]
      description "Create a new network configuration"
    end

    update :update do
      accept [
        :name,
        :pan_id,
        :channel,
        :role,
        :rloc16,
        :partition_id,
        :state,
        :link_quality,
        :child_count,
        :router_count,
        :leader_router_id,
        :network_data_version
      ]
      description "Update network state"
      primary? true
    end

    update :update_state do
      accept [:role, :state, :rloc16, :partition_id]
      description "Quick update of core network state"
    end

    update :update_topology do
      accept [:child_count, :router_count, :leader_router_id, :network_data_version]
      description "Update topology information"
    end

    action :form_network, :struct do
      description "Form a new Thread network with the given dataset"
      
      argument :dataset, :map do
        allow_nil? false
        description "Thread operational dataset"
      end

      returns Core.Resources.ThreadNetwork

      run fn input, _context ->
        dataset = input.arguments.dataset
        
        # In real implementation, this would call Core.NetworkManager.form_network/1
        # For now, create the resource
        {:ok, network} = Core.Resources.ThreadNetwork.create(%{
          name: dataset.name,
          pan_id: dataset.pan_id,
          channel: dataset.channel,
          extended_pan_id: dataset.extended_pan_id,
          network_key: dataset.network_key,
          role: :leader,
          state: :active
        })
        
        {:ok, network}
      end
    end

    action :attach, :struct do
      description "Attach to an existing Thread network"
      
      argument :dataset, :map do
        allow_nil? false
        description "Thread operational dataset of network to join"
      end

      returns Core.Resources.ThreadNetwork

      run fn input, _context ->
        dataset = input.arguments.dataset
        
        # In real implementation, this would call Core.NetworkManager.attach/1
        {:ok, network} = Core.Resources.ThreadNetwork.create(%{
          name: dataset.name,
          pan_id: dataset.pan_id,
          channel: dataset.channel,
          extended_pan_id: dataset.extended_pan_id,
          network_key: dataset.network_key,
          role: :child,
          state: :joining
        })
        
        {:ok, network}
      end
    end
  end

  # Code interface for programmatic access
  code_interface do
    define :create
    define :read_all
    define :read, args: [:id]
    define :update
    define :update_state
    define :update_topology
    define :form_network, args: [:dataset]
    define :attach, args: [:dataset]
    define :destroy
  end

  # Validations
  validations do
    validate present([:name, :role, :state])
    
    validate fn changeset, _context ->
      # Ensure network_key is present for active networks
      if Ash.Changeset.get_attribute(changeset, :state) in [:active, :attached] do
        if is_nil(Ash.Changeset.get_attribute(changeset, :network_key)) do
          {:error, field: :network_key, message: "required for active networks"}
        else
          :ok
        end
      else
        :ok
      end
    end
  end

  # Changes (hooks)
  changes do
    change fn changeset, _context ->
      # Auto-generate extended_pan_id if not provided
      if is_nil(Ash.Changeset.get_attribute(changeset, :extended_pan_id)) do
        Ash.Changeset.change_attribute(changeset, :extended_pan_id, :crypto.strong_rand_bytes(8))
      else
        changeset
      end
    end
  end
end
