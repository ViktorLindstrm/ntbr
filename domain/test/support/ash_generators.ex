defmodule NTBR.Domain.Test.AshGenerators do
  @moduledoc """
  Type-safe PropCheck generators for Ash resources.
  
  Based on PropCheck official patterns from:
  https://github.com/alfert/propcheck/tree/master/test
  
  All generators respect Ash resource constraints and use proper
  PropCheck patterns for dependent values and type safety.
  """
  use PropCheck
  import PropCheck

  @type uuid :: String.t()

  # ===========================================================================
  # UUID Generators
  # ===========================================================================

  @spec uuid_gen() :: PropCheck.type()
  @doc """
  Generates a valid UUID v4 string compatible with Ash's uuid_primary_key.
  
  Returns UUID in the format: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  
  ## Example
      iex> {:ok, uuid} = PropCheck.produce(uuid_gen())
      iex> String.length(uuid)
      36
  """
  def uuid_gen do
    let bytes <- binary(16) do
      # Convert to UUID v4 format
      <<a::32, b::16, c::16, d::16, e::48>> = bytes
      
      # Set version to 4 and variant to RFC 4122
      c_variant = (c &&& 0x0FFF) ||| 0x4000
      d_variant = (d &&& 0x3FFF) ||| 0x8000
      
      format_uuid(a, b, c_variant, d_variant, e)
    end
  end

  defp format_uuid(a, b, c, d, e) do
    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a, b, c, d, e]
    )
    |> IO.iodata_to_binary()
    |> String.downcase()
  end

  # ===========================================================================
  # Network Generators
  # ===========================================================================

  @spec network_name_gen() :: PropCheck.type()
  @doc """
  Generates valid network names respecting Ash constraint:
  - min_length: 1
  - max_length: 16
  
  Uses alphanumeric characters and hyphens.
  """
  def network_name_gen do
    let length <- integer(1, 16) do
      let chars <- vector(length, oneof([char(?a..?z), char(?A..?Z), char(?0..?9), exactly(?-)])) do
        to_string(chars)
      end
    end
  end

  @spec network_attrs_gen() :: PropCheck.type()
  @doc """
  Generates valid Network creation attributes.
  
  Returns a map with all required fields respecting Ash constraints.
  """
  def network_attrs_gen do
    let {name, net_name} <- {network_name_gen(), network_name_gen()} do
      %{
        name: name,
        network_name: net_name
      }
    end
  end

  # ===========================================================================
  # Device Generators
  # ===========================================================================

  @spec rloc16_gen() :: PropCheck.type()
  @doc """
  Generates RLOC16 in valid range [0, 0xFFFF].
  
  Thread RLOC16 is a 16-bit routing locator.
  """
  def rloc16_gen, do: integer(0, 0xFFFF)

  @spec extended_address_gen() :: PropCheck.type()
  @doc """
  Generates 8-byte extended address (EUI-64).
  """
  def extended_address_gen, do: binary(8)

  @spec device_type_gen() :: PropCheck.type()
  @doc """
  Generates valid device types per Ash constraint.
  """
  def device_type_gen do
    oneof([:end_device, :router, :leader, :reed])
  end

  @spec link_quality_gen() :: PropCheck.type()
  @doc """
  Generates link quality indicator (0-3).
  """
  def link_quality_gen, do: integer(0, 3)

  @spec rssi_gen() :: PropCheck.type()
  @doc """
  Generates RSSI value (typically -100 to 0 dBm).
  """
  def rssi_gen, do: integer(-100, 0)

  @spec device_attrs_gen(uuid(), uuid() | nil) :: PropCheck.type()
  @doc """
  Generates valid Device creation attributes.
  
  Respects all Ash constraints:
  - network_id: required UUID
  - parent_id: optional UUID (for child devices)
  - rloc16: 0..0xFFFF
  - extended_address: 8 bytes
  - device_type: one of [:end_device, :router, :leader, :reed]
  
  ## Examples
      # Device without parent
      device_attrs_gen(network_id, nil)
      
      # Device with parent (child device)
      device_attrs_gen(network_id, parent_id)
  """
  def device_attrs_gen(network_id, parent_id \\ nil) do
    let {rloc16, extended_addr, device_type, link_quality, rssi} <- {
      rloc16_gen(),
      extended_address_gen(),
      device_type_gen(),
      link_quality_gen(),
      rssi_gen()
    } do
      base_attrs = %{
        network_id: network_id,
        rloc16: rloc16,
        extended_address: extended_addr,
        device_type: device_type,
        link_quality: link_quality,
        rssi: rssi
      }

      if parent_id do
        Map.put(base_attrs, :parent_id, parent_id)
      else
        base_attrs
      end
    end
  end

  # ===========================================================================
  # Joiner Generators
  # ===========================================================================

  @spec pskd_gen() :: PropCheck.type()
  @doc """
  Generates valid Pre-Shared Key for Device (PSKD).
  
  Thread specification requires PSKD to be:
  - 6 to 32 characters
  - Uppercase letters and digits (base-32)
  """
  def pskd_gen do
    let length <- integer(6, 32) do
      let chars <- vector(length, oneof([char(?0..?9), char(?A..?Z)])) do
        to_string(chars)
      end
    end
  end

  @spec joiner_timeout_gen() :: PropCheck.type()
  @doc """
  Generates valid joiner timeout in seconds (30-300).
  """
  def joiner_timeout_gen, do: integer(30, 300)

  @spec joiner_attrs_gen(uuid()) :: PropCheck.type()
  @doc """
  Generates valid Joiner creation attributes.
  
  Respects Thread commissioning constraints.
  """
  def joiner_attrs_gen(network_id) do
    let {eui64, pskd, timeout} <- {
      extended_address_gen(),
      pskd_gen(),
      joiner_timeout_gen()
    } do
      %{
        network_id: network_id,
        eui64: eui64,
        pskd: pskd,
        timeout: timeout
      }
    end
  end

  # ===========================================================================
  # BorderRouter Generators  
  # ===========================================================================

  @spec border_router_attrs_gen(uuid()) :: PropCheck.type()
  @doc """
  Generates valid BorderRouter creation attributes.
  """
  def border_router_attrs_gen(network_id) do
    let {name, ipv6_prefix} <- {network_name_gen(), binary(8)} do
      %{
        network_id: network_id,
        name: name,
        ipv6_prefix: ipv6_prefix
      }
    end
  end

  # ===========================================================================
  # Test Scenario Generators
  # ===========================================================================

  @spec resource_enumeration_gen() :: PropCheck.type()
  @doc """
  Generates a tuple of {existing_id, non_existing_id} for security testing.
  
  Both IDs are valid UUIDs (not binaries) to prevent type errors.
  
  ## Example
      iex> {id1, id2} = PropCheck.produce(resource_enumeration_gen())
      iex> is_binary(id1) and String.contains?(id1, "-")
      true
  """
  def resource_enumeration_gen do
    let {uuid1, uuid2} <- {uuid_gen(), uuid_gen()} do
      {uuid1, uuid2}
    end
  end

  @spec network_partition_gen() :: PropCheck.type()
  @doc """
  Generates network partition scenario for eclipse attack testing.
  """
  def network_partition_gen do
    let {fake_count, isolation_type} <- {
      integer(5, 20),
      oneof([:full, :partial])
    } do
      %{
        fake_count: fake_count,
        isolation_type: isolation_type
      }
    end
  end

  @spec state_conflict_gen() :: PropCheck.type()
  @doc """
  Generates conflicting state scenario for consensus testing.
  """
  def state_conflict_gen do
    let count <- integer(3, 10) do
      let conflicting_states <- vector(count, oneof([:child, :router, :detached])) do
        %{
          conflicting_states: conflicting_states
        }
      end
    end
  end

  @spec malformed_flood_gen() :: PropCheck.type()
  @doc """
  Generates a flood of malformed data for resource exhaustion testing.
  
  Uses proper PropCheck patterns with `let` for dependent values.
  """
  def malformed_flood_gen do
    let count <- integer(100, 500) do
      let malformed_list <- vector(count, malformed_binary_gen()) do
        malformed_list
      end
    end
  end

  @spec malformed_binary_gen() :: PropCheck.type()
  @doc """
  Generates individual malformed binary payloads.
  """
  def malformed_binary_gen do
    oneof([
      # Random length binary
      let len <- integer(0, 100) do
        binary(len)
      end,
      # Edge cases
      exactly(<<0xFF, 0xFF>>),
      exactly(<<0x00>>),
      exactly(<<>>),
      # Invalid frame markers
      exactly(<<0x7E, 0x7E>>),
      exactly(<<0x7D>>)
    ])
  end

  @spec credential_timing_gen() :: PropCheck.type()
  @doc """
  Generates credential sets for timing attack testing.
  
  Returns {correct_credential, similar_credentials, different_credentials}.
  """
  def credential_timing_gen do
    let base_cred <- pskd_gen() do
      let {similar, different} <- {
        similar_credentials_gen(base_cred),
        different_credentials_gen(4)
      } do
        {base_cred, similar, different}
      end
    end
  end

  defp similar_credentials_gen(base_cred) do
    # Generate credentials with 1-2 characters different
    let mutations <- vector(4, integer(0, String.length(base_cred) - 1)) do
      Enum.map(mutations, fn pos ->
        base_cred
        |> String.graphemes()
        |> List.update_at(pos, fn _ -> "X" end)
        |> Enum.join()
      end)
    end
  end

  defp different_credentials_gen(count) do
    vector(count, pskd_gen())
  end

  @spec frame_sequence_gen(pos_integer(), pos_integer()) :: PropCheck.type()
  @doc """
  Generates a sequence of encoded Spinel frames for testing.
  
  ## Parameters
  - min: Minimum number of frames
  - max: Maximum number of frames
  """
  def frame_sequence_gen(min, max) do
    let count <- integer(min, max) do
      let frames <- vector(count, frame_data_gen()) do
        frames
      end
    end
  end

  defp frame_data_gen do
    let {command, tid, payload} <- {
      oneof([:prop_value_get, :prop_value_set, :prop_value_is]),
      integer(0, 15),
      binary()
    } do
      # This is a simplified version - actual implementation would use Frame module
      # For now, just return the encoded components
      <<tid::4, 0::4>> <> payload
    end
  end
end
