defmodule Mix.Task.Sync.FlakyTest do
  use ExUnit.Case, async: true

  alias ExUnitFlaky.Repo

  setup do
    Mix.Task.reenable("test")
    Mix.Task.reenable("sync.flaky")

    on_exit(fn ->
      "test/support/tmp/sync_*.sqlite3" |> Path.wildcard() |> Enum.each(&File.rm/1)
    end)
  end

  test "synchronizes individual run dbs into the main database" do
    # setup some run dbs
    for id <- 1..3 do
      {:ok, run_repo} =
        Repo.start_link(database: Harness.file_db_path("sync_run_#{id}"), name: :sync_run)

      Repo.add_completed_test({"a", nil}, run_repo)
      Repo.add_completed_test({"b", {:failed, nil}}, run_repo)
      Repo.add_completed_test({"c", {:excluded, nil}}, run_repo)
      Repo.add_completed_test({"d", {:invalid, nil}}, run_repo)
      Repo.add_completed_test({"e", {:skipped, nil}}, run_repo)
      Repo.save_db(run_repo)
    end

    Mix.Task.run(
      "sync.flaky",
      [
        "-s",
        Harness.file_db_path("sync_shared"),
        "-b",
        "test/support/tmp",
        "-p",
        "sync_run_.*"
      ]
    )

    {:ok, shared_repo} = Repo.start_link(database: Harness.file_db_path("sync_shared"))

    assert [
             %ExUnitFlaky.TestRuns{
               key: "a",
               runs: 3,
               passes: 3
             },
             %ExUnitFlaky.TestRuns{
               key: "b",
               failure_rate: 100,
               runs: 3,
               failures: 3
             },
             %ExUnitFlaky.TestRuns{
               key: "c",
               runs: 3,
               excludeds: 3
             },
             %ExUnitFlaky.TestRuns{
               key: "d",
               runs: 3,
               invalids: 3
             },
             %ExUnitFlaky.TestRuns{
               key: "e",
               runs: 3,
               skippeds: 3
             }
           ] = Repo.query_tests(%{}, shared_repo)
  end
end
