defmodule ExUnitFlaky.TestRuns do
  @moduledoc """
  A struct to represent test runs.

  ## Attributes
   * `:key` - the test key
    * `:runs` - the number of runs
    * `:passes` - the number of passes
    * `:failures` - the number of failures
    * `:excludeds` - the number of excluded tests
    * `:invalids` - the number of invalid tests
    * `:skippeds` - the number of skipped tests
    * `:failure_rate` - the failure rate (runs with failures / total runs)

  """
  @type t :: %__MODULE__{
          runs: integer(),
          passes: integer(),
          failures: integer(),
          excludeds: integer(),
          invalids: integer(),
          skippeds: integer(),
          failure_rate: integer()
        }
  defstruct [
    :key,
    :failure_rate,
    runs: 0,
    passes: 0,
    failures: 0,
    excludeds: 0,
    invalids: 0,
    skippeds: 0
  ]

  @doc """
  Create a TestRuns struct from a map.
  """
  @spec from_row([tuple()]) :: t()
  def from_row(row) do
    row
    |> Enum.into(%{}, fn {key, value} ->
      {String.to_existing_atom(key), value}
    end)
    |> then(&struct(__MODULE__, &1))
  end
end
