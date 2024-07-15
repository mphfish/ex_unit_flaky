defmodule ExUnitFlaky.Formatter do
  @moduledoc false
  use GenServer

  alias ExUnit.Test
  alias ExUnitFlaky.Repo
  alias ExUnitFlaky.TestRuns

  @spec handle_completed_test(ExUnit.Test.t(), Repo.t()) :: TestRuns.t()
  @doc false
  def handle_completed_test(test, repo) do
    test |> format_test_result() |> Repo.add_completed_test(repo)
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc false
  @impl GenServer
  def init(_opts) do
    {:ok, repo} =
      Repo.start_link(database: System.fetch_env!("EXUNIT_FLAKY_DATABASE"))

    {:ok, repo}
  end

  @doc false
  @impl GenServer
  def handle_cast({:test_finished, test}, repo) do
    _test_run = handle_completed_test(test, repo)

    {:noreply, repo}
  end

  def handle_cast({:suite_finished, _}, repo) do
    Repo.save_db(repo)
    {:noreply, repo}
  end

  def handle_cast(_message, repo) do
    {:noreply, repo}
  end

  defp format_test_result(%Test{name: name, module: module, state: state}) do
    {"#{module}.#{name}", state}
  end
end
