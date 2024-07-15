defmodule Harness do
  @moduledoc false
  @spec file_db_path(String.t()) :: String.t()
  def file_db_path(filename \\ "test") do
    "test/support/tmp/#{filename}.sqlite3"
  end

  @spec pass :: true
  def pass, do: true

  @spec fail :: false
  def fail, do: false
end
