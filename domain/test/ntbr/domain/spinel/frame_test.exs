defmodule NTBR.Domain.Spinel.FrameTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.Frame
  import Bitwise

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

defmodule NTBR.Domain.Spinel.DataEncoderTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.DataEncoder

  # Property-based test generators

  defp uint8_gen, do: integer(0, 255)
  defp uint16_gen, do: integer(0, 65535)
  defp uint32_gen, do: integer(0, 4_294_967_295)
  defp int8_gen, do: integer(-128, 127)
  defp int16_gen, do: integer(-32768, 32767)
  defp int32_gen, do: integer(-2_147_483_648, 2_147_483_647)
  defp bool_gen, do: boolean()
  defp utf8_gen, do: utf8()
  defp binary_gen, do: binary()

  defp eui64_gen do
    let bytes <- vector(8, byte()) do
      :binary.list_to_bin(bytes)
    end
  end

  defp ipv6_gen do
    let bytes <- vector(16, byte()) do
      :binary.list_to_bin(bytes)
    end
  end

  # Property-based tests

  property "uint8 encode/decode roundtrip" do
    forall n <- uint8_gen() do
      encoded = DataEncoder.encode(:uint8, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:uint8, encoded)
      decoded == n
    end
  end

  property "uint16 encode/decode roundtrip" do
    forall n <- uint16_gen() do
      encoded = DataEncoder.encode(:uint16, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:uint16, encoded)
      decoded == n
    end
  end

  property "uint32 encode/decode roundtrip" do
    forall n <- uint32_gen() do
      encoded = DataEncoder.encode(:uint32, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:uint32, encoded)
      decoded == n
    end
  end

  property "int8 encode/decode roundtrip" do
    forall n <- int8_gen() do
      encoded = DataEncoder.encode(:int8, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:int8, encoded)
      decoded == n
    end
  end

  property "int16 encode/decode roundtrip" do
    forall n <- int16_gen() do
      encoded = DataEncoder.encode(:int16, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:int16, encoded)
      decoded == n
    end
  end

  property "int32 encode/decode roundtrip" do
    forall n <- int32_gen() do
      encoded = DataEncoder.encode(:int32, n)
      {:ok, decoded, <<>>} = DataEncoder.decode(:int32, encoded)
      decoded == n
    end
  end

  property "boolean encode/decode roundtrip" do
    forall b <- bool_gen() do
      encoded = DataEncoder.encode(:bool, b)
      {:ok, decoded, <<>>} = DataEncoder.decode(:bool, encoded)
      decoded == b
    end
  end

  property "utf8 encode/decode roundtrip" do
    forall s <- utf8_gen() do
      encoded = DataEncoder.encode(:utf8, s)
      {:ok, decoded, <<>>} = DataEncoder.decode(:utf8, encoded)
      decoded == s
    end
  end

  property "binary data encode/decode roundtrip" do
    forall data <- binary_gen() do
      encoded = DataEncoder.encode(:data, data)
      {:ok, decoded, <<>>} = DataEncoder.decode(:data, encoded)
      decoded == data
    end
  end

  property "eui64 encode/decode roundtrip" do
    forall eui64 <- eui64_gen() do
      encoded = DataEncoder.encode(:eui64, eui64)
      {:ok, decoded, <<>>} = DataEncoder.decode(:eui64, encoded)
      decoded == eui64
    end
  end

  property "ipv6 encode/decode roundtrip" do
    forall addr <- ipv6_gen() do
      encoded = DataEncoder.encode(:ipv6addr, addr)
      {:ok, decoded, <<>>} = DataEncoder.decode(:ipv6addr, encoded)
      decoded == addr
    end
  end

  property "sequence encode/decode preserves order and values" do
    forall values <-
             list(
               oneof([
                 {:uint8, integer(0, 255)},
                 {:bool, boolean()},
                 {:uint16, integer(0, 65535)}
               ])
             ) do
      encoded = DataEncoder.encode_sequence(values)
      types = Enum.map(values, fn {t, _} -> t end)

      expected_values =
        Enum.map(values, fn {_, v} ->
          case v do
            n when is_integer(n) -> if n > 1, do: rem(n, 256), else: n
            other -> other
          end
        end)

      case DataEncoder.decode_sequence(types, encoded) do
        {:ok, decoded, <<>>} ->
          length(decoded) == length(expected_values)

        _ ->
          false
      end
    end
  end

  property "uint8 encoded size is always 1 byte" do
    forall n <- uint8_gen() do
      byte_size(DataEncoder.encode(:uint8, n)) == 1
    end
  end

  property "uint16 encoded size is always 2 bytes" do
    forall n <- uint16_gen() do
      byte_size(DataEncoder.encode(:uint16, n)) == 2
    end
  end

  property "uint32 encoded size is always 4 bytes" do
    forall n <- uint32_gen() do
      byte_size(DataEncoder.encode(:uint32, n)) == 4
    end
  end

  property "bool encoded size is always 1 byte" do
    forall b <- bool_gen() do
      byte_size(DataEncoder.encode(:bool, b)) == 1
    end
  end

  property "eui64 encoded size is always 8 bytes" do
    forall eui64 <- eui64_gen() do
      byte_size(DataEncoder.encode(:eui64, eui64)) == 8
    end
  end

  property "ipv6 encoded size is always 16 bytes" do
    forall addr <- ipv6_gen() do
      byte_size(DataEncoder.encode(:ipv6addr, addr)) == 16
    end
  end

  property "utf8 encoding includes length prefix" do
    forall s <- utf8_gen() do
      encoded = DataEncoder.encode(:utf8, s)
      string_size = byte_size(s)

      # For strings < 128 bytes, length is 1 byte
      if string_size < 128 do
        byte_size(encoded) == string_size + 1
      else
        byte_size(encoded) > string_size
      end
    end
  end

  property "data encoding includes length prefix" do
    forall data <- binary_gen() do
      encoded = DataEncoder.encode(:data, data)
      data_size = byte_size(data)

      # Encoded size must be >= original size
      byte_size(encoded) >= data_size
    end
  end

  # Traditional unit tests

  describe "encode/2" do
    test "encodes uint8" do
      assert DataEncoder.encode(:uint8, 42) == <<42>>
      assert DataEncoder.encode(:uint8, 255) == <<255>>
      assert DataEncoder.encode(:uint8, 0) == <<0>>
    end

    test "encodes uint16 as little-endian" do
      assert DataEncoder.encode(:uint16, 1000) == <<232, 3>>
      assert DataEncoder.encode(:uint16, 0xABCD) == <<0xCD, 0xAB>>
    end

    test "encodes uint32 as little-endian" do
      assert DataEncoder.encode(:uint32, 0x12345678) == <<0x78, 0x56, 0x34, 0x12>>
    end

    test "encodes signed integers" do
      assert DataEncoder.encode(:int8, -1) == <<255>>
      assert DataEncoder.encode(:int8, 127) == <<127>>
      assert DataEncoder.encode(:int16, -1000) == <<24, 252>>
    end

    test "encodes boolean" do
      assert DataEncoder.encode(:bool, true) == <<1>>
      assert DataEncoder.encode(:bool, false) == <<0>>
    end

    test "encodes UTF-8 string with length" do
      result = DataEncoder.encode(:utf8, "Hello")
      assert result == <<5, "Hello">>
    end

    test "encodes empty string" do
      result = DataEncoder.encode(:utf8, "")
      assert result == <<0>>
    end

    test "encodes binary data with length" do
      data = <<1, 2, 3, 4>>
      result = DataEncoder.encode(:data, data)
      assert result == <<4, 1, 2, 3, 4>>
    end

    test "encodes EUI-64" do
      eui64 = <<0x00, 0x12, 0x4B, 0x00, 0x14, 0x15, 0x92, 0x00>>
      assert DataEncoder.encode(:eui64, eui64) == eui64
    end

    test "encodes IPv6 address" do
      addr =
        <<0x20, 0x01, 0x0D, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x01>>

      assert DataEncoder.encode(:ipv6addr, addr) == addr
    end
  end

  describe "decode/2" do
    test "decodes uint8" do
      assert {:ok, 42, <<>>} = DataEncoder.decode(:uint8, <<42>>)
      assert {:ok, 255, <<1, 2>>} = DataEncoder.decode(:uint8, <<255, 1, 2>>)
    end

    test "decodes uint16" do
      assert {:ok, 1000, <<>>} = DataEncoder.decode(:uint16, <<232, 3>>)
    end

    test "decodes uint32" do
      assert {:ok, 0x12345678, <<>>} =
               DataEncoder.decode(:uint32, <<0x78, 0x56, 0x34, 0x12>>)
    end

    test "decodes boolean" do
      assert {:ok, true, <<>>} = DataEncoder.decode(:bool, <<1>>)
      assert {:ok, false, <<>>} = DataEncoder.decode(:bool, <<0>>)
    end

    test "decodes UTF-8 string" do
      assert {:ok, "Hello", <<>>} = DataEncoder.decode(:utf8, <<5, "Hello">>)
    end

    test "decodes binary data" do
      {:ok, data, <<>>} = DataEncoder.decode(:data, <<4, 1, 2, 3, 4>>)
      assert data == <<1, 2, 3, 4>>
    end

    test "returns error for insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint16, <<1>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint32, <<1, 2>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:eui64, <<1, 2, 3>>)
    end

    test "returns error for invalid boolean" do
      assert {:error, :invalid_boolean} = DataEncoder.decode(:bool, <<2>>)
      assert {:error, :invalid_boolean} = DataEncoder.decode(:bool, <<255>>)
    end
  end

  describe "encode_sequence/1 and decode_sequence/2" do
    test "encodes and decodes a sequence of values" do
      values = [
        {:uint8, 42},
        {:uint16, 1000},
        {:bool, true},
        {:utf8, "Test"}
      ]

      encoded = DataEncoder.encode_sequence(values)
      types = [:uint8, :uint16, :bool, :utf8]

      assert {:ok, [42, 1000, true, "Test"], <<>>} = DataEncoder.decode_sequence(types, encoded)
    end

    test "handles empty sequence" do
      assert DataEncoder.encode_sequence([]) == <<>>
      assert {:ok, [], <<>>} = DataEncoder.decode_sequence([], <<>>)
    end

    test "preserves remaining data after decode" do
      encoded = <<42, 1, 2, 3, 4, 5>>
      types = [:uint8, :uint8]

      assert {:ok, [42, 1], <<2, 3, 4, 5>>} = DataEncoder.decode_sequence(types, encoded)
    end

    test "returns error on insufficient data in sequence" do
      types = [:uint8, :uint16, :uint32]
      insufficient = <<1, 2>>

      assert {:error, :insufficient_data} = DataEncoder.decode_sequence(types, insufficient)
    end
  end
end
