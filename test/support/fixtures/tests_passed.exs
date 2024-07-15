defmodule TestsPassed do
  use ExUnit.Case

  test "passes" do
    assert Harness.pass()
  end
end
