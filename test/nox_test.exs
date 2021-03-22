defmodule NoxTest do
  use ExUnit.Case
  doctest Nox

  test "greets the world" do
    assert Nox.hello() == :world
  end
end
