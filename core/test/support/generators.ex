defmodule Core.Test.Generators do
  @moduledoc """
  PropCheck generators for NTBR domain types.
  
  Provides reusable generators for property-based testing across
  the NTBR project, ensuring consistent test data generation.
  """
  
  use PropCheck
  
  # Thread Network Generators
  
  @doc """
  Generates valid Thread network names (1-16 UTF-8 characters).
  """
  def network_name do
    let name <- utf8(1, 16) do
      # Ensure printable characters
      String.trim(name)
    end
  end
  
  @doc """
  Generates valid PAN IDs (0x0000 - 0xFFFF).
  """
  def pan_id do
    integer(0, 0xFFFF)
  end
  
  @doc """
  Generates valid IEEE 802.15.4 channel numbers (11-26).
  """
  def channel do
    integer(11, 26)
  end
  
  @doc """
  Generates 8-byte extended PAN ID.
  """
  def extended_pan_id do
    binary(8)
  end
  
  @doc """
  Generates 16-byte Thread network master key.
  """
  def network_key do
    binary(16)
  end
  
  @doc """
  Generates valid Thread device role.
  """
  def role do
    oneof([:disabled, :detached, :child, :router, :leader])
  end
  
  @doc """
  Generates valid network state.
  """
  def network_state do
    oneof([:offline, :joining, :attached, :active])
  end
  
  @doc """
  Generates valid RLOC16 value.
  """
  def rloc16 do
    integer(0, 0xFFFF)
  end
  
  @doc """
  Generates link quality indicator (0-3).
  """
  def link_quality do
    integer(0, 3)
  end
  
  @doc """
  Generates router ID (6-bit, 0-63).
  """
  def router_id do
    integer(0, 0x3F)
  end
  
  @doc """
  Generates a complete valid Thread network dataset.
  """
  def thread_dataset do
    let {name, pan, chan, xpan, key, role, state} <- {
      network_name(),
      pan_id(),
      channel(),
      extended_pan_id(),
      network_key(),
      role(),
      network_state()
    } do
      %{
        name: name,
        pan_id: pan,
        channel: chan,
        extended_pan_id: xpan,
        network_key: key,
        role: role,
        state: state
      }
    end
  end
  
  @doc """
  Generates Thread network with active topology.
  """
  def active_network do
    let {dataset, child_count, router_count, leader_id, data_version} <- {
      thread_dataset(),
      non_neg_integer(),
      non_neg_integer(),
      router_id(),
      non_neg_integer()
    } do
      dataset
      |> Map.put(:role, oneof([:child, :router, :leader]))
      |> Map.put(:state, :active)
      |> Map.put(:child_count, child_count)
      |> Map.put(:router_count, router_count)
      |> Map.put(:leader_router_id, leader_id)
      |> Map.put(:network_data_version, data_version)
    end
  end
  
  # Spinel Frame Generators
  
  @doc """
  Generates valid Spinel header byte.
  """
  def spinel_header do
    integer(0, 0xFF)
  end
  
  @doc """
  Generates valid Spinel command.
  """
  def spinel_command do
    oneof([
      :reset,
      :noop,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove,
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ])
  end
  
  @doc """
  Generates request-type Spinel command.
  """
  def spinel_request_command do
    oneof([
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove
    ])
  end
  
  @doc """
  Generates response-type Spinel command.
  """
  def spinel_response_command do
    oneof([
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ])
  end
  
  @doc """
  Generates valid TID (4-bit, 0-15).
  """
  def tid do
    integer(0, 15)
  end
  
  @doc """
  Generates Spinel property identifier.
  """
  def spinel_property do
    oneof([
      :protocol_version,
      :ncp_version,
      :interface_type,
      :vendor_id,
      :caps,
      :hwaddr,
      :net_role,
      :net_network_name,
      :net_xpanid,
      :net_master_key,
      :net_key_sequence_counter,
      :thread_rloc16,
      :thread_router_id,
      :thread_child_table,
      :thread_neighbor_table,
      :thread_leader_router_id,
      :thread_partition_id
    ])
  end
  
  @doc """
  Generates frame direction.
  """
  def frame_direction do
    oneof([:inbound, :outbound])
  end
  
  @doc """
  Generates frame status.
  """
  def frame_status do
    oneof([:success, :error, :timeout, :malformed])
  end
  
  @doc """
  Generates Spinel frame payload.
  """
  def spinel_payload do
    # Variable length payload (0-255 bytes typical)
    let size <- integer(0, 255) do
      binary(size)
    end
  end
  
  @doc """
  Generates a complete valid Spinel frame.
  """
  def spinel_frame do
    let {seq, dir, header, cmd, tid, prop, payload, status} <- {
      non_neg_integer(),
      frame_direction(),
      spinel_header(),
      spinel_command(),
      tid(),
      spinel_property(),
      spinel_payload(),
      frame_status()
    } do
      %{
        sequence: seq,
        direction: dir,
        header: header,
        command: cmd,
        tid: tid,
        property: prop,
        payload: payload,
        size_bytes: 2 + byte_size(payload),
        status: status,
        timestamp: DateTime.utc_now()
      }
    end
  end
  
  @doc """
  Generates request/response frame pair with matching TID.
  """
  def frame_pair do
    let {seq, tid, prop, req_payload, resp_payload} <- {
      non_neg_integer(),
      tid(),
      spinel_property(),
      spinel_payload(),
      spinel_payload()
    } do
      request = %{
        sequence: seq,
        direction: :outbound,
        command: :prop_value_get,
        tid: tid,
        property: prop,
        payload: req_payload,
        size_bytes: 2 + byte_size(req_payload),
        status: :success,
        timestamp: DateTime.utc_now()
      }
      
      response = %{
        sequence: seq + 1,
        direction: :inbound,
        command: :prop_value_is,
        tid: tid,
        property: prop,
        payload: resp_payload,
        size_bytes: 2 + byte_size(resp_payload),
        status: :success,
        timestamp: DateTime.add(DateTime.utc_now(), 10, :millisecond)
      }
      
      {request, response}
    end
  end
  
  # RCP Status Generators
  
  @doc """
  Generates serial port path.
  """
  def serial_port do
    let port_num <- integer(0, 9) do
      "/dev/ttyUSB#{port_num}"
    end
  end
  
  @doc """
  Generates baud rate.
  """
  def baudrate do
    oneof([9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600])
  end
  
  @doc """
  Generates RCP connection state.
  """
  def connection_state do
    oneof([:disconnected, :connecting, :connected, :error])
  end
  
  @doc """
  Generates protocol version string.
  """
  def protocol_version do
    let {major, minor} <- {integer(1, 4), integer(0, 9)} do
      "#{major}.#{minor}"
    end
  end
  
  @doc """
  Generates NCP/RCP version string.
  """
  def ncp_version do
    let {major, minor, patch} <- {integer(1, 2), integer(0, 9), integer(0, 99)} do
      "OpenThread/#{major}.#{minor}.#{patch}"
    end
  end
  
  @doc """
  Generates RCP capabilities list.
  """
  def rcp_capabilities do
    let caps <- list(oneof([:config, :net, :mac, :raw, :gpio, :radio])) do
      Enum.uniq(caps)
    end
  end
  
  @doc """
  Generates IEEE 802.15.4 EUI-64 hardware address.
  """
  def hardware_address do
    binary(8)
  end
  
  @doc """
  Generates complete RCP status.
  """
  def rcp_status do
    let {port, baud, state, proto_ver, ncp_ver, caps, hwaddr, frames_sent, frames_recv, errors} <- {
      serial_port(),
      baudrate(),
      connection_state(),
      protocol_version(),
      ncp_version(),
      rcp_capabilities(),
      hardware_address(),
      non_neg_integer(),
      non_neg_integer(),
      non_neg_integer()
    } do
      %{
        port: port,
        baudrate: baud,
        connection_state: state,
        connected: state == :connected,
        protocol_version: proto_ver,
        ncp_version: ncp_ver,
        capabilities: caps,
        hardware_address: hwaddr,
        frames_sent: frames_sent,
        frames_received: frames_recv,
        frames_errored: errors,
        bytes_sent: frames_sent * 10,  # Approximate
        bytes_received: frames_recv * 10,
        uptime_seconds: non_neg_integer(),
        reset_count: integer(0, 10)
      }
    end
  end
  
  # Composite Generators
  
  @doc """
  Generates a network formation scenario (dataset + expected state).
  """
  def formation_scenario do
    let dataset <- thread_dataset() do
      expected_state = %{
        role: :leader,
        state: :active,
        partition_id: integer(0, 0xFFFFFFFF)
      }
      
      {dataset, expected_state}
    end
  end
  
  @doc """
  Generates a network attachment scenario.
  """
  def attachment_scenario do
    let dataset <- thread_dataset() do
      expected_state = %{
        role: :child,
        state: :joining,
        rloc16: rloc16()
      }
      
      {dataset, expected_state}
    end
  end
  
  @doc """
  Generates a frame exchange scenario (request + expected response).
  """
  def frame_exchange_scenario do
    let {request, response} <- frame_pair() do
      %{
        request: request,
        response: response,
        latency_ms: integer(1, 100)
      }
    end
  end
  
  # Helper Functions
  
  @doc """
  Generates list of unique sequence numbers.
  """
  def unique_sequences(count) do
    let seqs <- vector(count, non_neg_integer()) do
      seqs
      |> Enum.with_index()
      |> Enum.map(fn {_, idx} -> idx end)
    end
  end
  
  @doc """
  Generates timestamp in the past.
  """
  def past_timestamp do
    let seconds_ago <- integer(1, 3600) do
      DateTime.add(DateTime.utc_now(), -seconds_ago, :second)
    end
  end
  
  @doc """
  Generates valid MAC address.
  """
  def mac_address do
    let bytes <- vector(6, integer(0, 255)) do
      bytes
      |> Enum.map(&Integer.to_string(&1, 16))
      |> Enum.map(&String.pad_leading(&1, 2, "0"))
      |> Enum.join(":")
    end
  end
end
