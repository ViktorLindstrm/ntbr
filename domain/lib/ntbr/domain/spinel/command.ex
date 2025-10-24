defmodule NTBR.Domain.Spinel.Command do
  @moduledoc """
  Spinel protocol command definitions with Elixir 1.18 type system.

  Commands control the NCP (Network Co-Processor) and are used to
  perform operations like resetting, getting/setting properties, and
  managing the Thread network.

  This module provides compile-time validated command mappings with
  strict type guarantees.
  """

  @typedoc "Command ID (byte value)"
  @type command_id :: 0..255

  @typedoc "Supported Spinel command atoms"
  @type command_atom ::
          :noop
          | :reset
          | :prop_value_get
          | :prop_value_set
          | :prop_value_insert
          | :prop_value_remove
          | :prop_value_is
          | :prop_value_inserted
          | :prop_value_removed

  @typedoc "Command can be an atom or raw ID"
  @type command :: command_atom() | command_id()

  # Command ID mappings
  @commands %{
    0x00 => :noop,
    0x01 => :reset,
    0x02 => :prop_value_get,
    0x03 => :prop_value_set,
    0x04 => :prop_value_insert,
    0x05 => :prop_value_remove,
    0x06 => :prop_value_is,
    0x07 => :prop_value_inserted,
    0x08 => :prop_value_removed
  }

  #@commands_reverse Map.new(@commands, fn {k, v} -> {v, k} end)

  # Compile-time validation
  @doc false
  @spec __validate__! :: :ok | no_return()
  def __validate__! do
    # Ensure all command atoms are unique
    command_atoms = Map.values(@commands)

    if length(command_atoms) != length(Enum.uniq(command_atoms)) do
      raise "Duplicate command atoms detected"
    end

    # Ensure all command IDs are unique and valid bytes
    command_ids = Map.keys(@commands)

    if length(command_ids) != length(Enum.uniq(command_ids)) do
      raise "Duplicate command IDs detected"
    end

    unless Enum.all?(command_ids, &(&1 in 0..255)) do
      raise "Command IDs must be valid bytes (0-255)"
    end

    :ok
  end

  @doc """
  Converts a command atom to its ID with compile-time validation.

  ## Examples

      iex> Command.to_id(:reset)
      0x01

      iex> Command.to_id(:prop_value_get)
      0x02

      iex> Command.to_id(0x01)
      0x01
  """
  @spec to_id(command()) :: command_id()
  def to_id(cmd) when is_atom(cmd) do
    case cmd do
      :noop -> 0x00
      :reset -> 0x01
      :prop_value_get -> 0x02
      :prop_value_set -> 0x03
      :prop_value_insert -> 0x04
      :prop_value_remove -> 0x05
      :prop_value_is -> 0x06
      :prop_value_inserted -> 0x07
      :prop_value_removed -> 0x08
      _ -> 0x00
    end
  end

  def to_id(cmd) when is_integer(cmd) and cmd in 0..255 do
    cmd
  end

  @doc """
  Converts a command ID to its atom representation with validation.

  ## Examples

      iex> Command.from_id(0x01)
      :reset

      iex> Command.from_id(0x02)
      :prop_value_get

      iex> Command.from_id(:reset)
      :reset

      iex> Command.from_id(0xFF)
      0xFF
  """
  @spec from_id(command()) :: command()
  def from_id(id) when is_integer(id) and id in 0..255 do
    case id do
      0x00 -> :noop
      0x01 -> :reset
      0x02 -> :prop_value_get
      0x03 -> :prop_value_set
      0x04 -> :prop_value_insert
      0x05 -> :prop_value_remove
      0x06 -> :prop_value_is
      0x07 -> :prop_value_inserted
      0x08 -> :prop_value_removed
      _ -> id
    end
  end

  def from_id(cmd) when is_atom(cmd), do: cmd

  @doc """
  Returns all supported command atoms.
  """
  @spec all() :: [command_atom(), ...]
  def all do
    [
      :noop,
      :reset,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove,
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ]
  end

  @doc """
  Returns all command IDs.
  """
  @spec all_ids() :: [command_id(), ...]
  def all_ids do
    [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
  end

  @doc """
  Checks if a command is valid with type-safe guards.

  ## Examples

      iex> Command.valid?(:reset)
      true

      iex> Command.valid?(:invalid_command)
      false

      iex> Command.valid?(0x01)
      true

      iex> Command.valid?(0xFF)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(cmd) when is_atom(cmd) do
    cmd in [
      :noop,
      :reset,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove,
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ]
  end

  def valid?(id) when is_integer(id) do
    id in 0x00..0x08
  end

  def valid?(_), do: false

  @doc """
  Returns a human-readable description of a command.

  ## Examples

      iex> Command.description(:reset)
      "Reset the NCP"

      iex> Command.description(:prop_value_get)
      "Get property value"
  """
  @spec description(command()) :: String.t()
  def description(cmd) do
    cmd = from_id(cmd)

    case cmd do
      :noop -> "No operation"
      :reset -> "Reset the NCP"
      :prop_value_get -> "Get property value"
      :prop_value_set -> "Set property value"
      :prop_value_insert -> "Insert value into property"
      :prop_value_remove -> "Remove value from property"
      :prop_value_is -> "Property value response"
      :prop_value_inserted -> "Value inserted notification"
      :prop_value_removed -> "Value removed notification"
      _ -> "Unknown command"
    end
  end

  @doc """
  Checks if a command is a request (host to NCP).

  Request commands are sent from the host to the NCP and expect a response.
  """
  @spec request?(command()) :: boolean()
  def request?(cmd) do
    cmd = from_id(cmd)

    cmd in [
      :reset,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove
    ]
  end

  @doc """
  Checks if a command is a response (NCP to host).

  Response commands are sent from the NCP to the host in response to a request.
  """
  @spec response?(command()) :: boolean()
  def response?(cmd) do
    cmd = from_id(cmd)

    cmd in [
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ]
  end

  @doc """
  Returns the expected response command for a request.

  ## Examples

      iex> Command.response_for(:prop_value_get)
      {:ok, :prop_value_is}

      iex> Command.response_for(:prop_value_set)
      {:ok, :prop_value_is}

      iex> Command.response_for(:reset)
      {:ok, :prop_value_is}

      iex> Command.response_for(:prop_value_is)
      {:error, :not_a_request}
  """
  @spec response_for(command()) :: {:ok, command_atom()} | {:error, :not_a_request}
  def response_for(cmd) do
    cmd = from_id(cmd)

    case cmd do
      :prop_value_get -> {:ok, :prop_value_is}
      :prop_value_set -> {:ok, :prop_value_is}
      :prop_value_insert -> {:ok, :prop_value_inserted}
      :prop_value_remove -> {:ok, :prop_value_removed}
      :reset -> {:ok, :prop_value_is}
      _ when is_atom(cmd) -> {:error, :not_a_request}
      _ -> {:error, :not_a_request}
    end
  end

  @doc """
  Groups commands by type (request/response/notification).

  ## Examples

      iex> Command.by_type(:request)
      [:reset, :prop_value_get, :prop_value_set, :prop_value_insert, :prop_value_remove]

      iex> Command.by_type(:response)
      [:prop_value_is, :prop_value_inserted, :prop_value_removed]
  """
  @spec by_type(:request | :response | :notification) :: [command_atom()]
  def by_type(:request) do
    [
      :reset,
      :prop_value_get,
      :prop_value_set,
      :prop_value_insert,
      :prop_value_remove
    ]
  end

  def by_type(:response) do
    [
      :prop_value_is,
      :prop_value_inserted,
      :prop_value_removed
    ]
  end

  def by_type(:notification) do
    # Notifications are unsolicited responses
    [:noop]
  end

  @doc """
  Checks if two commands form a valid request/response pair.

  ## Examples

      iex> Command.valid_pair?(:prop_value_get, :prop_value_is)
      true

      iex> Command.valid_pair?(:prop_value_set, :prop_value_is)
      true

      iex> Command.valid_pair?(:prop_value_get, :prop_value_inserted)
      false
  """
  @spec valid_pair?(command(), command()) :: boolean()
  def valid_pair?(request, response) do
    case response_for(request) do
      {:ok, expected} -> from_id(response) == expected
      {:error, _} -> false
    end
  end
end
