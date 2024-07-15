defmodule Mix.Tasks.Sync.Flaky do
  @shortdoc "Syncs flaky test results from individual runs into the main table"

  @moduledoc """
  ExUnitFlaky is designed to help track flaky tests, specifically that are ran in Github Actions.

  Each individual run creates their own version of the ets table, and the results are saved to disk.

  Once this happens, the individual run tables need to be synchronized into the main table.

  ## Command line options

  - `db_path` - The path to the flaky test database
  - `base_path` - The path where individual action run result databases are located
  - `run_pattern` - The pattern to match the individual run databases filename against
  """
  use Mix.Task

  alias ExUnitFlaky.Repo

  require Logger

  @switches [
    shared_db_path: :string,
    base_path: :string,
    pattern: :string
  ]

  @aliases [
    s: :shared_db_path,
    b: :base_path,
    p: :pattern
  ]

  @impl Mix.Task
  def run(args) do
    {options, _args, _invalid} = OptionParser.parse(args, strict: @switches, aliases: @aliases)
    Logger.info("Starting shared repo at path #{options[:db_path]}")

    {:ok, shared_repo} = Repo.start_link(name: :shared, database: options[:shared_db_path])

    pattern = Regex.compile!(options[:pattern])

    options[:base_path]
    |> File.ls!()
    |> Enum.filter(&String.match?(&1, pattern))
    |> Enum.each(fn file ->
      Logger.info("Adding contents of file #{file} to shared repo")
      path = Path.join(options[:base_path], file)

      {:ok, repo} = Repo.start_link(name: :run, database: path)

      %{}
      |> Repo.query_tests(repo)
      |> Enum.each(&Repo.add_completed_test(&1, shared_repo))
      |> then(fn _result ->
        Logger.info("#{file} added to shared repo, stopping #{file} repo")
        Repo.save_db(repo)
      end)
    end)
    |> then(fn _result ->
      Repo.save_db(shared_repo)
    end)
  end
end
