defmodule NTBR.CoreTest do
  use ExUnit.Case
  doctest NTBR.Core

  test "greets the world" do
    assert NTBR.Core.hello() == :world
  end
end
