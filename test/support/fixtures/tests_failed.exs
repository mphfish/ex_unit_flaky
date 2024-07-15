defmodule TestsFailed do
  use ExUnit.Case

  test "fails" do
    assert Harness.fail()
  end
end
