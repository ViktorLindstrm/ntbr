defmodule NTBR.Domain.Spinel.FramePropertyTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use PropCheck

  alias NTBR.Domain.Spinel.{Frame, Property}

  @moduletag :property

  # Generators

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

  defp payload_gen do
    binary()
  end

  defp property_gen do
    oneof(Property.all())
  end

  defp frame_gen do
    let [cmd <- command_gen(), payload <- payload_gen(), tid <- tid_gen()] do
      Frame.new(cmd, payload, tid: tid)
    end
  end

  # Property Tests

  property "encode/decode roundtrip preserves frame data" do
    forall frame <- frame_gen() do
      encoded = Frame.encode(frame)
      {:ok, decoded} = Frame.decode(encoded)

      decoded.command == frame.command and
        decoded.tid == frame.tid and
        decoded.payload == frame.payload
    end
  end

  property "TID is always in valid range 0-15" do
    forall frame <- frame_gen() do
      frame.tid >= 0 and frame.tid <= 15
    end
  end

  property "header has bit 7 set for host-to-NCP frames" do
    forall frame <- frame_gen() do
      encoded = Frame.encode(frame)
      <<header::8, _rest::binary>> = encoded

      # Bit 7 should be set (0x80 = 128)
      header >= 128 and header <= 143
    end
  end

  property "encoded frame is at least 2 bytes (header + command)" do
    forall frame <- frame_gen() do
      encoded = Frame.encode(frame)
      byte_size(encoded) >= 2
    end
  end

  property "encoded frame size equals 2 + payload size" do
    forall frame <- frame_gen() do
      encoded = Frame.encode(frame)
      byte_size(encoded) == 2 + byte_size(frame.payload)
    end
  end

  property "decoding invalid data returns error" do
    forall data <- binary() do
      case byte_size(data) do
        0 -> Frame.decode(data) == {:error, :invalid_frame}
        1 -> Frame.decode(data) == {:error, :invalid_frame}
        _ -> true  # Valid frames have at least 2 bytes
      end
    end
  end

  property "reset frames have empty payload" do
    forall tid <- tid_gen() do
      frame = Frame.reset(tid: tid)
      frame.payload == <<>> and frame.command == :reset
    end
  end

  property "prop_value_get frames contain property ID" do
    forall {property, tid} <- {property_gen(), tid_gen()} do
      frame = Frame.prop_value_get(property, tid: tid)
      extracted_prop = Frame.extract_property(frame)

      extracted_prop == property
    end
  end

  property "prop_value_set frames contain property ID and value" do
    forall {property, value, tid} <- {property_gen(), binary(), tid_gen()} do
      frame = Frame.prop_value_set(property, value, tid: tid)
      extracted_prop = Frame.extract_property(frame)
      {:ok, extracted_value} = Frame.extract_value(frame)

      extracted_prop == property and extracted_value == value
    end
  end

  property "extract_property returns nil for empty payload" do
    forall tid <- tid_gen() do
      frame = Frame.new(:reset, <<>>, tid: tid)
      Frame.extract_property(frame) == nil
    end
  end

  property "extract_value returns error for empty payload" do
    forall tid <- tid_gen() do
      frame = Frame.new(:reset, <<>>, tid: tid)
      Frame.extract_value(frame) == {:error, :no_value}
    end
  end

  property "TID roundtrips through encode/decode" do
    forall {cmd, tid} <- {command_gen(), tid_gen()} do
      frame = Frame.new(cmd, <<>>, tid: tid)
      encoded = Frame.encode(frame)
      {:ok, decoded} = Frame.decode(encoded)

      decoded.tid == tid
    end
  end

  property "all commands are valid" do
    forall cmd <- command_gen() do
      Frame.valid_command?(cmd)
    end
  end

  property "command encoding is deterministic" do
    forall {cmd, payload, tid} <- {command_gen(), payload_gen(), tid_gen()} do
      frame1 = Frame.new(cmd, payload, tid: tid)
      frame2 = Frame.new(cmd, payload, tid: tid)

      Frame.encode(frame1) == Frame.encode(frame2)
    end
  end

  property "different TIDs produce different encoded frames" do
    forall {cmd, payload, tid1, tid2} <- 
      {command_gen(), payload_gen(), tid_gen(), tid_gen()} do
      implies tid1 != tid2 do
        frame1 = Frame.new(cmd, payload, tid: tid1)
        frame2 = Frame.new(cmd, payload, tid: tid2)

        Frame.encode(frame1) != Frame.encode(frame2)
      end
    end
  end

  property "request? and response? are mutually exclusive" do
    forall frame <- frame_gen() do
      not (Frame.request?(frame) and Frame.response?(frame))
    end
  end

  property "valid command pairs match expected patterns" do
    # Test that request commands pair with response commands
    prop_value_get_frame = Frame.new(:prop_value_get, <<1>>, tid: 0)
    prop_value_is_frame = Frame.new(:prop_value_is, <<1>>, tid: 0)

    Frame.valid_pair?(prop_value_get_frame, prop_value_is_frame)
  end
end
