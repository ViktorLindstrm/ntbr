defmodule NTBR.Domain.Spinel.Resources.PropertyState do
  @moduledoc """
  Tracks the current state of Spinel properties on the RCP.
  
  This resource maintains a cache of property values retrieved from or set on
  the RCP device. It tracks when properties were last updated and allows
  querying properties by category, recency, or specific property ID.
  
  ## Features
  
  - Upsert support: create or update property state
  - Category-based filtering (phy, mac, net, thread, ipv6, etc.)
  - Timestamp tracking for staleness detection
  - Update counter for change frequency analysis
  - Raw binary value storage alongside parsed value
  
  ## Examples
  
      # Record a property value
      PropertyState.upsert!(%{
        property: :phy_chan,
        value: %{channel: 15},
        raw_value: <<15>>
      })
      
      # Query by property
      [state] = PropertyState.by_property!(:phy_chan)
      state.value  # => %{channel: 15}
      
      # Get all PHY properties
      phy_props = PropertyState.by_category!(:phy)
      
      # Check property age
      age = Ash.calculate!(state, :age_seconds)
      if age > 60, do: IO.puts("Property is stale!")
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [],
    primary_read_warning?: false

  alias NTBR.Domain.Spinel.Property

  attributes do
    uuid_primary_key :id

    attribute :property, :atom do
      allow_nil? false
      public? true
    end

    attribute :value, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :raw_value, :binary do
      allow_nil? true
      public? true
    end

    attribute :category, :atom do
      allow_nil? false
      public? true
    end

    attribute :update_count, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :last_updated_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :age_seconds, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          DateTime.diff(DateTime.utc_now(), record.last_updated_at, :second)
        end)
      end
    end

    calculate :is_stale, :boolean do
      argument :threshold_seconds, :integer do
        allow_nil? false
        default 60
      end

      calculation fn records, %{arguments: %{threshold_seconds: threshold}} ->
        now = DateTime.utc_now()
        
        Enum.map(records, fn record ->
          age = DateTime.diff(now, record.last_updated_at, :second)
          age > threshold
        end)
      end
    end

    calculate :description, :string do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          Property.description(record.property) || "Unknown property"
        end)
      end
    end
  end

  actions do
    defaults [:destroy]

    create :create do
      accept [:property, :value, :raw_value]
      
      change fn changeset, _context ->
        property = Ash.Changeset.get_attribute(changeset, :property)
        
        # Derive category from property
        category = if property, do: Property.category(property), else: :unknown
        
        changeset
        |> Ash.Changeset.change_attribute(:category, category)
        |> Ash.Changeset.change_attribute(:update_count, 1)
        |> Ash.Changeset.change_attribute(:last_updated_at, DateTime.utc_now())
      end
    end

    update :update do
      accept [:value, :raw_value]
      require_atomic? false
      
      change fn changeset, _context ->
        current_count = Ash.Changeset.get_attribute(changeset, :update_count) || 0
        
        changeset
        |> Ash.Changeset.change_attribute(:update_count, current_count + 1)
        |> Ash.Changeset.change_attribute(:last_updated_at, DateTime.utc_now())
      end
    end

    create :upsert do
      accept [:property, :value, :raw_value]
      #require_atomic? false
      
      upsert? true
      upsert_identity :unique_property
      
      change fn changeset, _context ->
        property = Ash.Changeset.get_attribute(changeset, :property)
        category = if property, do: Property.category(property), else: :unknown
        
        # Check if this is an update or create
        current_count = Ash.Changeset.get_attribute(changeset, :update_count) || 0
        new_count = if current_count > 0, do: current_count + 1, else: 1
        
        changeset
        |> Ash.Changeset.change_attribute(:category, category)
        |> Ash.Changeset.change_attribute(:update_count, new_count)
        |> Ash.Changeset.change_attribute(:last_updated_at, DateTime.utc_now())
      end
    end

    read :read do
      primary? true
      prepare build(sort: [last_updated_at: :desc])
    end

    read :by_property do
      argument :property, :atom do
        allow_nil? false
      end
      
      filter expr(property == ^arg(:property))
    end

    read :by_category do
      argument :category, :atom do
        allow_nil? false
      end
      
      filter expr(category == ^arg(:category))
      prepare build(sort: [property: :asc])
    end

    read :recent do
      argument :limit, :integer do
        allow_nil? false
        default 10
        constraints min: 1, max: 100
      end
      
      prepare build(
        sort: [last_updated_at: :desc],
        limit: arg(:limit)
      )
    end

    read :stale do
      argument :threshold_seconds, :integer do
        allow_nil? false
        default 300  # 5 minutes
      end
      
      filter expr(
        last_updated_at < ago(^arg(:threshold_seconds), :second)
      )
    end

    read :frequently_updated do
      argument :min_updates, :integer do
        allow_nil? false
        default 10
      end
      
      filter expr(update_count >= ^arg(:min_updates))
      prepare build(sort: [update_count: :desc])
    end
  end

  identities do
    identity :unique_property, [:property], 
      pre_check_with: NTBR.Domain
  end

  code_interface do
    define :create
    define :update
    define :upsert
    define :destroy
    define :read
    define :by_property, args: [:property]
    define :by_category, args: [:category]
    define :recent, args: [{:optional, :limit}]
    define :stale, args: [{:optional, :threshold_seconds}]
    define :frequently_updated, args: [{:optional, :min_updates}]
  end
end
