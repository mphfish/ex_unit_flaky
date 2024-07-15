defmodule ExUnitFlaky.RepoTest do
  use ExUnit.Case, async: true

  alias ExUnitFlaky.Repo
  alias ExUnitFlaky.TestRuns

  setup do
    repo = start_link_supervised!({ExUnitFlaky.Repo, database: ":memory:", name: :repo_test})

    {:ok, repo: repo}
  end

  describe "add_completed_test/2" do
    test "adds a test to the repo", %{repo: repo} do
      assert %TestRuns{key: "a", runs: 1, passes: 1} = Repo.add_completed_test({"a", nil}, repo)

      assert %TestRuns{key: "b", runs: 1, passes: 0, failures: 1} =
               Repo.add_completed_test({"b", {:failed, nil}}, repo)

      assert %TestRuns{key: "c", runs: 1, passes: 0, excludeds: 1} =
               Repo.add_completed_test({"c", {:excluded, nil}}, repo)

      assert %TestRuns{key: "d", runs: 1, passes: 0, invalids: 1} =
               Repo.add_completed_test({"d", {:invalid, nil}}, repo)

      assert %TestRuns{key: "e", runs: 1, passes: 0, skippeds: 1} =
               Repo.add_completed_test({"e", {:skipped, nil}}, repo)
    end
  end

  describe "query_tests/2" do
    test "returns all tests when no filters are provided", %{repo: repo} do
      Repo.add_completed_test({"a", nil}, repo)
      Repo.add_completed_test({"b", nil}, repo)

      assert [%{key: "a"}, %{key: "b"}] = Repo.query_tests(%{}, repo)
    end

    test "returns only tests that match the filter", %{repo: repo} do
      Repo.add_completed_test({"a", nil}, repo)
      Repo.add_completed_test({"b", {:failed, nil}}, repo)

      assert [%{key: "a"}] = Repo.query_tests(%{key: "= 'a'"}, repo)

      assert [%{key: "b"}] = Repo.query_tests(%{failures: "> 0"}, repo)
    end

    test "accurately calculates failure_rate", %{repo: repo} do
      Repo.add_completed_test({"a", nil}, repo)
      Repo.add_completed_test({"a", {:failed, nil}}, repo)

      assert [%TestRuns{key: "a", runs: 2, passes: 1, failures: 1, failure_rate: 50}] =
               Repo.query_tests(%{key: "= 'a'"}, repo)
    end
  end

  describe "save_db/1" do
    test "saves the database" do
      {:ok, repo} = GenServer.start(Repo, [database: ":memory:"], name: :shutdown)

      assert :ok = Repo.save_db(repo)
    end
  end

  describe "init/1" do
    test "ensures the db file exists" do
      on_exit(fn -> File.rm(Harness.file_db_path()) end)

      {:ok, pid} = Repo.start_link(name: :file_db, database: Harness.file_db_path())

      assert File.exists?(Harness.file_db_path())

      GenServer.stop(pid)
    end

    test "deletes the db file if passed reset_db" do
      on_exit(fn -> File.rm(Harness.file_db_path()) end)

      File.touch!(Harness.file_db_path())

      {:ok, pid} =
        Repo.start_link(name: :file_db, database: Harness.file_db_path(), reset_db: true)

      GenServer.stop(pid)
    end
  end
end
