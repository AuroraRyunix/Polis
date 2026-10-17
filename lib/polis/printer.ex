defmodule Polis.Printer do
  @moduledoc """
  The road from a laid-out document to paper. One behaviour, three roads:

    * `Polis.Printer.Cups` - macOS and Linux. `lpstat` lists the printers,
      `lp` takes the PDF. CUPS, which every Mac has and every Linux with a
      printer has, does the rest with the printer's own driver.
    * `Polis.Printer.Windows` - Windows. Windows PowerShell 5.1, which every
      Windows 10 and 11 has, runs `priv/print/print.ps1`, which draws the
      layout (not the PDF) on the printer with System.Drawing and the
      printer's own Windows driver. Windows has no built-in way to print a
      PDF: printing one means handing it to whatever program is registered
      for PDFs, which may be none, a browser that opens a window, or a
      reader that shows a dialog. A headless Edge could print it, but it
      is a browser started for every page, its own print settings in the
      way, and nothing a hall PC's owner expects a print station to start.
      So on Windows the same drawing operations are drawn twice - into the
      PDF, for "Open PDF", and onto the printer - and the printed one uses
      Arial, with every character of every name.
    * `Polis.Printer.DryRun` - nothing printed: the PDF and the layout as
      JSON land in `<data>/dry-run/`. The default in development and in the
      tests, and `POLIS_PRINTER=dry-run` anywhere.

  Which one: `config :polis, :printer_backend` - a module, or `:auto` (the
  default) for the system's own.

  A job handed to `print/1`:

      %{pdf: path, layout: doc, printer: name, copies: n, title: text, paper: :a4 | :letter}
  """

  @type job :: %{
          pdf: Path.t(),
          layout: map(),
          printer: String.t(),
          copies: pos_integer(),
          title: String.t(),
          paper: :a4 | :letter
        }

  @doc "The printers this machine knows, by name."
  @callback printers() :: {:ok, [String.t()]} | {:error, String.t()}

  @doc "The system's default printer, or nil."
  @callback default_printer() :: String.t() | nil

  @doc "Prints a job. `{:error, words}` says why not, in words for the page."
  @callback print(job) :: :ok | {:error, String.t()}

  @doc "The backend in use."
  def backend do
    case Application.get_env(:polis, :printer_backend, :auto) do
      :auto -> system_backend()
      module when is_atom(module) -> module
    end
  end

  @doc "The system's own backend, whatever the configuration says."
  def system_backend(os \\ :os.type()) do
    case os do
      {:win32, _} -> Polis.Printer.Windows
      {:unix, _} -> Polis.Printer.Cups
    end
  end

  def printers, do: safely(fn -> backend().printers() end, {:error, "the printer list failed"})
  def default_printer, do: safely(fn -> backend().default_printer() end, nil)
  def print(job), do: safely(fn -> backend().print(job) end, {:error, "printing failed"})

  @doc "Whether the backend in use prints nothing (the page says so)."
  def dry_run?, do: backend() == Polis.Printer.DryRun

  defp safely(fun, fallback) do
    fun.()
  rescue
    error -> with({:error, _} <- fallback, do: {:error, Exception.message(error)})
  catch
    :exit, _reason -> fallback
  end
end
