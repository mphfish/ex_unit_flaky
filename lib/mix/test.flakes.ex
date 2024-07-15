defmodule Mix.Tasks.Test.Flakes do
  @shortdoc "Runs mix.test with tracking of flaky tests"
  @moduledoc """
  Mix Task that runs `mix test` with tracking of flaky tests.

  ## Command line options

  - `run_db_path` - The path that should be used for this runs database
  - `shared_db_path` The path to the database that has historical results
  - `filename` (optional) - The filename of the test file to run ()

  """
  use Mix.Task

  alias ExUnitFlaky.Repo
  alias ExUnitFlaky.TestRuns

  require Logger

  @switches [
    run_db_path: :string,
    shared_db_path: :string,
    threshold: :integer,
    filename: :string,
    ignore_exunit_exit_code: :boolean
  ]

  @aliases [
    t: :threshold,
    r: :run_db_path,
    s: :shared_db_path,
    f: :filename,
    i: :ignore_exunit_exit_code
  ]

  @impl Mix.Task
  def run(args) do
    {options, _args, _invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    Logger.info("Starting mix test with flaky support")

    options
    |> run_tests()
    |> then(fn
      0 ->
        Logger.info("All tests passed")

      _exit_code ->
        Logger.info("Test runs has failures, evaluating flakiness")
        {:ok, shared_repo} = Repo.start_link(database: options[:shared_db_path], name: :shared)

        {:ok, run_repo} = Repo.start_link(database: options[:run_db_path], name: :run)

        %{failures: "> 0"}
        |> Repo.query_tests(run_repo)
        |> Enum.reduce_while(0, fn test, _exit_code ->
          %{key: "= '#{test.key}'"}
          |> Repo.query_tests(shared_repo)
          |> evaluate_failed_test(options)
        end)
        |> then(fn exit_code ->
          Repo.save_db(run_repo)
          Repo.save_db(shared_repo)

          System.stop(exit_code)
        end)
    end)
  end

  defp run_tests(options) do
    "mix"
    |> System.cmd(
      [
        "test",
        "--formatter=ExUnitFlaky.Formatter" | mix_test_args(options)
      ],
      env: [{"EXUNIT_FLAKY_DATABASE", options[:run_db_path]}],
      stderr_to_stdout: true
    )
    |> then(fn {logs, exit_code} ->
      logs
      |> String.split("\n")
      |> Enum.each(&Logger.info/1)

      exit_code
    end)
  end

  defp mix_test_args(options) do
    if filename = Keyword.get(options, :filename) do
      [filename]
    else
      []
    end
  end

  defp evaluate_failed_test([%TestRuns{} = prev_run], options) do
    if prev_run.failure_rate > Keyword.get(options, :threshold, 10) do
      Logger.info("Test #{prev_run.key} is not flaky, exiting as failure")
      {:halt, 2}
    else
      Logger.info("Test #{prev_run.key} is flaky, ignoring.")
      {:cont, 0}
    end
  end

  defp evaluate_failed_test(_any, _options) do
    Logger.info("Test is new.  It cannot be evaluated for flakiness.  Exiting as failure")
    {:halt, 2}
  end
end
