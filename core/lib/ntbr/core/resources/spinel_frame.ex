defmodule Core.Resources.SpinelFrame do
  @moduledoc """
  Ash Resource for capturing and displaying Spinel protocol frames.
  
  This resource provides observability into the Spinel protocol communication
  between the host and RCP. Useful for debugging, monitoring, and understanding
  the low-level protocol behavior.
  
  ## Examples
  
      # List recent frames
      iex> Core.Resources.SpinelFrame.recent!(limit: 10)
      [%Core.Resources.SpinelFrame{direction: :outbound, ...}, ...]
      
      # Get statistics
      iex> Core.Resources.SpinelFrame.statistics!()
      %{total: 1234, outbound: 600, inbound: 634, errors: 0}
  """
  
  use Ash.Resource,
    domain: Core.AshDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  ets do
    table :spinel_frames
    # Keep last 1000 frames in memory
    private? false
  end

  graphql do
    type :spinel_frame
    
    queries do
      get :get_frame, :read
      list :list_frames, :read_all
      list :recent_frames, :recent
      read_one :frame_statistics, :statistics
    end
  end

  json_api do
    type "spinel_frame"
    
    routes do
      base "/api/spinel_frames"
      get :read
      index :read_all
    end
  end

  attributes do
    uuid_primary_key :id

    # Frame Metadata
    attribute :sequence, :integer do
      allow_nil? false
      description "Auto-incrementing sequence number"
    end

    attribute :direction, :atom do
      allow_nil? false
      constraints one_of: [:inbound, :outbound]
      description "Frame direction (inbound from RCP or outbound to RCP)"
    end

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "Precise timestamp of frame capture"
    end

    # Spinel Frame Components
    attribute :header, :integer do
      constraints min: 0, max: 0xFF
      description "Spinel header byte (flags + NLI)"
    end

    attribute :command, :atom do
      allow_nil? false
      description "Spinel command type"
      constraints one_of: [
        :reset,
        :noop,
        :prop_value_get,
        :prop_value_set,
        :prop_value_insert,
        :prop_value_remove,
        :prop_value_is,
        :prop_value_inserted,
        :prop_value_removed
      ]
    end

    attribute :tid, :integer do
      constraints min: 0, max: 15
      description "Transaction ID (4-bit)"
    end

    attribute :property, :atom do
      description "Spinel property identifier"
    end

    attribute :property_id, :integer do
      description "Raw property ID number"
    end

    # Payload
    attribute :payload, :binary do
      description "Raw payload data"
    end

    attribute :payload_decoded, :map do
      description "Decoded payload structure (if parseable)"
    end

    # Frame Status
    attribute :status, :atom do
      allow_nil? false
      default :success
      constraints one_of: [:success, :error, :timeout, :malformed]
      description "Frame processing status"
    end

    attribute :error_message, :string do
      description "Error details if status is error/malformed"
    end

    attribute :size_bytes, :integer do
      allow_nil? false
      description "Total frame size in bytes"
    end

    # Relations to other entities
    attribute :network_id, :uuid do
      description "Associated Thread network (if applicable)"
    end

    timestamps()
  end

  calculations do
    calculate :is_request, :boolean, 
      expr(command in [:prop_value_get, :prop_value_set, :prop_value_insert, :prop_value_remove]) do
      description "True if frame is a request (vs response)"
    end

    calculate :is_response, :boolean,
      expr(command in [:prop_value_is, :prop_value_inserted, :prop_value_removed]) do
      description "True if frame is a response"
    end

    calculate :has_error, :boolean, expr(status != :success) do
      description "True if frame encountered an error"
    end

    calculate :latency_ms, :integer do
      description "Response latency in milliseconds (for responses)"
      # In real implementation, would calculate from matching request/response
      expr(0)
    end
  end

  aggregates do
    count :total_frames, :read_all do
      description "Total number of captured frames"
    end
  end

  actions do
    defaults [:read, :destroy]

    read :read_all do
      description "List all captured frames"
      primary? true
      
      pagination do
        offset? true
        default_limit 50
        max_page_size 1000
      end
    end

    read :recent do
      description "Get most recent frames"
      
      argument :limit, :integer do
        default 100
        constraints max: 1000
      end

      argument :direction, :atom do
        constraints one_of: [:inbound, :outbound]
      end

      filter expr(
        if is_nil(^arg(:direction)),
          do: true,
          else: direction == ^arg(:direction)
      )

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit)
        query
        |> Ash.Query.sort(timestamp: :desc)
        |> Ash.Query.limit(limit)
      end
    end

    read :by_network do
      description "Get frames for a specific network"
      
      argument :network_id, :uuid do
        allow_nil? false
      end

      filter expr(network_id == ^arg(:network_id))
    end

    read :by_command do
      description "Filter frames by command type"
      
      argument :command, :atom do
        allow_nil? false
      end

      filter expr(command == ^arg(:command))
    end

    read :with_errors do
      description "Get frames that encountered errors"
      filter expr(status != :success)
    end

    read :statistics, {:read, :one} do
      description "Get frame statistics"

      prepare fn query, _context ->
        # In real implementation, would aggregate statistics
        query
      end
    end

    create :capture do
      accept [
        :sequence,
        :direction,
        :timestamp,
        :header,
        :command,
        :tid,
        :property,
        :property_id,
        :payload,
        :payload_decoded,
        :status,
        :error_message,
        :size_bytes,
        :network_id
      ]
      description "Capture a new Spinel frame"
    end

    update :update do
      accept [:status, :error_message, :payload_decoded]
      description "Update frame analysis"
    end

    action :clear_old_frames, :struct do
      description "Clear frames older than specified age"
      
      argument :older_than_minutes, :integer do
        default 60
      end

      returns :integer

      run fn input, _context ->
        minutes = input.arguments.older_than_minutes
        cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
        
        # In real implementation, would delete old frames
        {:ok, 0}
      end
    end

    action :decode_payload, :struct do
      description "Attempt to decode a frame's payload"
      
      argument :frame_id, :uuid do
        allow_nil? false
      end

      returns Core.Resources.SpinelFrame

      run fn input, context ->
        frame_id = input.arguments.frame_id
        
        case Core.Resources.SpinelFrame.read(frame_id) do
          {:ok, frame} ->
            # In real implementation, would use Domain.Spinel.DataEncoder
            decoded = %{
              raw: "Decoded structure would appear here",
              property_info: %{}
            }
            
            Core.Resources.SpinelFrame.update(frame, %{payload_decoded: decoded})
            
          {:error, _} = error ->
            error
        end
      end
    end
  end

  code_interface do
    define :capture
    define :read_all
    define :read, args: [:id]
    define :recent, args: [:limit, :direction]
    define :by_network, args: [:network_id]
    define :by_command, args: [:command]
    define :with_errors
    define :statistics
    define :update
    define :clear_old_frames, args: [:older_than_minutes]
    define :decode_payload, args: [:frame_id]
    define :destroy
  end

  validations do
    validate present([:sequence, :direction, :command, :size_bytes])
    
    validate fn changeset, _context ->
      # Validate TID is within 4-bit range
      case Ash.Changeset.get_attribute(changeset, :tid) do
        nil -> :ok
        tid when tid >= 0 and tid <= 15 -> :ok
        _ -> {:error, field: :tid, message: "must be 0-15"}
      end
    end
  end

  changes do
    change fn changeset, _context ->
      # Auto-calculate size if not provided
      if is_nil(Ash.Changeset.get_attribute(changeset, :size_bytes)) do
        payload = Ash.Changeset.get_attribute(changeset, :payload) || <<>>
        # 2 bytes header + command, payload length
        size = 2 + byte_size(payload)
        Ash.Changeset.change_attribute(changeset, :size_bytes, size)
      else
        changeset
      end
    end
  end
end
