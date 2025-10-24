defmodule NTBR.FirmwareTest do
  use ExUnit.Case
  doctest NTBR.Firmware

  test "greets the world" do
    assert NTBR.Firmware.hello() == :world
  end
end
