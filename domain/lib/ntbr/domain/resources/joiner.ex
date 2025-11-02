defmodule NTBR.Domain.Resources.Joiner do
  @moduledoc """
  Represents a device attempting to join the Thread network.

  Manages the commissioning process for new devices joining the mesh.
  Supports both specific (EUI-64) joiners and wildcard joiners that
  allow any device with the correct PSKD to join.

  ## State Machine

  The joiner transitions through these states:

  ```
  :pending ──start──> :joining ──complete──> :joined
      │                  │
      │                  └──fail──> :failed
      │
      └──expire──> :expired
  ```

  ## Features

  - PSKD (Pre-Shared Key for Device) management
  - Automatic timeout and expiration
  - Vendor information tracking
  - State machine for joining process
  - Links to Device once successfully joined

  ## Examples

      # Create a joiner for a specific device
      {:ok, joiner} = Joiner.create(%{
        network_id: network.id,
        eui64: <<0x00, 0x12, 0x4b, 0x00, 0x14, 0x32, 0x16, 0x78>>,
        pskd: "J01NME",
        timeout: 120
      })
      
      # Start the joining process
      {:ok, joiner} = Joiner.start(joiner)
      
      # Complete when device successfully joins
      {:ok, joiner} = Joiner.complete(joiner)
      
      # Or handle failure
      {:ok, joiner} = Joiner.fail(joiner)
      
      # Create a wildcard joiner (any device can join)
      {:ok, joiner} = Joiner.create_any(%{
        network_id: network.id,
        pskd: "ABCDEF",
        timeout: 300
      })
  """
  use Ash.Resource,
    domain: NTBR.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  attributes do
    uuid_primary_key(:id)

    attribute :eui64, :binary do
      description("""
      64-bit Extended Unique Identifier for the joining device.
      If null, this is a wildcard joiner (any device can use this PSKD).
      """)

      allow_nil?(true)
      public?(true)
    end

    attribute :pskd, :string do
      description("""
      Pre-Shared Key for Device (6-32 characters, base32).
      Used during Thread commissioning for device authentication.
      Marked as sensitive to prevent logging.
      """)

      allow_nil?(false)
      sensitive?(true)
      constraints(min_length: 6, max_length: 32)
      public?(true)
    end

    attribute :timeout, :integer do
      description("""
      How long (in seconds) this joiner credential is valid.
      After timeout, joiner expires if not completed.
      """)

      allow_nil?(false)
      default(120)
      constraints(min: 30, max: 600)
      public?(true)
    end

    attribute :state, :atom do
      description("""
      Current state in the joining process.
      Managed by AshStateMachine.
      """)

      allow_nil?(false)
      default(:pending)
      constraints(one_of: [:pending, :joining, :joined, :failed, :expired])
      public?(true)
    end

    attribute :discerner, :map do
      description("""
      Optional joiner discerner for distinguishing between devices.
      Format: %{length: bits, value: integer}
      Used when multiple devices share the same EUI-64 prefix.
      """)

      allow_nil?(true)
      public?(true)
    end

    attribute :vendor_name, :string do
      description("""
      Vendor name from commissioning TLVs.
      Optional, provided by joining device.
      """)

      allow_nil?(true)
      constraints(max_length: 32)
      public?(true)
    end

    attribute :vendor_model, :string do
      description("""
      Vendor model/product name.
      Optional, provided by joining device.
      """)

      allow_nil?(true)
      constraints(max_length: 32)
      public?(true)
    end

    attribute :vendor_sw_version, :string do
      description("""
      Software/firmware version.
      Optional, provided by joining device.
      """)

      allow_nil?(true)
      constraints(max_length: 16)
      public?(true)
    end

    attribute :provisioning_url, :string do
      description("""
      URL for device provisioning information.
      Optional, provided by joining device.
      """)

      allow_nil?(true)
      public?(true)
    end

    attribute :started_at, :utc_datetime_usec do
      description("""
      When the joining process started (state changed to :joining).
      """)

      allow_nil?(true)
      public?(true)
    end

    attribute :completed_at, :utc_datetime_usec do
      description("""
      When the joining process completed (success or failure).
      """)

      allow_nil?(true)
      public?(true)
    end

    attribute :expires_at, :utc_datetime_usec do
      description("""
      When this joiner credential expires.
      Calculated as started_at + timeout.
      """)

      allow_nil?(true)
      public?(true)
    end

    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :network, NTBR.Domain.Resources.Network do
      description("The network this device is trying to join")
      allow_nil?(false)
    end

    belongs_to :device, NTBR.Domain.Resources.Device do
      description("The device record once successfully joined")
      allow_nil?(true)
    end
  end

  calculations do
    calculate :is_wildcard, :boolean do
      description("True if this is a wildcard joiner (no specific EUI-64)")

      calculation(fn records, _context ->
        Enum.map(records, fn joiner ->
          is_nil(joiner.eui64)
        end)
      end)
    end

    calculate :time_remaining, :integer do
      description("Seconds remaining until expiration (nil if not started)")

      calculation(fn records, _context ->
        now = DateTime.utc_now()

        Enum.map(records, fn joiner ->
          if joiner.expires_at do
            max(DateTime.diff(joiner.expires_at, now, :second), 0)
          else
            nil
          end
        end)
      end)
    end

    calculate :duration_seconds, :integer do
      description("How long the joining process took (nil if not completed)")

      calculation(fn records, _context ->
        Enum.map(records, fn joiner ->
          if joiner.started_at && joiner.completed_at do
            DateTime.diff(joiner.completed_at, joiner.started_at, :second)
          else
            nil
          end
        end)
      end)
    end

    calculate :is_expired, :boolean do
      description("True if past expiration time")

      calculation(fn records, _context ->
        now = DateTime.utc_now()

        Enum.map(records, fn joiner ->
          if joiner.expires_at do
            DateTime.compare(now, joiner.expires_at) == :gt
          else
            false
          end
        end)
      end)
    end
  end

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition :start do
        from(:pending)
        to(:joining)
      end

      transition :complete do
        from(:joining)
        to(:joined)
      end

      transition :fail do
        from([:pending, :joining])
        to(:failed)
      end

      transition :expire do
        from([:pending, :joining])
        to(:expired)
      end
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      description("Create a joiner for a specific device (by EUI-64)")

      accept([
        :network_id,
        :eui64,
        :pskd,
        :timeout,
        :discerner,
        :vendor_name,
        :vendor_model,
        :vendor_sw_version,
        :provisioning_url
      ])

      validate(fn changeset, _context ->
        eui64 = Ash.Changeset.get_attribute(changeset, :eui64)
        pskd = Ash.Changeset.get_attribute(changeset, :pskd)

        cond do
          is_nil(eui64) ->
            {:error, "EUI-64 required for specific joiner. Use create_any for wildcard."}

          byte_size(eui64) != 8 ->
            {:error, "EUI-64 must be exactly 8 bytes"}

          not is_nil(pskd) and not valid_pskd?(pskd) ->
            {:error, "PSKD must contain only uppercase alphanumeric characters (0-9, A-Z)"}

          true ->
            :ok
        end
      end)
    end

    create :create_any do
      description("Create a wildcard joiner (any device with correct PSKD can join)")
      accept([:network_id, :pskd, :timeout])

      validate(fn changeset, _context ->
        pskd = Ash.Changeset.get_attribute(changeset, :pskd)

        if not is_nil(pskd) and not valid_pskd?(pskd) do
          {:error, "PSKD must contain only uppercase alphanumeric characters (0-9, A-Z)"}
        else
          :ok
        end
      end)

      change(fn changeset, _context ->
        # Explicitly set eui64 to nil for wildcard
        Ash.Changeset.change_attribute(changeset, :eui64, nil)
      end)
    end

    read :active do
      description("Get all active joiners (pending or joining)")
      filter(expr(state in [:pending, :joining]))
      prepare(build(sort: [created_at: :desc]))
    end

    read :by_network do
      description("Get all joiners for a specific network")
      argument(:network_id, :uuid, allow_nil?: false)
      filter(expr(network_id == ^arg(:network_id)))
      prepare(build(sort: [created_at: :desc]))
    end

    read :by_state do
      description("Get joiners in a specific state")
      argument(:state, :atom, allow_nil?: false)
      filter(expr(state == ^arg(:state)))
    end

    read :wildcards do
      description("Get all wildcard joiners")
      filter(expr(is_nil(eui64)))
    end

    read :specific do
      description("Get all specific (non-wildcard) joiners")
      filter(expr(not is_nil(eui64)))
    end

    read :by_eui64 do
      description("Find joiner for a specific EUI-64")
      argument(:eui64, :binary, allow_nil?: false)
      filter(expr(eui64 == ^arg(:eui64)))
    end

    read :expired_joiners do
      description("Find joiners that have passed their expiration time")

      filter(
        expr(
          not is_nil(expires_at) and
            expires_at < now() and
            state in [:pending, :joining]
        )
      )
    end

    update :update do
      description("Update joiner metadata (vendor info, timeout)")
      accept([:timeout, :vendor_name, :vendor_model, :vendor_sw_version, :provisioning_url])
      require_atomic?(false)

      validate(fn changeset, _context ->
        state = Ash.Changeset.get_attribute(changeset, :state)

        if state in [:pending, :joining] do
          :ok
        else
          {:error, "Can only update active joiners"}
        end
      end)
    end

    update :start do
      description("Start the joining process - triggers state transition to :joining")
      require_atomic?(false)
      change(transition_state(:joining))

      change(fn changeset, _context ->
        timeout = Ash.Changeset.get_attribute(changeset, :timeout)
        now = DateTime.utc_now()
        expires = DateTime.add(now, timeout, :second)

        changeset
        |> Ash.Changeset.change_attribute(:started_at, now)
        |> Ash.Changeset.change_attribute(:expires_at, expires)
      end)
    end

    update :complete do
      description("Mark joining as successfully completed")
      require_atomic?(false)
      change(transition_state(:joined))

      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end)
    end

    update :fail do
      description("Mark joining as failed")
      require_atomic?(false)
      change(transition_state(:failed))

      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end)
    end

    update :expire do
      description("Mark joiner credential as expired")
      require_atomic?(false)
      change(transition_state(:expired))

      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end)
    end

    update :link_device do
      description("Link this joiner to the device that successfully joined")
      argument(:device_id, :uuid, allow_nil?: false)
      require_atomic?(false)

      change(fn changeset, context ->
        Ash.Changeset.change_attribute(changeset, :device_id, context.arguments.device_id)
      end)

      validate(fn changeset, _context ->
        state = Ash.Changeset.get_attribute(changeset, :state)

        if state == :joined do
          :ok
        else
          {:error, "Can only link device after joining is complete"}
        end
      end)
    end
  end

  identities do
    identity(:unique_eui64_per_network, [:network_id, :eui64],
      where: expr(not is_nil(eui64)),
      pre_check_with: NTBR.Domain
    )
  end

  code_interface do
    define(:create)
    define(:create_any)
    define(:read)
    define(:update)
    define(:destroy)
    define(:active)
    define(:by_network, args: [:network_id])
    define(:by_state, args: [:state])
    define(:wildcards)
    define(:specific)
    define(:by_eui64, args: [:eui64])
    define(:expired_joiners)
    define(:link_device, args: [:device_id])
    define(:start)
    define(:complete)
    define(:fail)
    define(:expire)
    define(:by_id, action: :read, get_by: [:id])
    define(:by_id!, action: :read, get_by: [:id], get?: true)
  end

  @doc """
  Alias for expired_joiners with bang suffix for consistency.
  """
  def expired!(), do: expired_joiners!()

  # Private helper functions

  @spec valid_pskd?(term()) :: boolean()
  defp valid_pskd?(pskd) when is_binary(pskd) do
    # Thread spec: PSKD must contain only alphanumeric characters (0-9, A-Z, case-insensitive)
    String.match?(pskd, ~r/^[0-9A-Z]+$/i)
  end

  defp valid_pskd?(_), do: false
end
