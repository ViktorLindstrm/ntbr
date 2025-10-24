defmodule NTBR.InfraTest do
  use ExUnit.Case
  doctest NTBR.Infra

  test "greets the world" do
    assert NTBR.Infra.hello() == :world
  end
end
