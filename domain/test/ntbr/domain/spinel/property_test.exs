defmodule NTBR.Domain.Spinel.PropertyTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.Property

  @moduletag :property
  @moduletag :spinel
  @moduletag :unit

  # Property-based test generators

  defp property_atom_gen do
    oneof(Property.all())
  end

  defp property_id_gen do
    oneof(Property.all_ids())
  end

  defp category_gen do
    oneof([:core, :phy, :mac, :net, :thread, :ipv6, :stream])
  end

  # Property-based tests

  property "to_id/from_id roundtrip for all properties" do
    forall prop <- property_atom_gen() do
      id = Property.to_id(prop)
      Property.from_id(id) == prop
    end
  end

  property "from_id/to_id roundtrip for all IDs" do
    forall id <- property_id_gen() do
      prop = Property.from_id(id)

      # If it's a known property (atom), converting back should give same ID
      if is_atom(prop) do
        Property.to_id(prop) == id
      else
        # Unknown ID returns itself
        prop == id
      end
    end
  end

  property "to_id always returns a valid byte" do
    forall prop <- property_atom_gen() do
      id = Property.to_id(prop)
      is_integer(id) and id in 0..255
    end
  end

  property "to_id with integer returns same integer" do
    forall id <- integer(0, 255) do
      Property.to_id(id) == id
    end
  end

  property "from_id with atom returns same atom" do
    forall prop <- property_atom_gen() do
      Property.from_id(prop) == prop
    end
  end

  property "all properties are valid" do
    forall prop <- property_atom_gen() do
      Property.valid?(prop)
    end
  end

  property "all property IDs are valid" do
    forall id <- property_id_gen() do
      Property.valid?(id)
    end
  end

  property "category is consistent with property name" do
    forall prop <- property_atom_gen() do
      cat = Property.category(prop)
      prop_str = Atom.to_string(prop)

      # Category should match the prefix of the property name
      case cat do
        :core ->
          prop_str in [
            "last_status",
            "protocol_version",
            "ncp_version",
            "interface_type",
            "vendor_id",
            "caps",
            "interface_count",
            "power_state",
            "hwaddr",
            "lock",
            "host_power_state",
            "mcu_power_state"
          ]

        :phy ->
          String.starts_with?(prop_str, "phy_")

        :mac ->
          String.starts_with?(prop_str, "mac_")

        :net ->
          String.starts_with?(prop_str, "net_")

        :thread ->
          String.starts_with?(prop_str, "thread_")

        :ipv6 ->
          String.starts_with?(prop_str, "ipv6_")

        :stream ->
          String.starts_with?(prop_str, "stream_")

        _ ->
          false
      end
    end
  end

  property "by_category returns properties of that category" do
    forall cat <- category_gen() do
      props = Property.by_category(cat)

      Enum.all?(props, fn prop ->
        Property.category(prop) == cat
      end)
    end
  end

  property "category from ID matches category from atom" do
    forall prop <- property_atom_gen() do
      id = Property.to_id(prop)
      Property.category(id) == Property.category(prop)
    end
  end

  property "description is always non-empty string" do
    forall prop <- property_atom_gen() do
      desc = Property.description(prop)
      is_binary(desc) and byte_size(desc) > 0
    end
  end

  property "read_only? returns a boolean" do
    forall prop <- property_atom_gen() do
      is_boolean(Property.read_only?(prop))
    end
  end

  property "all() contains no duplicates" do
    all_props = Property.all()
    length(all_props) == length(Enum.uniq(all_props))
  end

  property "all_ids() contains no duplicates" do
    all_ids = Property.all_ids()
    length(all_ids) == length(Enum.uniq(all_ids))
  end

  # Traditional unit tests

  describe "to_id/1" do
    test "converts known properties to IDs" do
      assert Property.to_id(:protocol_version) == 0x01
      assert Property.to_id(:ncp_version) == 0x02
      assert Property.to_id(:phy_chan) == 0x71
      assert Property.to_id(:mac_15_4_panid) == 0x84
      assert Property.to_id(:thread_role) == 0xA3
      assert Property.to_id(:ipv6_ll_addr) == 0xE0
    end

    test "returns 0x00 for unknown property" do
      assert Property.to_id(:unknown_property) == 0x00
    end

    test "returns same value for integer input" do
      assert Property.to_id(0x71) == 0x71
      assert Property.to_id(0xFF) == 0xFF
    end
  end

  describe "from_id/1" do
    test "converts known IDs to properties" do
      assert Property.from_id(0x01) == :protocol_version
      assert Property.from_id(0x02) == :ncp_version
      assert Property.from_id(0x71) == :phy_chan
      assert Property.from_id(0x84) == :mac_15_4_panid
      assert Property.from_id(0xA3) == :net_role
      assert Property.from_id(0xE0) == :ipv6_ll_addr
    end

    test "returns ID for unknown property" do
      assert Property.from_id(0x99) == 0x99
      assert Property.from_id(0x50) == 0x50
    end

    test "returns same value for atom input" do
      assert Property.from_id(:phy_chan) == :phy_chan
      assert Property.from_id(:net_role) == :net_role
    end
  end

  describe "all/0 and all_ids/0" do
    test "all() returns comprehensive list of properties" do
      props = Property.all()

      assert :protocol_version in props
      assert :ncp_version in props
      assert :phy_chan in props
      assert :mac_15_4_panid in props
      assert :net_role in props
      assert :thread_mode in props
      assert :ipv6_ll_addr in props
      assert :stream_debug in props

      # Verify count (should have many properties)
      assert length(props) > 50
    end

    test "all_ids() returns all property IDs" do
      ids = Property.all_ids()

      assert 0x01 in ids
      assert 0x02 in ids
      assert 0x71 in ids
      assert 0x84 in ids
      assert 0xA3 in ids

      assert length(ids) > 50
    end

    test "all() and all_ids() have same length" do
      assert length(Property.all()) == length(Property.all_ids())
    end
  end

  describe "category/1" do
    test "returns correct category for core properties" do
      assert Property.category(:protocol_version) == :core
      assert Property.category(:ncp_version) == :core
      assert Property.category(:caps) == :core
      assert Property.category(0x01) == :core
      assert Property.category(0x05) == :core
    end

    test "returns correct category for PHY properties" do
      assert Property.category(:phy_enabled) == :phy
      assert Property.category(:phy_chan) == :phy
      assert Property.category(:phy_tx_power) == :phy
      assert Property.category(0x70) == :phy
      assert Property.category(0x75) == :phy
    end

    test "returns correct category for MAC properties" do
      assert Property.category(:mac_scan_state) == :mac
      assert Property.category(:mac_15_4_panid) == :mac
      assert Property.category(0x80) == :mac
      assert Property.category(0x84) == :mac
    end

    test "returns correct category for NET properties" do
      assert Property.category(:net_role) == :net
      assert Property.category(:net_network_name) == :net
      assert Property.category(0xA3) == :net
      assert Property.category(0xA4) == :net
    end

    test "returns correct category for Thread properties" do
      assert Property.category(:thread_mode) == :thread
      assert Property.category(:thread_rloc16) == :thread
      assert Property.category(0xCE) == :thread
      assert Property.category(0xD0) == :thread
    end

    test "returns correct category for IPv6 properties" do
      assert Property.category(:ipv6_ll_addr) == :ipv6
      assert Property.category(:ipv6_ml_addr) == :ipv6
      assert Property.category(0xE0) == :ipv6
      assert Property.category(0xE1) == :ipv6
    end

    test "returns correct category for stream properties" do
      assert Property.category(:stream_debug) == :stream
      assert Property.category(:stream_raw) == :stream
      assert Property.category(0xF0) == :stream
      assert Property.category(0xF1) == :stream
    end

    test "returns :unknown for undefined IDs" do
      assert Property.category(0x50) == :unknown
      assert Property.category(0x99) == :unknown
    end
  end

  describe "by_category/1" do
    test "returns all PHY properties" do
      phy_props = Property.by_category(:phy)

      assert :phy_enabled in phy_props
      assert :phy_chan in phy_props
      assert :phy_tx_power in phy_props

      # Should not contain non-PHY properties
      refute :net_role in phy_props
      refute :thread_mode in phy_props
    end

    test "returns all MAC properties" do
      mac_props = Property.by_category(:mac)

      assert :mac_15_4_panid in mac_props
      assert :mac_scan_state in mac_props

      refute :phy_chan in mac_props
    end

    test "returns all NET properties" do
      net_props = Property.by_category(:net)

      assert :net_role in net_props
      assert :net_network_name in net_props
      assert :net_xpanid in net_props

      refute :thread_mode in net_props
    end

    test "returns all Thread properties" do
      thread_props = Property.by_category(:thread)

      assert :thread_mode in thread_props
      assert :thread_rloc16 in thread_props
      assert :thread_child_timeout in thread_props

      refute :net_role in thread_props
    end

    test "returns empty list for unknown category" do
      assert Property.by_category(:unknown) == []
    end
  end

  describe "valid?/1" do
    test "returns true for known properties" do
      assert Property.valid?(:protocol_version)
      assert Property.valid?(:phy_chan)
      assert Property.valid?(:net_role)
      assert Property.valid?(0x01)
      assert Property.valid?(0x71)
    end

    test "returns false for unknown properties" do
      refute Property.valid?(:unknown_property)
      refute Property.valid?(:fake_prop)
      refute Property.valid?(0x50)
      refute Property.valid?(0x99)
    end
  end

  describe "description/1" do
    test "returns descriptions for known properties" do
      assert Property.description(:protocol_version) =~ "protocol version"
      assert Property.description(:phy_chan) =~ "channel"
      assert Property.description(:net_role) =~ "role"
      assert Property.description(:thread_mode) =~ "mode"
    end

    test "returns generic description for unknown properties" do
      assert Property.description(:unknown_prop) == "Unknown property"
      assert Property.description(0x99) == "Unknown property"
    end

    test "works with IDs" do
      assert Property.description(0x71) =~ "channel"
    end
  end

  describe "read_only?/1" do
    test "returns true for read-only properties" do
      assert Property.read_only?(:protocol_version)
      assert Property.read_only?(:ncp_version)
      assert Property.read_only?(:caps)
      assert Property.read_only?(:phy_chan_supported)
      assert Property.read_only?(:thread_rloc16)
    end

    test "returns false for writable properties" do
      refute Property.read_only?(:phy_enabled)
      refute Property.read_only?(:phy_chan)
      refute Property.read_only?(:net_network_name)
      refute Property.read_only?(:thread_mode)
    end
  end

  describe "integration with Frame" do
    test "Property integrates with Frame module" do
      alias NTBR.Domain.Spinel.Frame

      # Create frame using property atom
      frame = Frame.prop_value_get(:phy_chan, tid: 1)

      # Extract property
      prop = Frame.extract_property(frame)
      assert prop == :phy_chan

      # Verify it's a valid property
      assert Property.valid?(prop)
      assert Property.category(prop) == :phy
    end
  end
end
