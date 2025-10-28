defmodule NTBR.Domain.Spinel.FrameTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.Frame
  import Bitwise

  @moduletag :property
  @moduletag :spinel
  @moduletag :unit

  # Property-based test generators

  defp tid_gen do
    integer(0, 15)
  end

  defp command_gen do
    oneof([
      :noop,
      :reset,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove,
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ])
  end

  defp property_gen do
    oneof([
      :last_status,
      :protocol_version,
      :ncp_version,
      :interface_type,
      :vendor_id,
      :caps,
      :phy_enabled,
      :phy_chan,
      :mac_15_4_panid,
      :mac_15_4_laddr
    ])
  end

  defp payload_gen do
    binary()
  end

  defp frame_gen do
    let [command <- command_gen(), tid <- tid_gen(), payload <- payload_gen()] do
      Frame.new(command, payload, tid: tid)
    end
  end

  # Property-based tests
  property "encode/decode roundtrip preserves frame data" do
    forall frame <- frame_gen() do
      encoded = Frame.encode(frame)
      {:ok, decoded} = Frame.decode(encoded)

      decoded.command == frame.command and
        decoded.tid == frame.tid and
        decoded.payload == frame.payload
    end
  end

  property "TID is always between 0 and 15" do
    forall tid <- tid_gen() do
      frame = Frame.new(:reset, <<>>, tid: tid)
      frame.tid in 0..15 and frame.tid == tid
    end
  end

  property "header always has bit 7 set (host to NCP)" do
    forall frame <- frame_gen() do
      (frame.header &&& 0x80) == 0x80
    end
  end

  property "header lower 4 bits match TID" do
    forall frame <- frame_gen() do
      (frame.header &&& 0x0F) == frame.tid
    end
  end

  property "payload is preserved through encode/decode" do
    forall payload <- payload_gen() do
      frame = Frame.new(:prop_value_get, payload)
      encoded = Frame.encode(frame)
      {:ok, decoded} = Frame.decode(encoded)

      decoded.payload == payload
    end
  end

  property "property_get frames encode property correctly" do
    forall prop <- property_gen() do
      frame = Frame.prop_value_get(prop)
      {:ok, decoded} = Frame.decode(Frame.encode(frame))

      Frame.extract_property(decoded) == prop
    end
  end

  property "property_set frames preserve value" do
    forall [prop <- property_gen(), value <- binary()] do
      frame = Frame.prop_value_set(prop, value)
      {:ok, extracted_value} = Frame.extract_value(frame)

      extracted_value == value
    end
  end

  # Traditional unit tests for edge cases

  describe "new/3" do
    test "creates a reset frame" do
      frame = Frame.new(:reset, <<>>)

      assert frame.command == :reset
      assert frame.tid == 0
      assert frame.payload == <<>>
      assert frame.header == 0x80
    end

    test "creates a frame with custom TID" do
      frame = Frame.new(:reset, <<>>, tid: 5)

      assert frame.tid == 5
      assert frame.header == 0x85
    end

    test "raises on invalid TID" do
      assert_raise ArgumentError, fn ->
        Frame.new(:reset, <<>>, tid: 16)
      end

      assert_raise ArgumentError, fn ->
        Frame.new(:reset, <<>>, tid: -1)
      end
    end
  end

  describe "encode/1" do
    test "encodes a reset frame" do
      frame = Frame.new(:reset, <<>>)
      encoded = Frame.encode(frame)

      assert encoded == <<0x80, 0x01>>
    end

    test "encodes a property get frame" do
      frame = Frame.new(:prop_value_get, <<0x01>>, tid: 3)
      encoded = Frame.encode(frame)

      assert <<0x83, 0x02, 0x01>> == encoded
    end
  end

  describe "decode/1" do
    test "decodes a reset frame" do
      {:ok, frame} = Frame.decode(<<0x80, 0x01>>)

      assert frame.command == :reset
      assert frame.tid == 0
      assert frame.payload == <<>>
    end

    test "decodes a property value response" do
      {:ok, frame} = Frame.decode(<<0x83, 0x06, 0x01, 0x04, 0x00>>)

      assert frame.command == :prop_value_is
      assert frame.tid == 3
      assert frame.payload == <<0x01, 0x04, 0x00>>
    end

    test "returns error for invalid data" do
      assert {:error, :invalid_frame} = Frame.decode(<<0x80>>)
      assert {:error, :invalid_frame} = Frame.decode(<<>>)
    end
  end

  describe "helper functions" do
    test "reset/1 creates reset frame" do
      frame = Frame.reset(tid: 2)

      assert frame.command == :reset
      assert frame.tid == 2
    end

    test "prop_value_get/2 creates property get frame" do
      frame = Frame.prop_value_get(:protocol_version, tid: 1)

      assert frame.command == :prop_value_get
      assert frame.tid == 1
      assert frame.payload == <<0x01>>
    end

    test "prop_value_set/3 creates property set frame" do
      frame = Frame.prop_value_set(:phy_chan, <<15>>, tid: 4)

      assert frame.command == :prop_value_set
      assert frame.tid == 4
      assert frame.payload == <<0x71, 15>>
    end

    test "extract_property/1 returns property from frame" do
      frame = Frame.prop_value_get(:ncp_version)
      property = Frame.extract_property(frame)

      assert property == :ncp_version
    end

    test "extract_value/1 returns value from frame" do
      frame = %Frame{
        header: 0x80,
        command: :prop_value_is,
        tid: 0,
        payload: <<0x71, 15>>
      }

      {:ok, value} = Frame.extract_value(frame)
      assert value == <<15>>
    end

    test "extract_value/1 returns error for empty payload" do
      frame = %Frame{
        header: 0x80,
        command: :reset,
        tid: 0,
        payload: <<>>
      }

      assert {:error, :no_value} = Frame.extract_value(frame)
    end
  end

  describe "commands and properties" do
    test "commands/0 returns all supported commands" do
      commands = Frame.commands()

      assert :reset in commands
      assert :prop_value_get in commands
      assert :prop_value_set in commands
      assert length(commands) == 9
    end

    test "properties/0 returns all supported properties" do
      properties = Frame.properties()

      assert :protocol_version in properties
      assert :ncp_version in properties
      assert :phy_chan in properties
      assert length(properties) > 10
    end
  end
end
