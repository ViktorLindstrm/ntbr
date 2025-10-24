defmodule Web.GraphQL.Schema do
  @moduledoc """
  GraphQL schema for NTBR Border Router API.
  
  Provides GraphQL access to Thread network state, RCP status,
  and Spinel frame inspection.
  
  ## Example Queries
  
  ```graphql
  query GetNetwork {
    getNetwork(id: "...") {
      name
      role
      channel
      isActive
      deviceCount
    }
  }
  
  query ListRecentFrames {
    listFrames(limit: 20) {
      sequence
      direction
      command
      property
      timestamp
      status
    }
  }
  ```
  
  ## Example Mutations
  
  ```graphql
  mutation FormNetwork {
    formNetwork(dataset: {
      name: "MyNetwork"
      panId: 4660
      channel: 15
      networkKey: "..."
    }) {
      id
      name
      role
    }
  }
  ```
  """
  
  use Absinthe.Schema
  
  import_types AshGraphql.Types
  
  # Import Ash resources into GraphQL schema
  use AshGraphql, domains: [Core.AshDomain]

  query do
    # Thread Network Queries
    field :get_network, :thread_network do
      arg :id, non_null(:id)
      resolve &resolve_network/3
    end
    
    field :list_networks, list_of(:thread_network) do
      resolve &resolve_networks/3
    end
    
    # RCP Status Queries
    field :rcp_status, :rcp_status do
      resolve &resolve_rcp_status/3
    end
    
    # Spinel Frame Queries
    field :list_frames, list_of(:spinel_frame) do
      arg :limit, :integer, default_value: 50
      arg :direction, :direction_enum
      arg :command, :command_enum
      resolve &resolve_frames/3
    end
    
    field :recent_frames, list_of(:spinel_frame) do
      arg :limit, :integer, default_value: 20
      resolve &resolve_recent_frames/3
    end
    
    field :frame_statistics, :frame_statistics do
      resolve &resolve_frame_stats/3
    end
  end

  mutation do
    # Thread Network Mutations
    field :form_network, :thread_network do
      arg :dataset, non_null(:network_dataset_input)
      resolve &resolve_form_network/3
    end
    
    field :attach_to_network, :thread_network do
      arg :dataset, non_null(:network_dataset_input)
      resolve &resolve_attach_network/3
    end
    
    field :update_network, :thread_network do
      arg :id, non_null(:id)
      arg :input, non_null(:network_update_input)
      resolve &resolve_update_network/3
    end
  end

  # Custom Types
  enum :direction_enum do
    value :inbound
    value :outbound
  end

  enum :command_enum do
    value :reset
    value :noop
    value :prop_value_get
    value :prop_value_set
    value :prop_value_insert
    value :prop_value_remove
    value :prop_value_is
    value :prop_value_inserted
    value :prop_value_removed
  end

  enum :role_enum do
    value :disabled
    value :detached
    value :child
    value :router
    value :leader
  end

  input_object :network_dataset_input do
    field :name, non_null(:string)
    field :pan_id, non_null(:integer)
    field :channel, non_null(:integer)
    field :network_key, :string
    field :extended_pan_id, :string
  end

  input_object :network_update_input do
    field :name, :string
    field :channel, :integer
  end

  object :frame_statistics do
    field :total, non_null(:integer)
    field :outbound, non_null(:integer)
    field :inbound, non_null(:integer)
    field :errors, non_null(:integer)
    field :error_rate, non_null(:float)
  end

  # Resolvers
  defp resolve_network(_parent, %{id: id}, _resolution) do
    case Core.Resources.ThreadNetwork.read(id) do
      {:ok, network} -> {:ok, network}
      {:error, _} -> {:error, "Network not found"}
    end
  end

  defp resolve_networks(_parent, _args, _resolution) do
    {:ok, Core.Resources.ThreadNetwork.read_all!()}
  end

  defp resolve_rcp_status(_parent, _args, _resolution) do
    case Core.Resources.RCPStatus.current() do
      {:ok, status} -> {:ok, status}
      {:error, _} -> {:error, "RCP status not available"}
    end
  end

  defp resolve_frames(_parent, args, _resolution) do
    limit = Map.get(args, :limit, 50)
    direction = Map.get(args, :direction)
    command = Map.get(args, :command)
    
    frames = 
      cond do
        command != nil ->
          Core.Resources.SpinelFrame.by_command!(command: command)
        
        direction != nil ->
          Core.Resources.SpinelFrame.recent!(limit: limit, direction: direction)
        
        true ->
          Core.Resources.SpinelFrame.recent!(limit: limit, direction: nil)
      end
    
    {:ok, frames}
  end

  defp resolve_recent_frames(_parent, args, _resolution) do
    limit = Map.get(args, :limit, 20)
    {:ok, Core.Resources.SpinelFrame.recent!(limit: limit, direction: nil)}
  end

  defp resolve_frame_stats(_parent, _args, _resolution) do
    # In real implementation, would calculate from actual frames
    stats = %{
      total: 0,
      outbound: 0,
      inbound: 0,
      errors: 0,
      error_rate: 0.0
    }
    {:ok, stats}
  end

  defp resolve_form_network(_parent, %{dataset: dataset}, _resolution) do
    case Core.Resources.ThreadNetwork.form_network!(dataset: dataset) do
      {:ok, network} -> {:ok, network}
      {:error, error} -> {:error, inspect(error)}
    end
  end

  defp resolve_attach_network(_parent, %{dataset: dataset}, _resolution) do
    case Core.Resources.ThreadNetwork.attach!(dataset: dataset) do
      {:ok, network} -> {:ok, network}
      {:error, error} -> {:error, inspect(error)}
    end
  end

  defp resolve_update_network(_parent, %{id: id, input: input}, _resolution) do
    case Core.Resources.ThreadNetwork.read(id) do
      {:ok, network} ->
        case Core.Resources.ThreadNetwork.update(network, input) do
          {:ok, updated} -> {:ok, updated}
          {:error, error} -> {:error, inspect(error)}
        end
      {:error, _} ->
        {:error, "Network not found"}
    end
  end
end
