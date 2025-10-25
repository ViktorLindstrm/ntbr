defmodule NTBR.Domain.Spinel.CommandTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.Command

  # Property-based test generators

  defp command_atom_gen do
    oneof(Command.all())
  end

  defp command_id_gen do
    oneof(Command.all_ids())
  end

  # Property-based tests

  property "to_id/from_id roundtrip for all commands" do
    forall cmd <- command_atom_gen() do
      id = Command.to_id(cmd)
      Command.from_id(id) == cmd
    end
  end

  property "from_id/to_id roundtrip for all IDs" do
    forall id <- command_id_gen() do
      cmd = Command.from_id(id)

      # If it's a known command (atom), converting back should give same ID
      if is_atom(cmd) do
        Command.to_id(cmd) == id
      else
        # Unknown ID returns itself
        cmd == id
      end
    end
  end

  property "to_id always returns a valid byte" do
    forall cmd <- command_atom_gen() do
      id = Command.to_id(cmd)
      is_integer(id) and id in 0..255
    end
  end

  property "to_id with integer returns same integer" do
    forall id <- integer(0, 255) do
      Command.to_id(id) == id
    end
  end

  property "from_id with atom returns same atom" do
    forall cmd <- command_atom_gen() do
      Command.from_id(cmd) == cmd
    end
  end

  property "all commands are valid" do
    forall cmd <- command_atom_gen() do
      Command.valid?(cmd)
    end
  end

  property "all command IDs are valid" do
    forall id <- command_id_gen() do
      Command.valid?(id)
    end
  end

  property "request and response commands are mutually exclusive" do
    forall cmd <- command_atom_gen() do
      not (Command.request?(cmd) and Command.response?(cmd))
    end
  end

  property "description is always non-empty string" do
    forall cmd <- command_atom_gen() do
      desc = Command.description(cmd)
      is_binary(desc) and byte_size(desc) > 0
    end
  end

  property "all() contains no duplicates" do
    all_cmds = Command.all()
    length(all_cmds) == length(Enum.uniq(all_cmds))
  end

  property "all_ids() contains no duplicates" do
    all_ids = Command.all_ids()
    length(all_ids) == length(Enum.uniq(all_ids))
  end

  property "request commands have a response" do
    forall cmd <- command_atom_gen() do
      if Command.request?(cmd) do
        match?({:ok, _}, Command.response_for(cmd))
      else
        true
      end
    end
  end

  property "response_for is consistent with valid_pair?" do
    forall [req <- command_atom_gen(), resp <- command_atom_gen()] do
      case Command.response_for(req) do
        {:ok, expected} ->
          Command.valid_pair?(req, resp) == (resp == expected)

        {:error, :not_a_request} ->
          not Command.valid_pair?(req, resp)
      end
    end
  end

  # Traditional unit tests

  describe "to_id/1" do
    test "converts known commands to IDs" do
      assert Command.to_id(:noop) == 0x00
      assert Command.to_id(:reset) == 0x01
      assert Command.to_id(:prop_value_get) == 0x02
      assert Command.to_id(:prop_value_set) == 0x03
      assert Command.to_id(:prop_value_is) == 0x06
    end

    test "returns 0x00 for unknown command" do
      assert Command.to_id(:unknown_command) == 0x00
    end

    test "returns same value for integer input" do
      assert Command.to_id(0x01) == 0x01
      assert Command.to_id(0xFF) == 0xFF
    end
  end

  describe "from_id/1" do
    test "converts known IDs to commands" do
      assert Command.from_id(0x00) == :noop
      assert Command.from_id(0x01) == :reset
      assert Command.from_id(0x02) == :prop_value_get
      assert Command.from_id(0x03) == :prop_value_set
      assert Command.from_id(0x06) == :prop_value_is
    end

    test "returns ID for unknown command" do
      assert Command.from_id(0xFF) == 0xFF
      assert Command.from_id(0x50) == 0x50
    end

    test "returns same value for atom input" do
      assert Command.from_id(:reset) == :reset
      assert Command.from_id(:prop_value_get) == :prop_value_get
    end
  end

  describe "all/0 and all_ids/0" do
    test "all() returns all command atoms" do
      cmds = Command.all()

      assert :noop in cmds
      assert :reset in cmds
      assert :prop_value_get in cmds
      assert :prop_value_set in cmds
      assert :prop_value_is in cmds

      assert length(cmds) == 9
    end

    test "all_ids() returns all command IDs" do
      ids = Command.all_ids()

      assert 0x00 in ids
      assert 0x01 in ids
      assert 0x02 in ids
      assert 0x03 in ids
      assert 0x06 in ids

      assert length(ids) == 9
    end

    test "all() and all_ids() have same length" do
      assert length(Command.all()) == length(Command.all_ids())
    end
  end

  describe "valid?/1" do
    test "returns true for known commands" do
      assert Command.valid?(:reset)
      assert Command.valid?(:prop_value_get)
      assert Command.valid?(:prop_value_is)
      assert Command.valid?(0x01)
      assert Command.valid?(0x02)
    end

    test "returns false for unknown commands" do
      refute Command.valid?(:unknown_command)
      refute Command.valid?(:fake_cmd)
      refute Command.valid?(0xFF)
      refute Command.valid?(0x50)
    end

    test "returns false for invalid types" do
      refute Command.valid?("reset")
      refute Command.valid?(nil)
      refute Command.valid?(%{})
    end
  end

  describe "description/1" do
    test "returns descriptions for known commands" do
      assert Command.description(:reset) =~ "Reset"
      assert Command.description(:prop_value_get) =~ "Get property"
      assert Command.description(:prop_value_set) =~ "Set property"
      assert Command.description(:noop) =~ "No operation"
    end

    test "returns generic description for unknown commands" do
      assert Command.description(:unknown_cmd) == "Unknown command"
      assert Command.description(0xFF) == "Unknown command"
    end

    test "works with IDs" do
      assert Command.description(0x01) =~ "Reset"
    end
  end

  describe "request?/1 and response?/1" do
    test "identifies request commands correctly" do
      assert Command.request?(:reset)
      assert Command.request?(:prop_value_get)
      assert Command.request?(:prop_value_set)
      assert Command.request?(:prop_value_insert)
      assert Command.request?(:prop_value_remove)

      refute Command.request?(:prop_value_is)
      refute Command.request?(:noop)
    end

    test "identifies response commands correctly" do
      assert Command.response?(:prop_value_is)
      assert Command.response?(:prop_value_inserted)
      assert Command.response?(:prop_value_removed)

      refute Command.response?(:reset)
      refute Command.response?(:prop_value_get)
    end

    test "request and response are mutually exclusive" do
      Enum.each(Command.all(), fn cmd ->
        refute Command.request?(cmd) and Command.response?(cmd)
      end)
    end
  end

  describe "response_for/1" do
    test "returns correct response for requests" do
      assert {:ok, :prop_value_is} = Command.response_for(:prop_value_get)
      assert {:ok, :prop_value_is} = Command.response_for(:prop_value_set)
      assert {:ok, :prop_value_inserted} = Command.response_for(:prop_value_insert)
      assert {:ok, :prop_value_removed} = Command.response_for(:prop_value_remove)
      assert {:ok, :prop_value_is} = Command.response_for(:reset)
    end

    test "returns error for non-request commands" do
      assert {:error, :not_a_request} = Command.response_for(:prop_value_is)
      assert {:error, :not_a_request} = Command.response_for(:noop)
    end

    test "works with command IDs" do
      assert {:ok, :prop_value_is} = Command.response_for(0x02)
    end
  end

  describe "by_type/1" do
    test "returns request commands" do
      requests = Command.by_type(:request)

      assert :reset in requests
      assert :prop_value_get in requests
      assert :prop_value_set in requests

      refute :prop_value_is in requests
    end

    test "returns response commands" do
      responses = Command.by_type(:response)

      assert :prop_value_is in responses
      assert :prop_value_inserted in responses
      assert :prop_value_removed in responses

      refute :prop_value_get in responses
    end

    test "returns notification commands" do
      notifications = Command.by_type(:notification)

      assert :noop in notifications
    end

    test "all types cover all commands" do
      all_types =
        Command.by_type(:request) ++
          Command.by_type(:response) ++
          Command.by_type(:notification)

      assert length(Enum.uniq(all_types)) == length(Command.all())
    end
  end

  describe "valid_pair?/1" do
    test "validates correct request/response pairs" do
      assert Command.valid_pair?(:prop_value_get, :prop_value_is)
      assert Command.valid_pair?(:prop_value_set, :prop_value_is)
      assert Command.valid_pair?(:prop_value_insert, :prop_value_inserted)
      assert Command.valid_pair?(:prop_value_remove, :prop_value_removed)
      assert Command.valid_pair?(:reset, :prop_value_is)
    end

    test "rejects incorrect pairs" do
      refute Command.valid_pair?(:prop_value_get, :prop_value_inserted)
      refute Command.valid_pair?(:prop_value_set, :prop_value_removed)
      refute Command.valid_pair?(:prop_value_insert, :prop_value_is)
    end

    test "rejects non-request commands" do
      refute Command.valid_pair?(:prop_value_is, :prop_value_is)
      refute Command.valid_pair?(:noop, :prop_value_is)
    end

    test "works with command IDs" do
      assert Command.valid_pair?(0x02, 0x06)
      refute Command.valid_pair?(0x02, 0x07)
    end
  end

  describe "integration with Frame" do
    test "Command integrates with Frame module" do
      alias NTBR.Domain.Spinel.Frame

      # Create frame using command atom
      frame = Frame.new(:reset, <<>>, tid: 1)

      # Verify command
      assert frame.command == :reset
      assert Command.valid?(frame.command)
      assert Command.request?(frame.command)
      assert {:ok, :prop_value_is} = Command.response_for(frame.command)
    end

    test "Frame helper functions use Command" do
      alias NTBR.Domain.Spinel.Frame

      request = Frame.new(:prop_value_get, <<0x01>>, tid: 1)
      response = Frame.new(:prop_value_is, <<0x01, 0x42>>, tid: 1)

      assert Frame.request?(request)
      assert Frame.response?(response)
      assert Frame.valid_pair?(request, response)
    end
  end

  describe "compile-time validation" do
    test "__validate__! runs successfully" do
      assert :ok = Command.__validate__!()
    end
  end
end
