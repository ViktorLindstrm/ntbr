defmodule NTBR.Domain.Spinel.Frame do
  @moduledoc """
  Spinel protocol frame representation with Elixir 1.18 type system.
  Pure domain logic without any infrastructure dependencies.

  Spinel frame format:
  +----------+--------+-----+--------+----------+
  | Header   | Command| TID | Length | Payload  |
  | (1 byte) |(1 byte)|     |        |          |
  +----------+--------+-----+--------+----------+
  """
  import Bitwise

  alias NTBR.Domain.Spinel.{Command, Property}

  # Strictly refined types
  @typedoc "Transaction ID must be 0-15 (4 bits)"
  @type tid :: 0..15

  @typedoc "Header byte with bit 7 set for host-to-NCP"
  @type header :: 128..143

  @typedoc "Payload is any binary data"
  @type payload :: binary()

  @typedoc "Re-export Command types for convenience"
  @type command :: Command.command()
  @type command_atom :: Command.command_atom()

  @typedoc "Spinel frame structure with enforced keys"
  @type t :: %__MODULE__{
          header: header(),
          command: command(),
          tid: tid(),
          payload: payload()
        }

  @enforce_keys [:header, :command, :tid, :payload]
  defstruct [:header, :command, :tid, :payload]

  @doc """
  Creates a new Spinel frame with validated inputs.

  ## Examples

      iex> Frame.new(:reset, <<>>)
      %Frame{header: 0x80, command: :reset, tid: 0, payload: <<>>}
      
      iex> Frame.new(:prop_value_get, <<0x01>>, tid: 5)
      %Frame{header: 0x85, command: :prop_value_get, tid: 5, payload: <<0x01>>}
      
  ## Errors

  Raises `ArgumentError` if TID is out of range (0-15).
  """
  @spec new(command(), payload(), keyword()) :: t()
  def new(command, payload \\ <<>>, opts \\ [])
      when is_binary(payload) and is_list(opts) do
    tid = Keyword.get(opts, :tid, 0)

    unless is_integer(tid) and tid in 0..15 do
      raise ArgumentError,
            "TID must be an integer in range 0..15, got: #{inspect(tid)}"
    end

    header = build_header(tid)

    %__MODULE__{
      header: header,
      command: command,
      tid: tid,
      payload: payload
    }
  end

  @doc """
  Encodes a frame to binary format for transmission.

  The encoded format is: `<header:8><command:8><payload::binary>`

  ## Examples

      iex> frame = Frame.new(:reset, <<>>)
      iex> Frame.encode(frame)
      <<128, 1>>
  """
  @spec encode(t()) :: <<_::16, _::_*8>>
  def encode(%__MODULE__{header: header, command: command, payload: payload})
      when header in 128..143 and is_binary(payload) do
    command_byte = Command.to_id(command)
    <<header::8, command_byte::8, payload::binary>>
  end

  @doc """
  Decodes a binary frame from the wire.

  Returns `{:ok, frame}` on success or `{:error, :invalid_frame}` if
  the binary data is malformed.

  ## Examples

      iex> Frame.decode(<<128, 1>>)
      {:ok, %Frame{header: 128, command: :reset, tid: 0, payload: <<>>}}
      
      iex> Frame.decode(<<128>>)
      {:error, :invalid_frame}
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, :invalid_frame}
  def decode(<<header::8, command_byte::8, payload::binary>>)
      when header in 128..255 and command_byte in 0..255 do
    {:ok,
     %__MODULE__{
       header: header,
       command: Command.from_id(command_byte),
       tid: extract_tid(header),
       payload: payload
     }}
  end

  def decode(_), do: {:error, :invalid_frame}

  @doc """
  Creates a RESET command frame.

  This resets the NCP to its initial state.
  """
  @spec reset(keyword()) :: t()
  def reset(opts \\ []) when is_list(opts) do
    new(:reset, <<>>, opts)
  end

  @doc """
  Creates a property GET frame.

  Used to read a property value from the NCP.
  """
  @spec prop_value_get(Property.property(), keyword()) :: t()
  def prop_value_get(property, opts \\ []) when is_list(opts) do
    prop_id = Property.to_id(property)
    new(:prop_value_get, <<prop_id::8>>, opts)
  end

  @doc """
  Creates a property SET frame.

  Used to write a property value to the NCP.
  """
  @spec prop_value_set(Property.property(), payload(), keyword()) :: t()
  def prop_value_set(property, value, opts \\ [])
      when is_binary(value) and is_list(opts) do
    prop_id = Property.to_id(property)
    new(:prop_value_set, <<prop_id::8, value::binary>>, opts)
  end

  @doc """
  Extracts the property from a frame payload.

  Returns the property atom if recognized, the raw ID if unknown,
  or `nil` if the payload is empty.
  """
  @spec extract_property(t()) :: Property.property() | nil
  def extract_property(%__MODULE__{payload: <<prop_id::8, _rest::binary>>})
      when prop_id in 0..255 do
    Property.from_id(prop_id)
  end

  def extract_property(%__MODULE__{payload: <<>>}), do: nil

  @doc """
  Extracts the value portion from a frame payload.

  The first byte (property ID) is stripped, returning only the value.
  """
  @spec extract_value(t()) :: {:ok, binary()} | {:error, :no_value}
  def extract_value(%__MODULE__{payload: <<_prop_id::8, value::binary>>}) do
    {:ok, value}
  end

  def extract_value(%__MODULE__{payload: <<>>}), do: {:error, :no_value}

  @doc """
  Returns all supported command atoms.

  Delegates to Command module.
  """
  @spec commands() :: [command_atom(), ...]
  def commands, do: Command.all()

  @doc """
  Returns all supported properties.

  Delegates to Property module for the complete list.
  """
  @spec properties() :: [Property.property_atom(), ...]
  def properties, do: Property.all()

  @doc """
  Checks if a command is valid (known).

  Delegates to Command module.
  """
  @spec valid_command?(term()) :: boolean()
  def valid_command?(cmd), do: Command.valid?(cmd)

  @doc """
  Checks if a frame is a request (host to NCP).
  """
  @spec request?(t()) :: boolean()
  def request?(%__MODULE__{command: command}), do: Command.request?(command)

  @doc """
  Checks if a frame is a response (NCP to host).
  """
  @spec response?(t()) :: boolean()
  def response?(%__MODULE__{command: command}), do: Command.response?(command)

  @doc """
  Checks if two frames form a valid request/response pair.
  """
  @spec valid_pair?(t(), t()) :: boolean()
  def valid_pair?(%__MODULE__{command: req_cmd}, %__MODULE__{command: resp_cmd}) do
    Command.valid_pair?(req_cmd, resp_cmd)
  end

  # Private functions with strict types

  @spec build_header(tid()) :: header()
  defp build_header(tid) when is_integer(tid) and tid in 0..15 do
    # Bit 7 = 1 (host to NCP) ensures result is 128..143
    # Bits 6-4 = 000 (reserved)
    # Bits 3-0 = TID
    0x80 ||| (tid &&& 0x0F)
  end

  @spec extract_tid(header()) :: tid()
  def extract_tid(header) when is_integer(header) and header in 128..255 do
    header &&& 0x0F
  end
end
