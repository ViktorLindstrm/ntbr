defmodule NTBR.Domain.Spinel.Resources.CommandLog do
  @moduledoc """
  Audit trail for all Spinel commands sent to and received from the RCP.
  
  This resource tracks every command interaction with the RCP device, including
  timing, success/failure status, and response data. It's essential for:
  
  - Debugging communication issues
  - Performance monitoring
  - Security auditing
  - Analyzing failure patterns
  - Optimizing command sequences
  
  ## Features
  
  - Complete command history
  - Request/response correlation via TID
  - Duration tracking
  - Status tracking (pending, success, error, timeout)
  - Error message capture
  - Direction tracking (outgoing/incoming)
  
  ## Examples
  
      # Log an outgoing command
      {:ok, log} = CommandLog.create(%{
        command: :prop_value_set,
        property: :phy_chan,
        direction: :outgoing,
        tid: 5,
        payload: <<15>>,
        status: :pending
      })
      
      # Mark as successful with response
      CommandLog.mark_success!(log, %{
        response_payload: <<15>>
      })
      
      # Query failed commands
      failed = CommandLog.failed!()
      Enum.each(failed, fn log ->
        IO.puts("Failed: #\{log.command\} - #\{log.error_message\}")
      end)
      
      # Analyze slow commands
      recent = CommandLog.recent!(limit: 100)
      slow = Enum.filter(recent, fn log ->
        [duration] = Ash.calculate!(log, :duration_ms)
        duration && duration > 1000  # > 1 second
      end)
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  alias NTBR.Domain.Spinel.{Command, Property}

  attributes do
    uuid_primary_key :id

    attribute :command, :atom do
      allow_nil? false
      public? true
    end

    attribute :property, :atom do
      allow_nil? true
      public? true
    end

    attribute :tid, :integer do
      allow_nil? false
      constraints min: 0, max: 15
      public? true
    end

    attribute :direction, :atom do
      allow_nil? false
      constraints one_of: [:outgoing, :incoming]
      default :outgoing
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :success, :error, :timeout]
      public? true
    end

    attribute :payload, :binary do
      allow_nil? true
      public? true
    end

    attribute :response_payload, :binary do
      allow_nil? true
      public? true
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
    end

    attribute :sent_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :duration_ms, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          if record.completed_at do
            DateTime.diff(record.completed_at, record.sent_at, :millisecond)
          else
            nil
          end
        end)
      end
    end

    calculate :is_request, :boolean do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          Command.request?(record.command)
        end)
      end
    end

    calculate :is_response, :boolean do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          Command.response?(record.command)
        end)
      end
    end

    calculate :command_description, :string do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          base = "#{record.command}"
          
          property_desc = if record.property do
            prop_desc = Property.description(record.property)
            " (#{record.property}: #{prop_desc})"
          else
            ""
          end
          
          base <> property_desc
        end)
      end
    end
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :mark_success do
        from :pending
        to :success
      end

      transition :mark_error do
        from :pending
        to :error
      end

      transition :mark_timeout do
        from :pending
        to :timeout
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:command, :property, :tid, :direction, :payload, :status]
      
      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :sent_at, DateTime.utc_now())
      end
    end

    update :mark_success do
      accept [:response_payload]
      require_atomic? false
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end

    update :mark_error do
      accept [:error_message, :response_payload]
      require_atomic? false
      
      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end

    update :mark_timeout do
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, "Command timed out")
      end
    end

    read :failed do
      filter expr(status in [:error, :timeout])
      prepare build(sort: [sent_at: :desc])
    end

    read :pending do
      filter expr(status == :pending)
      prepare build(sort: [sent_at: :asc])
    end

    read :successful do
      filter expr(status == :success)
      prepare build(sort: [sent_at: :desc])
    end

    read :by_command do
      argument :command, :atom do
        allow_nil? false
      end
      
      filter expr(command == ^arg(:command))
      prepare build(sort: [sent_at: :desc])
    end

    read :by_property do
      argument :property, :atom do
        allow_nil? false
      end
      
      filter expr(property == ^arg(:property))
      prepare build(sort: [sent_at: :desc])
    end

    read :by_tid do
      argument :tid, :integer do
        allow_nil? false
        constraints min: 0, max: 15
      end
      
      filter expr(tid == ^arg(:tid))
    end

    read :recent do
      argument :limit, :integer do
        allow_nil? false
        default 50
        constraints min: 1, max: 1000
      end
      
      prepare build(
        sort: [sent_at: :desc],
        limit: arg(:limit)
      )
    end

    read :slow_commands do
      argument :threshold_ms, :integer do
        allow_nil? false
        default 1000  # 1 second
      end
      
      # Return completed commands, caller should filter by duration
      filter expr(status in [:success, :error, :timeout])
      prepare build(sort: [sent_at: :desc])
    end

    read :timeouts do
      filter expr(status == :timeout)
      prepare build(sort: [sent_at: :desc])
    end

    read :in_time_range do
      argument :start_time, :utc_datetime_usec do
        allow_nil? false
      end
      
      argument :end_time, :utc_datetime_usec do
        allow_nil? false
      end
      
      filter expr(
        sent_at >= ^arg(:start_time) and
        sent_at <= ^arg(:end_time)
      )
      prepare build(sort: [sent_at: :asc])
    end
  end

  code_interface do
    define :create
    define :mark_success, args: [{:optional, :response_payload}]
    define :mark_error, args: [:error_message, {:optional, :response_payload}]
    define :mark_timeout
    define :destroy
    define :read
    define :failed
    define :pending
    define :successful
    define :by_command, args: [:command]
    define :by_property, args: [:property]
    define :by_tid, args: [:tid]
    define :recent, args: [{:optional, :limit}]
    define :slow_commands, args: [{:optional, :threshold_ms}]
    define :timeouts
    define :in_time_range, args: [:start_time, :end_time]
  end
end
