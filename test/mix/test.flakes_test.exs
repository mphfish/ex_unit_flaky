defmodule Mix.Tasks.Test.FlakesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias ExUnitFlaky.Repo

  setup do
    Mix.Task.reenable("test")
    Mix.Task.reenable("test.flakes")

    on_exit(fn ->
      "test/support/tmp/flakes_*.sqlite3" |> Path.wildcard() |> Enum.each(&File.rm/1)
    end)
  end

  test "accurately records passing tests" do
    Mix.Task.run(
      "test.flakes",
      [
        "-r",
        Harness.file_db_path("flakes_pass_run"),
        "-s",
        ":memory:",
        "-f",
        "test/support/fixtures/tests_passed.exs"
      ]
    )

    {:ok, repo} = Repo.start_link(database: Harness.file_db_path("flakes_pass_run"))

    assert [
             %ExUnitFlaky.TestRuns{
               key: "Elixir.TestsPassed.test passes",
               runs: 1,
               passes: 1
             }
           ] = Repo.query_tests(%{}, repo)
  end

  test "accurately records failing tests" do
    assert {_logs, 2} =
             System.cmd("mix", [
               "test.flakes",
               "-r",
               Harness.file_db_path("flakes_fail_run"),
               "-s",
               ":memory:",
               "-f",
               "test/support/fixtures/tests_failed.exs"
             ])

    {:ok, repo} = Repo.start_link(database: Harness.file_db_path("flakes_fail_run"))

    assert [
             %ExUnitFlaky.TestRuns{
               key: "Elixir.TestsFailed.test fails",
               runs: 1,
               failures: 1
             }
           ] = Repo.query_tests(%{}, repo)
  end

  describe "flakiness" do
    test "if the test's failure rate is under the threshold, the command exits with a 0 exit code" do
      {:ok, repo} = Repo.start_link(database: Harness.file_db_path("flakes_shared"))

      for _ <- 1..5 do
        Repo.add_completed_test({"Elixir.TestsFailed.test fails", nil}, repo)
      end

      Repo.save_db(repo)

      assert {_logs, 0} =
               System.cmd("mix", [
                 "test.flakes",
                 "-r",
                 Harness.file_db_path("flakes_run"),
                 "-s",
                 Harness.file_db_path("flakes_shared"),
                 "-f",
                 "test/support/fixtures/tests_failed.exs"
               ])
    end

    test "if the test's flakiness is over the threshold, the command exits with a 2 exit code" do
      {:ok, repo} = Repo.start_link(database: Harness.file_db_path("flakes_shared"))

      for _ <- 1..5 do
        Repo.add_completed_test({"Elixir.TestsFailed.test fails", {:failed, "abc"}}, repo)
      end

      Repo.save_db(repo)

      assert {_logs, 2} =
               System.cmd("mix", [
                 "test.flakes",
                 "-r",
                 Harness.file_db_path("flakes_run"),
                 "-s",
                 Harness.file_db_path("flakes_shared"),
                 "-f",
                 "test/support/fixtures/tests_failed.exs"
               ])
    end
  end
end
