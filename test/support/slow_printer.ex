defmodule Polis.SlowPrinter do
  @moduledoc "A printer that takes two seconds to answer: a job that stays \"printing\"."
  @behaviour Polis.Printer
  def printers, do: {:ok, ["Hall printer"]}
  def default_printer, do: nil

  def print(_job) do
    receive do
    after
      2_000 -> :ok
    end
  end
end
