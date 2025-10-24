defmodule NTBR.Domain.Spinel.DataEncoder do
  @moduledoc """
  Encodes and decodes Spinel data types with Elixir 1.18 type system.

  Spinel data format encoding:
  - UINT8: 1 byte unsigned integer (0..255)
  - UINT16: 2 bytes little-endian (0..65535)
  - UINT32: 4 bytes little-endian (0..4_294_967_295)
  - INT8: 1 byte signed integer (-128..127)
  - INT16: 2 bytes little-endian signed (-32768..32767)
  - INT32: 4 bytes little-endian signed
  - BOOL: 1 byte (0 or 1)
  - UTF8: Length-prefixed UTF-8 string
  - DATA: Length-prefixed binary data
  - EUI64: 8 bytes IEEE EUI-64
  - IPv6: 16 bytes IPv6 address
  """
  import Bitwise

  # Refined types with exact ranges
  @type uint8 :: 0..255
  @type uint16 :: 0..65535
  @type uint32 :: 0..4_294_967_295
  @type int8 :: -128..127
  @type int16 :: -32768..32767
  @type int32 :: -2_147_483_648..2_147_483_647

  @typedoc "8-byte EUI-64 address"
  @type eui64 :: <<_::64>>

  @typedoc "16-byte IPv6 address"
  @type ipv6_addr :: <<_::128>>

  @typedoc "Supported data types for encoding/decoding"
  @type data_type ::
          :uint8
          | :uint16
          | :uint32
          | :int8
          | :int16
          | :int32
          | :bool
          | :utf8
          | :data
          | :eui64
          | :ipv6addr

  @typedoc "Values that can be encoded"
  @type encodable_value ::
          uint8()
          | uint16()
          | uint32()
          | int8()
          | int16()
          | int32()
          | boolean()
          | String.t()
          | binary()

  @typedoc "Possible decode errors"
  @type decode_error ::
          :insufficient_data
          | :invalid_boolean
          | :invalid_utf8
          | :invalid_data
          | :invalid_packed_length

  @typedoc "Result of decoding with remaining bytes"
  @type decode_result :: {:ok, encodable_value(), binary()} | {:error, decode_error()}

  # Encoding functions with strict type guards

  @doc """
  Encodes a value according to its type with compile-time type checking.

  ## Examples

      iex> DataEncoder.encode(:uint8, 42)
      <<42>>
      
      iex> DataEncoder.encode(:uint16, 1000)
      <<232, 3>>
      
      iex> DataEncoder.encode(:bool, true)
      <<1>>
  """
  @spec encode(data_type(), encodable_value()) :: binary()

  def encode(:uint8, value) when is_integer(value) and value in 0..255 do
    <<value::8>>
  end

  def encode(:uint16, value) when is_integer(value) and value in 0..65535 do
    <<value::little-16>>
  end

  def encode(:uint32, value) when is_integer(value) and value in 0..4_294_967_295 do
    <<value::little-32>>
  end

  def encode(:int8, value) when is_integer(value) and value in -128..127 do
    <<value::signed-8>>
  end

  def encode(:int16, value) when is_integer(value) and value in -32768..32767 do
    <<value::little-signed-16>>
  end

  def encode(:int32, value)
      when is_integer(value) and value in -2_147_483_648..2_147_483_647 do
    <<value::little-signed-32>>
  end

  def encode(:bool, true), do: <<1::8>>
  def encode(:bool, false), do: <<0::8>>

  def encode(:bool, _) do
    raise ArgumentError,
          "An bool has to be either true or false"
  end

  def encode(:utf8, string) when is_binary(string) do
    # Verify it's valid UTF-8
    unless String.valid?(string) do
      raise ArgumentError, "Invalid UTF-8 string"
    end

    length = byte_size(string)
    encode_packed_length(length) <> string
  end

  def encode(:data, binary) when is_binary(binary) do
    length = byte_size(binary)
    encode_packed_length(length) <> binary
  end

  def encode(:eui64, <<_::64>> = eui64) do
    eui64
  end

  def encode(:eui64, other) do
    raise ArgumentError,
          "EUI-64 must be exactly 8 bytes, got #{byte_size(other)} bytes"
  end

  def encode(:ipv6addr, <<_::128>> = addr) do
    addr
  end

  def encode(:ipv6addr, other) do
    raise ArgumentError,
          "IPv6 address must be exactly 16 bytes, got #{byte_size(other)} bytes"
  end

  @doc """
  Encodes multiple values in sequence.

  ## Examples

      iex> DataEncoder.encode_sequence([
      ...>   {:uint8, 42},
      ...>   {:uint16, 1000},
      ...>   {:bool, true}
      ...> ])
      <<42, 232, 3, 1>>
  """
  @spec encode_sequence([{data_type(), encodable_value()}]) :: binary()
  def encode_sequence(types_and_values) when is_list(types_and_values) do
    types_and_values
    |> Enum.map(fn {type, value} -> encode(type, value) end)
    |> IO.iodata_to_binary()
  end

  # Decoding functions with explicit result types

  @doc """
  Decodes a value from binary data.

  Returns `{:ok, value, rest}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> DataEncoder.decode(:uint8, <<42, 1, 2>>)
      {:ok, 42, <<1, 2>>}
      
      iex> DataEncoder.decode(:uint16, <<232, 3>>)
      {:ok, 1000, <<>>}
  """
  @spec decode(data_type(), binary()) :: decode_result()

  def decode(:uint8, <<value::8, rest::binary>>) when value in 0..255 do
    {:ok, value, rest}
  end

  def decode(:uint8, _), do: {:error, :insufficient_data}

  def decode(:uint16, <<value::little-16, rest::binary>>) when value in 0..65535 do
    {:ok, value, rest}
  end

  def decode(:uint16, _), do: {:error, :insufficient_data}

  def decode(:uint32, <<value::little-32, rest::binary>>)
      when value in 0..4_294_967_295 do
    {:ok, value, rest}
  end

  def decode(:uint32, _), do: {:error, :insufficient_data}

  def decode(:int8, <<value::signed-8, rest::binary>>) when value in -128..127 do
    {:ok, value, rest}
  end

  def decode(:int8, _), do: {:error, :insufficient_data}

  def decode(:int16, <<value::little-signed-16, rest::binary>>)
      when value in -32768..32767 do
    {:ok, value, rest}
  end

  def decode(:int16, _), do: {:error, :insufficient_data}

  def decode(:int32, <<value::little-signed-32, rest::binary>>)
      when value in -2_147_483_648..2_147_483_647 do
    {:ok, value, rest}
  end

  def decode(:int32, _), do: {:error, :insufficient_data}

  def decode(:bool, <<1::8, rest::binary>>), do: {:ok, true, rest}
  def decode(:bool, <<0::8, rest::binary>>), do: {:ok, false, rest}
  def decode(:bool, _), do: {:error, :invalid_boolean}

  def decode(:utf8, data) when is_binary(data) do
    with {:ok, length, rest} <- decode_packed_length(data),
         <<string::binary-size(length), rest2::binary>> <- rest,
         true <- String.valid?(string) do
      {:ok, string, rest2}
    else
      false -> {:error, :invalid_utf8}
      _ -> {:error, :invalid_utf8}
    end
  end

  def decode(:data, data) when is_binary(data) do
    with {:ok, length, rest} <- decode_packed_length(data),
         <<binary::binary-size(length), rest2::binary>> <- rest do
      {:ok, binary, rest2}
    else
      _ -> {:error, :invalid_data}
    end
  end

  def decode(:eui64, <<eui64::64-bitstring, rest::binary>>) do
    {:ok, eui64, rest}
  end

  def decode(:eui64, _), do: {:error, :insufficient_data}

  def decode(:ipv6addr, <<addr::128-bitstring, rest::binary>>) do
    {:ok, addr, rest}
  end

  def decode(:ipv6addr, _), do: {:error, :insufficient_data}

  @doc """
  Decodes a sequence of values from binary data.

  Stops at the first decoding error or when all types are decoded.
  """
  @spec decode_sequence([data_type()], binary()) ::
          {:ok, [encodable_value()], binary()} | {:error, decode_error()}
  def decode_sequence(types, binary) when is_list(types) and is_binary(binary) do
    decode_sequence_iter(types, binary, [])
  end

  @spec decode_sequence_iter([data_type()], binary(), [encodable_value()]) ::
          {:ok, [encodable_value()], binary()} | {:error, decode_error()}
  defp decode_sequence_iter([], rest, acc) when is_binary(rest) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp decode_sequence_iter([type | types], binary, acc) when is_binary(binary) do
    case decode(type, binary) do
      {:ok, value, rest} ->
        decode_sequence_iter(types, rest, [value | acc])

      {:error, _} = error ->
        error
    end
  end

  # Packed length encoding (VLQ - Variable-Length Quantity)

  @spec encode_packed_length(non_neg_integer()) :: binary()
  defp encode_packed_length(length) when is_integer(length) and length >= 0 and length < 128 do
    <<length::8>>
  end

  defp encode_packed_length(length) when is_integer(length) and length >= 128 do
    encode_packed_length_multi(length, [])
  end

  @spec encode_packed_length_multi(non_neg_integer(), [binary()]) :: binary()
  defp encode_packed_length_multi(0, acc) when is_list(acc) do
    acc
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp encode_packed_length_multi(length, acc)
       when is_integer(length) and length > 0 and is_list(acc) do
    has_more = length > 127
    byte = (length &&& 0x7F) ||| if has_more, do: 0x80, else: 0x00
    encode_packed_length_multi(length >>> 7, [<<byte::8>> | acc])
  end

  @spec decode_packed_length(binary()) ::
          {:ok, non_neg_integer(), binary()} | {:error, :invalid_packed_length}
  defp decode_packed_length(binary) when is_binary(binary) do
    decode_packed_length_iter(binary, 0, 0)
  end

  @spec decode_packed_length_iter(binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer(), binary()} | {:error, :invalid_packed_length}
  defp decode_packed_length_iter(<<byte::8, rest::binary>>, acc, shift)
       when is_integer(acc) and is_integer(shift) and shift < 32 do
    value = byte &&& 0x7F
    new_acc = acc ||| value <<< shift

    if (byte &&& 0x80) != 0 do
      decode_packed_length_iter(rest, new_acc, shift + 7)
    else
      {:ok, new_acc, rest}
    end
  end

  defp decode_packed_length_iter(_, _, _) do
    {:error, :invalid_packed_length}
  end

  @doc "Encode unsigned 8-bit integer"
  @spec encode_uint8(non_neg_integer()) :: binary()
  def encode_uint8(value) when value >= 0 and value <= 255 do
    <<value::8>>
  end
  
  @doc "Encode unsigned 16-bit integer (little endian)"
  @spec encode_uint16(non_neg_integer()) :: binary()
  def encode_uint16(value) when value >= 0 and value <= 0xFFFF do
    <<value::little-16>>
  end




end
