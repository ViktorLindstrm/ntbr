defmodule Core.Resources.RCPStatus do
  @moduledoc """
  Ash Resource for RCP (Radio Co-Processor) connection status and health.
  
  Tracks the connection state, statistics, and health of the ESP32-C6 RCP
  device communicating via Spinel protocol.
  """
  
  use Ash.Resource,
    domain: Core.AshDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  ets do
    table :rcp_status
  end

  graphql do
    type :rcp_status
    
    queries do
      get :get_status, :read
      read_one :current_status, :current
    end
    
    mutations do
      update :update_status, :update
    end
  end

  json_api do
    type "rcp_status"
    
    routes do
      base "/api/rcp_status"
      get :read
      index :current
    end
  end

  attributes do
    uuid_primary_key :id

    # Connection State
    attribute :connected, :boolean do
      allow_nil? false
      default false
      description "True if RCP is connected and responsive"
    end

    attribute :port, :string do
      description "Serial port path (e.g., /dev/ttyUSB0)"
    end

    attribute :baudrate, :integer do
      default 115200
      description "Serial port baud rate"
    end

    attribute :connection_state, :atom do
      allow_nil? false
      default :disconnected
      constraints one_of: [:disconnected, :connecting, :connected, :error]
      description "Detailed connection state"
    end

    # RCP Information
    attribute :protocol_version, :string do
      description "Spinel protocol version (e.g., '4.0')"
    end

    attribute :ncp_version, :string do
      description "NCP/RCP firmware version"
    end

    attribute :capabilities, {:array, :atom} do
      default []
      description "RCP capabilities list"
    end

    attribute :hardware_address, :binary do
      constraints max_length: 8
      description "IEEE 802.15.4 EUI-64 address"
    end

    # Statistics
    attribute :frames_sent, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Total frames sent to RCP"
    end

    attribute :frames_received, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Total frames received from RCP"
    end

    attribute :frames_errored, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Total frames with errors"
    end

    attribute :bytes_sent, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Total bytes sent"
    end

    attribute :bytes_received, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Total bytes received"
    end

    # Health Monitoring
    attribute :last_seen_at, :utc_datetime_usec do
      description "Last time RCP responded"
    end

    attribute :uptime_seconds, :integer do
      default 0
      constraints min: 0
      description "RCP uptime in seconds"
    end

    attribute :reset_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Number of RCP resets"
    end

    attribute :last_error, :string do
      description "Last error message"
    end

    attribute :last_error_at, :utc_datetime_usec do
      description "Timestamp of last error"
    end

    # Performance Metrics
    attribute :average_response_time_ms, :float do
      description "Average response time in milliseconds"
    end

    attribute :pending_requests, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      description "Number of pending requests awaiting response"
    end

    timestamps()
  end

  calculations do
    calculate :is_healthy, :boolean, 
      expr(connected and is_nil(last_error)) do
      description "True if RCP is connected and has no recent errors"
    end

    calculate :error_rate, :float do
      description "Frame error rate as percentage"
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          total = record.frames_sent + record.frames_received
          if total > 0 do
            (record.frames_errored / total) * 100.0
          else
            0.0
          end
        end)
      end
    end

    calculate :uptime_hours, :float, expr(uptime_seconds / 3600.0) do
      description "Uptime in hours"
    end

    calculate :seconds_since_last_seen, :integer do
      description "Seconds since last RCP response"
      calculation fn records, _context ->
        now = DateTime.utc_now()
        Enum.map(records, fn record ->
          if record.last_seen_at do
            DateTime.diff(now, record.last_seen_at, :second)
          else
            nil
          end
        end)
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    read :current do
      description "Get current RCP status"
      primary? true
      
      prepare fn query, _context ->
        # Return the single RCP status record
        query
        |> Ash.Query.limit(1)
      end
    end

    read :history do
      description "Get connection history"
      
      argument :hours, :integer do
        default 24
        constraints min: 1, max: 168
      end

      # In real implementation, would filter by time range
    end

    create :initialize do
      accept [:port, :baudrate]
      description "Initialize RCP status tracking"
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:connection_state, :disconnected)
        |> Ash.Changeset.change_attribute(:connected, false)
      end
    end

    update :update do
      accept [
        :connected,
        :port,
        :baudrate,
        :connection_state,
        :protocol_version,
        :ncp_version,
        :capabilities,
        :hardware_address,
        :frames_sent,
        :frames_received,
        :frames_errored,
        :bytes_sent,
        :bytes_received,
        :last_seen_at,
        :uptime_seconds,
        :reset_count,
        :last_error,
        :last_error_at,
        :average_response_time_ms,
        :pending_requests
      ]
      description "Update RCP status"
      primary? true
    end

    update :mark_connected do
      accept [:protocol_version, :ncp_version, :capabilities, :hardware_address]
      description "Mark RCP as connected"
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:connected, true)
        |> Ash.Changeset.change_attribute(:connection_state, :connected)
        |> Ash.Changeset.change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :mark_disconnected do
      accept [:last_error]
      description "Mark RCP as disconnected"
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:connected, false)
        |> Ash.Changeset.change_attribute(:connection_state, :disconnected)
        |> Ash.Changeset.change_attribute(:last_error_at, DateTime.utc_now())
      end
    end

    update :increment_sent do
      description "Increment frames sent counter"
      
      argument :bytes, :integer do
        allow_nil? false
      end

      change fn changeset, _context ->
        bytes = Ash.Changeset.get_argument(changeset, :bytes)
        current_frames = Ash.Changeset.get_attribute(changeset, :frames_sent) || 0
        current_bytes = Ash.Changeset.get_attribute(changeset, :bytes_sent) || 0
        
        changeset
        |> Ash.Changeset.change_attribute(:frames_sent, current_frames + 1)
        |> Ash.Changeset.change_attribute(:bytes_sent, current_bytes + bytes)
        |> Ash.Changeset.change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :increment_received do
      description "Increment frames received counter"
      
      argument :bytes, :integer do
        allow_nil? false
      end

      change fn changeset, _context ->
        bytes = Ash.Changeset.get_argument(changeset, :bytes)
        current_frames = Ash.Changeset.get_attribute(changeset, :frames_received) || 0
        current_bytes = Ash.Changeset.get_attribute(changeset, :bytes_received) || 0
        
        changeset
        |> Ash.Changeset.change_attribute(:frames_received, current_frames + 1)
        |> Ash.Changeset.change_attribute(:bytes_received, current_bytes + bytes)
        |> Ash.Changeset.change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end

    update :record_error do
      description "Record a frame error"
      
      argument :error_message, :string do
        allow_nil? false
      end

      change fn changeset, _context ->
        error_msg = Ash.Changeset.get_argument(changeset, :error_message)
        current_errors = Ash.Changeset.get_attribute(changeset, :frames_errored) || 0
        
        changeset
        |> Ash.Changeset.change_attribute(:frames_errored, current_errors + 1)
        |> Ash.Changeset.change_attribute(:last_error, error_msg)
        |> Ash.Changeset.change_attribute(:last_error_at, DateTime.utc_now())
      end
    end

    update :reset do
      description "Record an RCP reset"
      
      change fn changeset, _context ->
        current_resets = Ash.Changeset.get_attribute(changeset, :reset_count) || 0
        
        changeset
        |> Ash.Changeset.change_attribute(:reset_count, current_resets + 1)
        |> Ash.Changeset.change_attribute(:uptime_seconds, 0)
        |> Ash.Changeset.change_attribute(:last_seen_at, DateTime.utc_now())
      end
    end
  end

  code_interface do
    define :initialize, args: [:port, :baudrate]
    define :current
    define :read, args: [:id]
    define :history, args: [:hours]
    define :update
    define :mark_connected, args: [:protocol_version, :ncp_version, :capabilities, :hardware_address]
    define :mark_disconnected, args: [:last_error]
    define :increment_sent, args: [:bytes]
    define :increment_received, args: [:bytes]
    define :record_error, args: [:error_message]
    define :reset
    define :destroy
  end

  validations do
    validate present([:connected, :connection_state])
    
    validate fn changeset, _context ->
      # Validate port format if provided
      case Ash.Changeset.get_attribute(changeset, :port) do
        nil -> :ok
        port when is_binary(port) ->
          if String.starts_with?(port, "/dev/") do
            :ok
          else
            {:error, field: :port, message: "must be a device path like /dev/ttyUSB0"}
          end
        _ -> :ok
      end
    end
  end
end