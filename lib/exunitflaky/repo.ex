defmodule ExUnitFlaky.Repo do
  @moduledoc """
  Repository for `ExUnitFlaky`.

  When `ExUnitFormatter` records a test run, it is sent here.

  Failed tests are stored in memory, and all tests are stored to ets, and then eventually persisted to disk.
  """
  use GenServer

  alias Exqlite.Basic, as: Database
  alias ExUnitFlaky.TestRuns

  require Logger

  @type t :: __MODULE__

  @doc """
  Starts the repository.

  ## Options:
  - database (required):  The path that the db will be read from/saved to.  Backed by SQLite.  Use `:memory:` for an in memory db.
  - reset_db? (optional):  If true, any existing db will be deleted a new one will be created.  Defaults to false.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Adds a completed test to the repository.
  """
  @spec add_completed_test({String.t(), atom()} | TestRuns.t(), GenServer.server()) ::
          TestRuns.t()
  def add_completed_test(test, server \\ __MODULE__) do
    GenServer.call(server, {:load_test, test})
  end

  @doc """
  Queries the tests in the repository.

  Filters can be structured as a map where the keys are the column names and the values are the query operators.

  ## Examples:

    ```
    Repo.query_tests(%{failures: "> 0"})
    ```

    ```
    Repo.query_tests(%{key: "= 'test_key'"})
    ```
  """
  @spec query_tests(filters :: %{atom => String.t()}, GenServer.server()) :: [TestRuns.t()]
  def query_tests(filters \\ %{}, server \\ __MODULE__) do
    GenServer.call(server, {:query_tests, filters})
  end

  @doc """
  Saves the database to the `path`, defaults to `db.ets`.
  """
  @spec save_db(server :: GenServer.server()) :: :ok
  def save_db(server \\ __MODULE__) do
    GenServer.call(server, :save_db)
  end

  @doc false
  @impl GenServer
  def init(opts) do
    conn = setup_db(opts)

    {:ok, conn}
  end

  @doc false
  @impl GenServer
  def handle_call({:load_test, {key, result}}, _from, conn) do
    test_type = test_type_for_state(result)

    one(
      """
        INSERT INTO test_runs (key, #{test_type})
        VALUES ('#{key}', 1)
        ON CONFLICT(key) DO UPDATE
        SET #{test_type} = test_runs.#{test_type} + 1, runs = test_runs.runs + 1
        RETURNING *
      """,
      conn
    )
  end

  def handle_call({:load_test, %TestRuns{} = test}, _from, conn) do
    one(
      """
        INSERT INTO test_runs (key, runs, passes, failures, excludeds, invalids, skippeds)
        VALUES ('#{test.key}', #{test.runs}, #{test.passes}, #{test.failures}, #{test.excludeds}, #{test.invalids}, #{test.skippeds})
        ON CONFLICT(key) DO UPDATE
        SET
          runs = test_runs.runs + excluded.runs,
          passes = test_runs.passes + excluded.passes,
          failures = test_runs.failures + excluded.failures,
          excludeds = test_runs.excludeds + excluded.excludeds,
          invalids = test_runs.invalids + excluded.invalids,
          skippeds = test_runs.skippeds + excluded.skippeds
        RETURNING *
      """,
      conn
    )
  end

  def handle_call({:query_tests, filters}, _from, conn) do
    all(
      """
        SELECT
          key,
          runs,
          passes,
          failures,
          excludeds,
          invalids,
          skippeds,
          CAST(
           CAST(failures AS FLOAT) / runs * 100 AS INTEGER
          ) AS failure_rate
        FROM test_runs
        #{unless Enum.empty?(filters), do: "WHERE #{Enum.map_join(filters, " AND ", &"#{elem(&1, 0)} #{elem(&1, 1)}")}"}
        ORDER BY key ASC
      """,
      conn
    )
  end

  def handle_call(:save_db, _from, conn) do
    case Database.close(conn) do
      :ok -> {:stop, :normal, :ok, nil}
      any -> {:stop, :db_cannot_be_closed, any, nil}
    end
  end

  defp test_type_for_state(state) do
    case state do
      nil -> "passes"
      {:failed, _reason} -> "failures"
      {:excluded, _reason} -> "excludeds"
      {:invalid, _reason} -> "invalids"
      {:skipped, _reason} -> "skippeds"
    end
  end

  defp setup_db(opts) do
    database = Keyword.fetch!(opts, :database)
    reset_db = Keyword.get(opts, :reset_db, false)

    unless database == ":memory:", do: ensure_db_exists(reset_db, database)

    {:ok, conn} = Database.open(database)

    {:ok, _query, _result, _status} =
      Database.exec(conn, """
        CREATE TABLE IF NOT EXISTS test_runs (
          key TEXT PRIMARY KEY,
          runs INTEGER DEFAULT 1,
          passes INTEGER DEFAULT 0,
          failures INTEGER DEFAULT 0,
          excludeds INTEGER DEFAULT 0,
          invalids INTEGER DEFAULT 0,
          skippeds INTEGER DEFAULT 0
        );

        CREATE UNIQUE INDEX IF NOT EXISTS test_runs_key ON test_runs (key);
        CREATE INDEX IF NOT EXISTS test_runs_failures ON test_runs (failures);
      """)

    conn
  end

  defp ensure_db_exists(reset_db, database) do
    if reset_db and File.exists?(database) do
      File.rm!(database)
    end

    unless File.exists?(database) do
      File.touch!(database)
    end
  end

  defp all(statement, conn) do
    statement
    |> cast_statement(conn)
    |> then(&{:reply, &1, conn})
  end

  defp one(statement, conn) do
    statement
    |> cast_statement(conn)
    |> then(&{:reply, hd(&1), conn})
  end

  defp cast_statement(statement, conn) do
    case execute_statement(conn, statement) do
      {:ok, rows, columns} ->
        Enum.map(rows, &cast_to_test_run(&1, columns))

      {:error, message} ->
        {:error, message}
    end
  end

  defp execute_statement(conn, statement) do
    Logger.debug(statement)

    conn
    |> Database.exec(statement)
    |> Database.rows()
  end

  defp cast_to_test_run(row, columns) do
    columns
    |> Enum.zip(row)
    |> TestRuns.from_row()
  end
end
