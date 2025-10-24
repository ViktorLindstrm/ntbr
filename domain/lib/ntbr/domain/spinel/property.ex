defmodule NTBR.Domain.Spinel.Property do
  @moduledoc """
  Spinel protocol property definitions and utilities.

  Properties are used to get/set configuration and state on the RCP.
  Each property has a unique ID and represents a specific aspect of the
  Thread network or radio configuration.
  """

  # Core properties (0x00-0x0F)
  @type property_atom ::
          :last_status
          | :protocol_version
          | :ncp_version
          | :interface_type
          | :vendor_id
          | :caps
          | :interface_count
          | :power_state
          | :hwaddr
          | :lock
          | :host_power_state
          | :mcu_power_state
          # PHY properties (0x70-0x7F)
          | :phy_enabled
          | :phy_chan
          | :phy_chan_supported
          | :phy_freq
          | :phy_cca_threshold
          | :phy_tx_power
          | :phy_rssi
          | :phy_rx_sensitivity
          | :phy_chan_preferred
          # MAC properties (0x80-0x9F)
          | :mac_scan_state
          | :mac_scan_mask
          | :mac_scan_period
          | :mac_scan_beacon
          | :mac_15_4_panid
          | :mac_15_4_laddr
          | :mac_15_4_saddr
          | :mac_raw_stream_enabled
          | :mac_filter_mode
          | :mac_src_match_enabled
          | :mac_src_match_short_addresses
          | :mac_src_match_extended_addresses
          | :mac_allowlist
          | :mac_allowlist_enabled
          | :mac_denylist
          | :mac_denylist_enabled
          | :mac_fixed_rss
          | :mac_cca_failure_rate
          | :mac_max_retry_number_direct
          | :mac_max_retry_number_indirect
          # NET properties (0xA0-0xBF)
          | :net_saved
          | :net_if_up
          | :net_stack_up
          | :net_role
          | :net_network_name
          | :net_xpanid
          | :net_network_key
          | :net_key_sequence_counter
          | :net_partition_id
          | :net_require_join_existing
          | :net_key_switch_guardtime
          | :net_pskc
          # Thread properties (0xC0-0xDF)
          | :thread_leader_addr
          | :thread_parent
          | :thread_child_table
          | :thread_leader_rid
          | :thread_leader_weight
          | :thread_local_leader_weight
          | :thread_network_data
          | :thread_network_data_version
          | :thread_stable_network_data
          | :thread_stable_network_data_version
          | :thread_on_mesh_nets
          | :thread_off_mesh_routes
          | :thread_assisting_ports
          | :thread_allow_local_net_data_change
          | :thread_mode
          | :thread_child_timeout
          | :thread_rloc16
          | :thread_router_upgrade_threshold
          | :thread_context_reuse_delay
          | :thread_network_id_timeout
          | :thread_active_router_ids
          | :thread_rloc16_debug_passthru
          | :thread_router_role_enabled
          | :thread_router_downgrade_threshold
          | :thread_router_selection_jitter
          | :thread_preferred_router_id
          | :thread_neighbor_table
          | :thread_child_count_max
          | :thread_leader_network_data
          | :thread_stable_leader_network_data
          # IPv6 properties (0xE0-0xEF)
          | :ipv6_ll_addr
          | :ipv6_ml_addr
          | :ipv6_ml_prefix
          | :ipv6_address_table
          | :ipv6_route_table
          | :ipv6_icmp_ping_offload
          | :ipv6_multicast_address_table
          | :ipv6_icmp_ping_offload_mode
          # Stream properties (0xF0-0xFF)
          | :stream_debug
          | :stream_raw
          | :stream_net
          | :stream_net_insecure
          | :stream_log

  @type property_id :: byte()
  @type property :: property_atom() | property_id()

  @type category ::
          :core
          | :phy
          | :mac
          | :net
          | :thread
          | :ipv6
          | :stream
          | :unknown

  # Property ID mappings
  @properties %{
    # Core (0x00-0x0F)
    0x00 => :last_status,
    0x01 => :protocol_version,
    0x02 => :ncp_version,
    0x03 => :interface_type,
    0x04 => :vendor_id,
    0x05 => :caps,
    0x06 => :interface_count,
    0x07 => :power_state,
    0x08 => :hwaddr,
    0x09 => :lock,
    0x0A => :host_power_state,
    0x0B => :mcu_power_state,
    # PHY (0x70-0x7F)
    0x70 => :phy_enabled,
    0x71 => :phy_chan,
    0x72 => :phy_chan_supported,
    0x73 => :phy_freq,
    0x74 => :phy_cca_threshold,
    0x75 => :phy_tx_power,
    0x76 => :phy_rssi,
    0x77 => :phy_rx_sensitivity,
    0x78 => :phy_chan_preferred,
    # MAC (0x80-0x9F)
    0x80 => :mac_scan_state,
    0x81 => :mac_scan_mask,
    0x82 => :mac_scan_period,
    0x83 => :mac_scan_beacon,
    0x84 => :mac_15_4_panid,
    0x85 => :mac_15_4_laddr,
    0x86 => :mac_15_4_saddr,
    0x87 => :mac_raw_stream_enabled,
    0x88 => :mac_filter_mode,
    0x89 => :mac_src_match_enabled,
    0x8A => :mac_src_match_short_addresses,
    0x8B => :mac_src_match_extended_addresses,
    0x8C => :mac_allowlist,
    0x8D => :mac_allowlist_enabled,
    0x8E => :mac_denylist,
    0x8F => :mac_denylist_enabled,
    0x90 => :mac_fixed_rss,
    0x91 => :mac_cca_failure_rate,
    0x92 => :mac_max_retry_number_direct,
    0x93 => :mac_max_retry_number_indirect,
    # NET (0xA0-0xBF)
    0xA0 => :net_saved,
    0xA1 => :net_if_up,
    0xA2 => :net_stack_up,
    0xA3 => :net_role,
    0xA4 => :net_network_name,
    0xA5 => :net_xpanid,
    0xA6 => :net_network_key,
    0xA7 => :net_key_sequence_counter,
    0xA8 => :net_partition_id,
    0xA9 => :net_require_join_existing,
    0xAA => :net_key_switch_guardtime,
    0xAB => :net_pskc,
    # Thread (0xC0-0xDF)
    0xC0 => :thread_leader_addr,
    0xC1 => :thread_parent,
    0xC2 => :thread_child_table,
    0xC3 => :thread_leader_rid,
    0xC4 => :thread_leader_weight,
    0xC5 => :thread_local_leader_weight,
    0xC6 => :thread_network_data,
    0xC7 => :thread_network_data_version,
    0xC8 => :thread_stable_network_data,
    0xC9 => :thread_stable_network_data_version,
    0xCA => :thread_on_mesh_nets,
    0xCB => :thread_off_mesh_routes,
    0xCC => :thread_assisting_ports,
    0xCD => :thread_allow_local_net_data_change,
    0xCE => :thread_mode,
    0xCF => :thread_child_timeout,
    0xD0 => :thread_rloc16,
    0xD1 => :thread_router_upgrade_threshold,
    0xD2 => :thread_context_reuse_delay,
    0xD3 => :thread_network_id_timeout,
    0xD4 => :thread_active_router_ids,
    0xD5 => :thread_rloc16_debug_passthru,
    0xD6 => :thread_router_role_enabled,
    0xD7 => :thread_router_downgrade_threshold,
    0xD8 => :thread_router_selection_jitter,
    0xD9 => :thread_preferred_router_id,
    0xDA => :thread_neighbor_table,
    0xDB => :thread_child_count_max,
    0xDC => :thread_leader_network_data,
    0xDD => :thread_stable_leader_network_data,
    # IPv6 (0xE0-0xEF)
    0xE0 => :ipv6_ll_addr,
    0xE1 => :ipv6_ml_addr,
    0xE2 => :ipv6_ml_prefix,
    0xE3 => :ipv6_address_table,
    0xE4 => :ipv6_route_table,
    0xE5 => :ipv6_icmp_ping_offload,
    0xE6 => :ipv6_multicast_address_table,
    0xE7 => :ipv6_icmp_ping_offload_mode,
    # Stream (0xF0-0xFF)
    0xF0 => :stream_debug,
    0xF1 => :stream_raw,
    0xF2 => :stream_net,
    0xF3 => :stream_net_insecure,
    0xF4 => :stream_log
  }

  @properties_reverse Map.new(@properties, fn {k, v} -> {v, k} end)

  @doc """
  Converts a property atom to its ID with compile-time validation.

  ## Examples

      iex> Property.to_id(:protocol_version)
      0x01

      iex> Property.to_id(:phy_chan)
      0x71

      iex> Property.to_id(0x01)
      0x01
  """
  @spec to_id(property()) :: property_id()
  def to_id(prop) when is_atom(prop) do
    case Map.fetch(@properties_reverse, prop) do
      {:ok, id} -> id
      :error -> 0x00
    end
  end

  def to_id(prop) when is_integer(prop) and prop in 0..255 do
    prop
  end

  @doc """
  Converts a property ID to its atom representation with validation.

  ## Examples

      iex> Property.from_id(0x01)
      :protocol_version

      iex> Property.from_id(0x71)
      :phy_chan

      iex> Property.from_id(:phy_chan)
      :phy_chan
  """
  @spec from_id(property()) :: property()
  def from_id(id) when is_integer(id) and id in 0..255 do
    Map.get(@properties, id, id)
  end

  def from_id(prop) when is_atom(prop), do: prop

  @doc """
  Returns all supported properties.
  """
  @spec all() :: [property_atom()]
  def all, do: Map.values(@properties)

  @doc """
  Returns all property IDs.
  """
  @spec all_ids() :: [property_id()]
  def all_ids, do: Map.keys(@properties)

  @doc """
  Returns the category of a property with compile-time guarantees.

  ## Examples

      iex> Property.category(:protocol_version)
      :core

      iex> Property.category(:phy_chan)
      :phy

      iex> Property.category(:thread_role)
      :net
  """
  @spec category(property()) :: category()
  def category(prop) when is_atom(prop) do
    case Atom.to_string(prop) do
      "last_status" ->
        :core

      "protocol_version" ->
        :core

      "ncp_version" ->
        :core

      "interface_type" ->
        :core

      "vendor_id" ->
        :core

      "caps" ->
        :core

      "interface_count" ->
        :core

      "power_state" ->
        :core

      "hwaddr" ->
        :core

      "lock" ->
        :core

      "host_power_state" ->
        :core

      "mcu_power_state" ->
        :core

      str when byte_size(str) >= 4 ->
        case :binary.part(str, 0, 4) do
          "phy_" ->
            :phy

          "mac_" ->
            :mac

          "net_" ->
            :net

          "ipv6" ->
            :ipv6

          _ ->
            case :binary.part(str, 0, min(7, byte_size(str))) do
              "thread_" -> :thread
              "stream_" -> :stream
              _ -> :unknown
            end
        end

      _ ->
        :unknown
    end
  end

  def category(id) when is_integer(id) and id in 0..255 do
    cond do
      id in 0x00..0x0F -> :core
      id in 0x70..0x7F -> :phy
      id in 0x80..0x9F -> :mac
      id in 0xA0..0xBF -> :net
      id in 0xC0..0xDF -> :thread
      id in 0xE0..0xEF -> :ipv6
      id in 0xF0..0xFF -> :stream
      true -> :unknown
    end
  end

  @doc """
  Returns all properties in a specific category.

  ## Examples

      iex> Property.by_category(:phy)
      [:phy_enabled, :phy_chan, :phy_chan_supported, ...]
  """
  @spec by_category(category()) :: [property_atom()]
  def by_category(cat) when is_atom(cat) do
    @properties
    |> Map.values()
    |> Enum.filter(&(category(&1) == cat))
  end

  @doc """
  Checks if a property is valid with type-safe guards.

  ## Examples

      iex> Property.valid?(:phy_chan)
      true

      iex> Property.valid?(:invalid_property)
      false

      iex> Property.valid?(0x71)
      true
  """
  @spec valid?(term()) :: boolean()
  def valid?(prop) when is_atom(prop) do
    Map.has_key?(@properties_reverse, prop)
  end

  def valid?(id) when is_integer(id) and id in 0..255 do
    Map.has_key?(@properties, id)
  end

  def valid?(_), do: false

  @doc """
  Returns a human-readable description of a property.
  """
  @spec description(property()) :: String.t()
  def description(prop) do
    prop = from_id(prop)

    case prop do
      # Core
      :last_status -> "Last operation status code"
      :protocol_version -> "Spinel protocol version"
      :ncp_version -> "NCP firmware version string"
      :interface_type -> "Network interface type"
      :vendor_id -> "Vendor identification"
      :caps -> "Supported capabilities"
      :interface_count -> "Number of network interfaces"
      :power_state -> "Current power state"
      :hwaddr -> "Hardware MAC address"
      # PHY
      :phy_enabled -> "PHY radio enabled state"
      :phy_chan -> "Current radio channel"
      :phy_chan_supported -> "List of supported channels"
      :phy_freq -> "Current radio frequency"
      :phy_tx_power -> "Transmit power in dBm"
      :phy_rssi -> "Received signal strength"
      # MAC
      :mac_15_4_panid -> "802.15.4 PAN ID"
      :mac_15_4_laddr -> "802.15.4 long (extended) address"
      :mac_15_4_saddr -> "802.15.4 short address"
      :mac_scan_state -> "Current scan state"
      :mac_filter_mode -> "MAC filter mode (allowlist/denylist)"
      # NET
      :net_saved -> "Network configuration saved"
      :net_if_up -> "Network interface is up"
      :net_stack_up -> "Network stack is up"
      :net_role -> "Current Thread role"
      :net_network_name -> "Thread network name"
      :net_xpanid -> "Extended PAN ID"
      :net_network_key -> "Network encryption key"
      # Thread
      :thread_leader_addr -> "Thread leader IPv6 address"
      :thread_mode -> "Thread device mode"
      :thread_rloc16 -> "Thread Router Locator"
      :thread_child_timeout -> "Child timeout in seconds"
      :thread_network_data -> "Thread network data TLVs"
      # IPv6
      :ipv6_ll_addr -> "Link-local IPv6 address"
      :ipv6_ml_addr -> "Mesh-local IPv6 address"
      :ipv6_address_table -> "IPv6 address table"
      # Stream
      :stream_debug -> "Debug output stream"
      :stream_raw -> "Raw packet stream"
      :stream_net -> "Network packet stream"
      :stream_log -> "Log message stream"
      _ -> "Unknown property"
    end
  end

  @doc """
  Checks if a property is read-only.
  """
  @spec read_only?(property()) :: boolean()
  def read_only?(prop) do
    prop = from_id(prop)

    prop in [
      :last_status,
      :protocol_version,
      :ncp_version,
      :interface_type,
      :vendor_id,
      :caps,
      :interface_count,
      :hwaddr,
      :phy_chan_supported,
      :phy_rssi,
      :thread_leader_addr,
      :thread_rloc16
    ]
  end

  @doc "Network key (16 bytes)"
  def net_network_key, do: 0x18  # PROP_NET_NETWORK_KEY
  
  @doc "Network name (UTF-8 string, max 16 bytes)"
  def net_network_name, do: 0x19  # PROP_NET_NETWORK_NAME
  
  @doc "Extended PAN ID (8 bytes)"
  def net_xpanid, do: 0x1A  # PROP_NET_XPANID
  
  @doc "Network interface up/down"
  def net_if_up, do: 0x20  # PROP_NET_IF_UP
  
  @doc "Network stack up/down"
  def net_stack_up, do: 0x21  # PROP_NET_STACK_UP
  
  @doc "Network role"
  def net_role, do: 0x22  # PROP_NET_ROLE
  
  # MAC properties
  @doc "MAC PAN ID"
  def mac_pan_id, do: 0x30  # PROP_MAC_15_4_PANID
  
  # PHY properties
  @doc "PHY channel"
  def phy_chan, do: 0x00  # PROP_PHY_CHAN
  
  # Thread properties
  @doc "Thread router table"
  def thread_router_table, do: 0x71  # PROP_THREAD_ROUTER_TABLE
  
  @doc "Thread child table"
  def thread_child_table, do: 0x72  # PROP_THREAD_CHILD_TABLE
  
  # NCP properties
  @doc "NCP version string"
  def ncp_version, do: 0x02  # PROP_NCP_VERSION
  
  @doc "NCP capabilities"
  def caps, do: 0x61  # PROP_CAPS

end
