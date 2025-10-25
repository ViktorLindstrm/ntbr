defmodule NTBR.TestSupport.Generators do
  @moduledoc """
  Shared property-based test generators for BorderRouter tests.
  """

  import PropCheck

  # Spinel Frame Generators

  @doc """
  Generates valid TID values (0-15).
  """
  @spec tid() :: PropCheck.type()
  def tid, do: integer(0, 15)

  @doc """
  Generates valid Spinel commands.
  """
  @spec command() :: PropCheck.type()
  def command do
    alias NTBR.Domain.Spinel.Command
    oneof(Command.all())
  end

  @doc """
  Generates valid Spinel properties.
  """
  @spec property() :: PropCheck.type()
  def property do
    alias NTBR.Domain.Spinel.Property
    oneof(Property.all())
  end

  @doc """
  Generates arbitrary payload data.
  """
  @spec payload() :: PropCheck.type()
  def payload, do: binary()

  @doc """
  Generates a complete Spinel frame.
  """
  @spec frame() :: PropCheck.type()
  def frame do
    let [cmd <- command(), t <- tid(), p <- payload()] do
      NTBR.Domain.Spinel.Frame.new(cmd, p, tid: t)
    end
  end

  # Data Type Generators

  @doc """
  Generates uint8 values (0-255).
  """
  @spec uint8() :: PropCheck.type()
  def uint8, do: integer(0, 255)

  @doc """
  Generates uint16 values (0-65535).
  """
  @spec uint16() :: PropCheck.type()
  def uint16, do: integer(0, 65535)

  @doc """
  Generates uint32 values.
  """
  @spec uint32() :: PropCheck.type()
  def uint32, do: integer(0, 4_294_967_295)

  @doc """
  Generates int8 values (-128 to 127).
  """
  @spec int8() :: PropCheck.type()
  def int8, do: integer(-128, 127)

  @doc """
  Generates int16 values.
  """
  @spec int16() :: PropCheck.type()
  def int16, do: integer(-32768, 32767)

  @doc """
  Generates int32 values.
  """
  @spec int32() :: PropCheck.type()
  def int32, do: integer(-2_147_483_648, 2_147_483_647)

  @doc """
  Generates valid Thread channels (11-26).
  """
  @spec thread_channel() :: PropCheck.type()
  def thread_channel, do: integer(11, 26)

  @doc """
  Generates valid PAN IDs (0x0000-0xFFFF).
  """
  @spec pan_id() :: PropCheck.type()
  def pan_id, do: integer(0, 0xFFFF)

  @doc """
  Generates EUI-64 addresses (8 bytes).
  """
  @spec eui64() :: PropCheck.type()
  def eui64 do
    let bytes <- vector(8, byte()) do
      :binary.list_to_bin(bytes)
    end
  end

  @doc """
  Generates IPv6 addresses (16 bytes).
  """
  @spec ipv6_addr() :: PropCheck.type()
  def ipv6_addr do
    let bytes <- vector(16, byte()) do
      :binary.list_to_bin(bytes)
    end
  end

  @doc """
  Generates binary data with special HDLC bytes.
  """
  @spec hdlc_special_payload() :: PropCheck.type()
  def hdlc_special_payload do
    let bytes <-
          list(
            oneof([
              byte(),
              # FLAG
              exactly(0x7E),
              # ESCAPE
              exactly(0x7D),
              # XON
              exactly(0x11),
              # XOFF
              exactly(0x13)
            ])
          ) do
      :binary.list_to_bin(bytes)
    end
  end

  @doc """
  Generates UTF-8 strings of various lengths.
  """
  @spec utf8_string() :: PropCheck.type()
  def utf8_string do
    oneof([
      # Empty
      exactly(""),
      # Short
      utf8(max_size: 10),
      # Medium
      utf8(max_size: 100),
      # Long
      utf8(max_size: 1000)
    ])
  end

  @doc """
  Generates data encoder type/value pairs.
  """
  @spec data_type_value() :: PropCheck.type()
  def data_type_value do
    oneof([
      {:uint8, uint8()},
      {:uint16, uint16()},
      {:uint32, uint32()},
      {:int8, int8()},
      {:int16, int16()},
      {:int32, int32()},
      {:bool, boolean()},
      {:utf8, utf8_string()},
      {:data, binary()},
      {:eui64, eui64()},
      {:ipv6addr, ipv6_addr()}
    ])
  end

  @doc """
  Generates a sequence of data type/value pairs.
  """
  @spec data_sequence(pos_integer()) :: PropCheck.type()
  def data_sequence(max_length \\ 10) do
    let len <- integer(0, max_length) do
      vector(len, data_type_value())
    end
  end
