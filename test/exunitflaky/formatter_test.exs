defmodule ExUnit.FormatterTest do
  use ExUnit.Case, async: true

  alias ExUnitFlaky.Formatter
  alias ExUnitFlaky.TestRuns

  setup do
    repo = start_link_supervised!({ExUnitFlaky.Repo, database: ":memory:", name: :formatter_test})
    {:ok, repo: repo}
  end

  test "adds a passed test to the repo", %{repo: repo} do
    assert %TestRuns{runs: 1, passes: 1} =
             Formatter.handle_completed_test(
               %ExUnit.Test{
                 name: "test",
                 module: "MyTest",
                 state: nil
               },
               repo
             )
  end

  test "adds a failed test to the repo", %{repo: repo} do
    assert %TestRuns{runs: 1, failures: 1} =
             Formatter.handle_completed_test(
               %ExUnit.Test{
                 name: "test",
                 module: "MyTest",
                 state: {:failed, "reason"}
               },
               repo
             )
  end

  test "adds an excluded test to the repo", %{repo: repo} do
    assert %TestRuns{runs: 1, excludeds: 1} =
             Formatter.handle_completed_test(
               %ExUnit.Test{
                 name: "test",
                 module: "MyTest",
                 state: {:excluded, nil}
               },
               repo
             )
  end

  test "adds an invalid test to the repo", %{repo: repo} do
    assert %TestRuns{runs: 1, invalids: 1} =
             Formatter.handle_completed_test(
               %ExUnit.Test{
                 name: "test",
                 module: "MyTest",
                 state: {:invalid, "reason"}
               },
               repo
             )
  end

  test "adds a skipped test to the repo", %{repo: repo} do
    assert %TestRuns{runs: 1, skippeds: 1} =
             Formatter.handle_completed_test(
               %ExUnit.Test{
                 name: "test",
                 module: "MyTest",
                 state: {:skipped, nil}
               },
               repo
             )
  end
end
