defmodule NTBR.Domain.Spinel.DataEncoderTest do
  @moduledoc """
  Tests for Spinel DataEncoder module.

  Tests encoding and decoding of all Spinel data types including:
  - Integer types (UINT8, UINT16, UINT32, INT8, INT16, INT32)
  - Boolean
  - UTF-8 strings
  - Binary data
  - EUI-64
  - IPv6 addresses
  - Packed length encoding
  """
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.DataEncoder

  # ============================================================================
  # UINT8 TESTS
  # ============================================================================

  describe "encode/decode :uint8" do
    test "encodes valid uint8 values" do
      assert DataEncoder.encode(:uint8, 0) == <<0>>
      assert DataEncoder.encode(:uint8, 42) == <<42>>
      assert DataEncoder.encode(:uint8, 255) == <<255>>
    end

    test "decodes uint8 values" do
      assert {:ok, 0, <<>>} = DataEncoder.decode(:uint8, <<0>>)
      assert {:ok, 42, <<>>} = DataEncoder.decode(:uint8, <<42>>)
      assert {:ok, 255, <<>>} = DataEncoder.decode(:uint8, <<255>>)
      assert {:ok, 42, <<1, 2>>} = DataEncoder.decode(:uint8, <<42, 1, 2>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint8, <<>>)
    end

    property "uint8 encode/decode roundtrip" do
      forall value <- integer(0, 255) do
        encoded = DataEncoder.encode(:uint8, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:uint8, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # UINT16 TESTS
  # ============================================================================

  describe "encode/decode :uint16" do
    test "encodes valid uint16 values (little endian)" do
      assert DataEncoder.encode(:uint16, 0) == <<0, 0>>
      assert DataEncoder.encode(:uint16, 256) == <<0, 1>>
      assert DataEncoder.encode(:uint16, 1000) == <<232, 3>>
      assert DataEncoder.encode(:uint16, 65535) == <<255, 255>>
    end

    test "decodes uint16 values" do
      assert {:ok, 0, <<>>} = DataEncoder.decode(:uint16, <<0, 0>>)
      assert {:ok, 256, <<>>} = DataEncoder.decode(:uint16, <<0, 1>>)
      assert {:ok, 1000, <<>>} = DataEncoder.decode(:uint16, <<232, 3>>)
      assert {:ok, 65535, <<>>} = DataEncoder.decode(:uint16, <<255, 255>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint16, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint16, <<1>>)
    end

    property "uint16 encode/decode roundtrip" do
      forall value <- integer(0, 65535) do
        encoded = DataEncoder.encode(:uint16, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:uint16, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # UINT32 TESTS
  # ============================================================================

  describe "encode/decode :uint32" do
    test "encodes valid uint32 values (little endian)" do
      assert DataEncoder.encode(:uint32, 0) == <<0, 0, 0, 0>>
      assert DataEncoder.encode(:uint32, 256) == <<0, 1, 0, 0>>
      assert DataEncoder.encode(:uint32, 0x12345678) == <<0x78, 0x56, 0x34, 0x12>>
      assert DataEncoder.encode(:uint32, 4_294_967_295) == <<255, 255, 255, 255>>
    end

    test "decodes uint32 values" do
      assert {:ok, 0, <<>>} = DataEncoder.decode(:uint32, <<0, 0, 0, 0>>)
      assert {:ok, 256, <<>>} = DataEncoder.decode(:uint32, <<0, 1, 0, 0>>)
      assert {:ok, 0x12345678, <<>>} = DataEncoder.decode(:uint32, <<0x78, 0x56, 0x34, 0x12>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint32, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:uint32, <<1, 2, 3>>)
    end

    property "uint32 encode/decode roundtrip" do
      forall value <- integer(0, 4_294_967_295) do
        encoded = DataEncoder.encode(:uint32, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:uint32, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # INT8 TESTS
  # ============================================================================

  describe "encode/decode :int8" do
    test "encodes valid int8 values" do
      assert DataEncoder.encode(:int8, -128) == <<128>>
      assert DataEncoder.encode(:int8, -1) == <<255>>
      assert DataEncoder.encode(:int8, 0) == <<0>>
      assert DataEncoder.encode(:int8, 1) == <<1>>
      assert DataEncoder.encode(:int8, 127) == <<127>>
    end

    test "decodes int8 values" do
      assert {:ok, -128, <<>>} = DataEncoder.decode(:int8, <<128>>)
      assert {:ok, -1, <<>>} = DataEncoder.decode(:int8, <<255>>)
      assert {:ok, 0, <<>>} = DataEncoder.decode(:int8, <<0>>)
      assert {:ok, 127, <<>>} = DataEncoder.decode(:int8, <<127>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:int8, <<>>)
    end

    property "int8 encode/decode roundtrip" do
      forall value <- integer(-128, 127) do
        encoded = DataEncoder.encode(:int8, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:int8, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # INT16 TESTS
  # ============================================================================

  describe "encode/decode :int16" do
    test "encodes valid int16 values (little endian signed)" do
      assert DataEncoder.encode(:int16, -32768) == <<0, 128>>
      assert DataEncoder.encode(:int16, -1) == <<255, 255>>
      assert DataEncoder.encode(:int16, 0) == <<0, 0>>
      assert DataEncoder.encode(:int16, 1) == <<1, 0>>
      assert DataEncoder.encode(:int16, 32767) == <<255, 127>>
    end

    test "decodes int16 values" do
      assert {:ok, -32768, <<>>} = DataEncoder.decode(:int16, <<0, 128>>)
      assert {:ok, -1, <<>>} = DataEncoder.decode(:int16, <<255, 255>>)
      assert {:ok, 0, <<>>} = DataEncoder.decode(:int16, <<0, 0>>)
      assert {:ok, 32767, <<>>} = DataEncoder.decode(:int16, <<255, 127>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:int16, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:int16, <<1>>)
    end

    property "int16 encode/decode roundtrip" do
      forall value <- integer(-32768, 32767) do
        encoded = DataEncoder.encode(:int16, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:int16, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # INT32 TESTS
  # ============================================================================

  describe "encode/decode :int32" do
    test "encodes valid int32 values (little endian signed)" do
      assert DataEncoder.encode(:int32, -2_147_483_648) == <<0, 0, 0, 128>>
      assert DataEncoder.encode(:int32, -1) == <<255, 255, 255, 255>>
      assert DataEncoder.encode(:int32, 0) == <<0, 0, 0, 0>>
      assert DataEncoder.encode(:int32, 1) == <<1, 0, 0, 0>>
      assert DataEncoder.encode(:int32, 2_147_483_647) == <<255, 255, 255, 127>>
    end

    test "decodes int32 values" do
      assert {:ok, -2_147_483_648, <<>>} = DataEncoder.decode(:int32, <<0, 0, 0, 128>>)
      assert {:ok, -1, <<>>} = DataEncoder.decode(:int32, <<255, 255, 255, 255>>)
      assert {:ok, 0, <<>>} = DataEncoder.decode(:int32, <<0, 0, 0, 0>>)
      assert {:ok, 2_147_483_647, <<>>} = DataEncoder.decode(:int32, <<255, 255, 255, 127>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:int32, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:int32, <<1, 2, 3>>)
    end

    property "int32 encode/decode roundtrip" do
      forall value <- integer(-2_147_483_648, 2_147_483_647) do
        encoded = DataEncoder.encode(:int32, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:int32, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # BOOL TESTS
  # ============================================================================

  describe "encode/decode :bool" do
    test "encodes boolean values" do
      assert DataEncoder.encode(:bool, true) == <<1>>
      assert DataEncoder.encode(:bool, false) == <<0>>
    end

    test "decodes boolean values" do
      assert {:ok, true, <<>>} = DataEncoder.decode(:bool, <<1>>)
      assert {:ok, false, <<>>} = DataEncoder.decode(:bool, <<0>>)
      assert {:ok, true, <<99>>} = DataEncoder.decode(:bool, <<1, 99>>)
    end

    test "decode returns error with invalid boolean" do
      assert {:error, :invalid_boolean} = DataEncoder.decode(:bool, <<2>>)
      assert {:error, :invalid_boolean} = DataEncoder.decode(:bool, <<255>>)
      assert {:error, :invalid_boolean} = DataEncoder.decode(:bool, <<>>)
    end

    test "raises error for non-boolean encode" do
      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:bool, "not a bool")
      end

      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:bool, 1)
      end
    end

    property "bool encode/decode roundtrip" do
      forall value <- boolean() do
        encoded = DataEncoder.encode(:bool, value)
        {:ok, decoded, <<>>} = DataEncoder.decode(:bool, encoded)
        decoded == value
      end
    end
  end

  # ============================================================================
  # UTF8 TESTS
  # ============================================================================

  describe "encode/decode :utf8" do
    test "encodes UTF-8 strings with packed length" do
      # Empty string
      assert DataEncoder.encode(:utf8, "") == <<0>>

      # Short strings (length < 128)
      assert DataEncoder.encode(:utf8, "Hello") == <<5, "Hello"::binary>>
      assert DataEncoder.encode(:utf8, "Thread") == <<6, "Thread"::binary>>
    end

    test "decodes UTF-8 strings" do
      assert {:ok, "", <<>>} = DataEncoder.decode(:utf8, <<0>>)
      assert {:ok, "Hello", <<>>} = DataEncoder.decode(:utf8, <<5, "Hello"::binary>>)
      assert {:ok, "Thread", <<>>} = DataEncoder.decode(:utf8, <<6, "Thread"::binary>>)
    end

    test "decode handles remaining data" do
      assert {:ok, "Hi", <<1, 2, 3>>} = DataEncoder.decode(:utf8, <<2, "Hi", 1, 2, 3>>)
    end

    test "decode returns error with invalid UTF-8" do
      # Invalid UTF-8 sequence
      assert {:error, :invalid_utf8} = DataEncoder.decode(:utf8, <<3, 0xFF, 0xFE, 0xFD>>)
    end

    test "raises error for invalid UTF-8 encode" do
      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:utf8, <<0xFF, 0xFE>>)
      end
    end

    property "utf8 encode/decode roundtrip" do
      forall string <- utf8() do
        encoded = DataEncoder.encode(:utf8, string)
        {:ok, decoded, <<>>} = DataEncoder.decode(:utf8, encoded)
        decoded == string
      end
    end
  end

  # ============================================================================
  # DATA (BINARY) TESTS
  # ============================================================================

  describe "encode/decode :data" do
    test "encodes binary data with packed length" do
      assert DataEncoder.encode(:data, <<>>) == <<0>>
      assert DataEncoder.encode(:data, <<1, 2, 3>>) == <<3, 1, 2, 3>>
      assert DataEncoder.encode(:data, <<0xFF, 0xAA>>) == <<2, 0xFF, 0xAA>>
    end

    test "decodes binary data" do
      assert {:ok, <<>>, <<>>} = DataEncoder.decode(:data, <<0>>)
      assert {:ok, <<1, 2, 3>>, <<>>} = DataEncoder.decode(:data, <<3, 1, 2, 3>>)
      assert {:ok, <<0xFF, 0xAA>>, <<>>} = DataEncoder.decode(:data, <<2, 0xFF, 0xAA>>)
    end

    test "decode handles remaining data" do
      assert {:ok, <<1, 2>>, <<99, 100>>} =
               DataEncoder.decode(:data, <<2, 1, 2, 99, 100>>)
    end

    property "data encode/decode roundtrip" do
      forall data <- binary() do
        # Limit size for reasonable test times
        data = binary_part(data, 0, min(byte_size(data), 100))
        encoded = DataEncoder.encode(:data, data)
        {:ok, decoded, <<>>} = DataEncoder.decode(:data, encoded)
        decoded == data
      end
    end
  end

  # ============================================================================
  # EUI64 TESTS
  # ============================================================================

  describe "encode/decode :eui64" do
    test "encodes EUI-64 addresses" do
      eui64 = <<0x00, 0x12, 0x4B, 0x00, 0x14, 0x32, 0x16, 0x78>>
      assert DataEncoder.encode(:eui64, eui64) == eui64
    end

    test "decodes EUI-64 addresses" do
      eui64 = <<0x00, 0x12, 0x4B, 0x00, 0x14, 0x32, 0x16, 0x78>>
      assert {:ok, ^eui64, <<>>} = DataEncoder.decode(:eui64, eui64)
      assert {:ok, ^eui64, <<99>>} = DataEncoder.decode(:eui64, eui64 <> <<99>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:eui64, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:eui64, <<1, 2, 3, 4, 5, 6, 7>>)
    end

    test "raises error for wrong size EUI-64 encode" do
      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:eui64, <<1, 2, 3>>)
      end

      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:eui64, <<1, 2, 3, 4, 5, 6, 7, 8, 9>>)
      end
    end

    property "eui64 encode/decode roundtrip" do
      forall _ <- integer(1, 100) do
        eui64 = :crypto.strong_rand_bytes(8)
        encoded = DataEncoder.encode(:eui64, eui64)
        {:ok, decoded, <<>>} = DataEncoder.decode(:eui64, encoded)
        decoded == eui64
      end
    end
  end

  # ============================================================================
  # IPv6 ADDRESS TESTS
  # ============================================================================

  describe "encode/decode :ipv6addr" do
    test "encodes IPv6 addresses" do
      ipv6 = <<0xFD, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0, 0, 0, 0, 0, 0, 0, 1>>
      assert DataEncoder.encode(:ipv6addr, ipv6) == ipv6
    end

    test "decodes IPv6 addresses" do
      ipv6 = <<0xFD, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0, 0, 0, 0, 0, 0, 0, 1>>
      assert {:ok, ^ipv6, <<>>} = DataEncoder.decode(:ipv6addr, ipv6)
      assert {:ok, ^ipv6, <<99>>} = DataEncoder.decode(:ipv6addr, ipv6 <> <<99>>)
    end

    test "decode returns error with insufficient data" do
      assert {:error, :insufficient_data} = DataEncoder.decode(:ipv6addr, <<>>)
      assert {:error, :insufficient_data} = DataEncoder.decode(:ipv6addr, <<1, 2, 3, 4, 5>>)
    end

    test "raises error for wrong size IPv6 encode" do
      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:ipv6addr, <<1, 2, 3>>)
      end

      assert_raise ArgumentError, fn ->
        DataEncoder.encode(:ipv6addr, :crypto.strong_rand_bytes(20))
      end
    end

    property "ipv6addr encode/decode roundtrip" do
      forall _ <- integer(1, 100) do
        ipv6 = :crypto.strong_rand_bytes(16)
        encoded = DataEncoder.encode(:ipv6addr, ipv6)
        {:ok, decoded, <<>>} = DataEncoder.decode(:ipv6addr, encoded)
        decoded == ipv6
      end
    end
  end

  # ============================================================================
  # SEQUENCE TESTS
  # ============================================================================

  describe "encode_sequence/1 and decode_sequence/2" do
    test "encodes sequence of values" do
      sequence = [
        {:uint8, 42},
        {:uint16, 1000},
        {:bool, true},
        {:utf8, "Test"}
      ]

      result = DataEncoder.encode_sequence(sequence)
      # 42 + 232,3 + 1 + 4,"Test"
      assert result == <<42, 232, 3, 1, 4, "Test"::binary>>
    end

    test "decodes sequence of values" do
      binary = <<42, 232, 3, 1, 4, "Test"::binary>>
      types = [:uint8, :uint16, :bool, :utf8]

      assert {:ok, [42, 1000, true, "Test"], <<>>} =
               DataEncoder.decode_sequence(types, binary)
    end

    test "decode handles remaining data" do
      binary = <<42, 1, 99, 100>>
      types = [:uint8, :bool]

      assert {:ok, [42, true], <<99, 100>>} =
               DataEncoder.decode_sequence(types, binary)
    end

    test "decode returns error on first failure" do
      binary = <<42>>
      types = [:uint8, :uint16]

      assert {:error, :insufficient_data} = DataEncoder.decode_sequence(types, binary)
    end

    test "empty sequence" do
      assert DataEncoder.encode_sequence([]) == <<>>
      assert {:ok, [], <<1, 2>>} = DataEncoder.decode_sequence([], <<1, 2>>)
    end

    property "sequence encode/decode roundtrip" do
      forall values <- sequence_gen() do
        encoded = DataEncoder.encode_sequence(values)
        types = Enum.map(values, fn {type, _} -> type end)
        expected_values = Enum.map(values, fn {_, value} -> value end)

        {:ok, decoded, <<>>} = DataEncoder.decode_sequence(types, encoded)
        decoded == expected_values
      end
    end
  end

  # ============================================================================
  # HELPER FUNCTION TESTS
  # ============================================================================

  describe "encode_uint8/1 and encode_uint16/1" do
    test "encode_uint8 encodes correctly" do
      assert DataEncoder.encode_uint8(0) == <<0>>
      assert DataEncoder.encode_uint8(42) == <<42>>
      assert DataEncoder.encode_uint8(255) == <<255>>
    end

    test "encode_uint16 encodes correctly (little endian)" do
      assert DataEncoder.encode_uint16(0) == <<0, 0>>
      assert DataEncoder.encode_uint16(256) == <<0, 1>>
      assert DataEncoder.encode_uint16(1000) == <<232, 3>>
      assert DataEncoder.encode_uint16(0xFFFF) == <<255, 255>>
    end
  end

  # ============================================================================
  # PROPERTY TEST GENERATORS
  # ============================================================================

  defp sequence_gen do
    # Generate a list of mixed type/value pairs
    let count <- integer(1, 5) do
      Enum.map(1..count, fn _ ->
        oneof([
          {:uint8, integer(0, 255)},
          {:uint16, integer(0, 65535)},
          {:bool, boolean()},
          {:int8, integer(-128, 127)}
        ])
      end)
    end
  end
end
