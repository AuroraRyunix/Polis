defmodule Polis.RecordingPrinter do
  @moduledoc """
  A printer for the tests that remembers instead of printing: each job is
  sent as `{:printed, job}` to the process named by `listen/0`, and
  `fail/1` makes the next jobs fail with the given words. It offers two
  printers and says neither is the default.
  """

  @behaviour Polis.Printer

  @doc "Makes this the printer road, and the calling test the one that hears of each job."
  def install do
    Application.put_env(:polis, :printer_backend, __MODULE__)
    listen()
  end

  def uninstall do
    Application.put_env(:polis, :printer_backend, Polis.Printer.DryRun)
    :persistent_term.erase({__MODULE__, :listener})
    :persistent_term.erase({__MODULE__, :fail})
  end

  def listen, do: :persistent_term.put({__MODULE__, :listener}, self())
  def fail(words), do: :persistent_term.put({__MODULE__, :fail}, words)
  def succeed, do: :persistent_term.erase({__MODULE__, :fail})

  @impl true
  def printers, do: {:ok, ["Hall printer", "Office printer"]}

  @impl true
  def default_printer, do: nil

  @impl true
  def print(job) do
    if pid = :persistent_term.get({__MODULE__, :listener}, nil), do: send(pid, {:printed, job})

    case :persistent_term.get({__MODULE__, :fail}, nil) do
      nil -> :ok
      words -> {:error, words}
    end
  end
end