end

defmodule NTBR.TestSupport.Helpers do
  @moduledoc """
  Helper functions for NTBR tests.
  """

  alias NTBR.Domain.Spinel.{Frame, DataEncoder, Property}
  # Note: HDLC is infrastructure-level and not available in domain tests
  # alias NTBR.Infrastructure.RCP.SerialPort.HDLC

  @doc """
  Creates a mock Spinel frame with specified parameters.
  """
  @spec mock_frame(keyword()) :: Frame.t()
  def mock_frame(opts \\ []) do
    command = Keyword.get(opts, :command, :reset)
    tid = Keyword.get(opts, :tid, 0)
    payload = Keyword.get(opts, :payload, <<>>)

    Frame.new(command, payload, tid: tid)
  end

  @doc """
  Creates a property value response frame.
  """
  @spec mock_property_response(Property.property(), binary(), keyword()) :: Frame.t()
  def mock_property_response(property, value, opts \\ []) do
    tid = Keyword.get(opts, :tid, 0)
    prop_id = Property.to_id(property)

    Frame.new(:prop_value_is, <<prop_id>> <> value, tid: tid)
  end

  # @doc """
  # Encodes and frames data as it would be sent over serial.
  # """
  # @spec encode_for_serial(Frame.t()) :: binary()
  # def encode_for_serial(%Frame{} = frame) do
  #   frame
  #   |> Frame.encode()
  #   |> HDLC.encode()
  # end

  @doc """
  Verifies a frame roundtrip (encode -> decode).
  """
  @spec verify_roundtrip(Frame.t()) :: boolean()
  def verify_roundtrip(%Frame{} = frame) do
    encoded = Frame.encode(frame)

    case Frame.decode(encoded) do
      {:ok, decoded} ->
        decoded.command == frame.command and
          decoded.tid == frame.tid and
          decoded.payload == frame.payload

      {:error, _} ->
        false
    end
  end

  # @doc """
  # Verifies HDLC roundtrip (encode -> decode).
  # """
  # @spec verify_hdlc_roundtrip(binary()) :: boolean()
  # def verify_hdlc_roundtrip(payload) when is_binary(payload) do
  #   encoded = HDLC.encode(payload)
  #
  #   case HDLC.decode(encoded) do
  #     {:ok, ^payload} -> true
  #     _ -> false
  #   end
  # end

  @doc """
  Extracts property value from a frame response.
  """
  @spec extract_property_value(Frame.t(), DataEncoder.data_type()) ::
          {:ok, term()} | {:error, term()}
  def extract_property_value(%Frame{} = frame, type) do
    with {:ok, payload} <- Frame.extract_value(frame),
         {:ok, value, _rest} <- DataEncoder.decode(type, payload) do
      {:ok, value}
    end
  end

  @doc """
  Creates a test channel value (11-26).
  """
  @spec test_channel() :: 11..26
  def test_channel, do: 15

  @doc """
  Creates a test PAN ID.
  """
  @spec test_pan_id() :: 0..0xFFFF
  def test_pan_id, do: 0xABCD

  @doc """
  Creates a test EUI-64.
  """
  @spec test_eui64() :: binary()
  def test_eui64 do
    <<0x00, 0x12, 0x4B, 0x00, 0x14, 0x15, 0x92, 0x00>>
  end

  @doc """
  Creates a test IPv6 address.
  """
  @spec test_ipv6() :: binary()
  def test_ipv6 do
    # 2001:db8::1
    <<0x20, 0x01, 0x0D, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x01>>
  end

  @doc """
  Waits for a condition to be true with timeout.
  """
  @spec wait_until((-> boolean()), pos_integer(), pos_integer()) :: :ok | :timeout
  def wait_until(condition, timeout \\ 5000, interval \\ 100) do
    wait_until_loop(condition, timeout, interval, System.monotonic_time(:millisecond))
  end

  defp wait_until_loop(condition, timeout, interval, start_time) do
    if condition.() do
      :ok
    else
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed >= timeout do
        :timeout
      else
        Process.sleep(interval)
        wait_until_loop(condition, timeout, interval, start_time)
      end
    end
  end

  # Private helpers - Removed, now using Property module
end
