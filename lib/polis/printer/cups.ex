defmodule Polis.Printer.Cups do
  @moduledoc """
  Printing on macOS and Linux: CUPS, through its own command-line tools.

    * printers: `lpstat -e` (the destinations, one per line); where that
      flag is unknown (older CUPS), `lpstat -a` and the first word of each
      line;
    * the default: `lpstat -d` ("system default destination: NAME");
    * printing: `lp -d NAME -t TITLE -n COPIES -o media=A4|Letter FILE.pdf`.

  Every command is run with its arguments as a list (`Polis.Cmd.run/3`), never
  through a shell: a printer or tournament name with a quote or a
  semicolon in it is a name, not a command. The runner can be swapped
  (`config :polis, :cups_cmd`, a function like `System.cmd/3`, handed a
  `:timeout` too) so that the tests check the arguments without printing
  anything. Every command has a deadline and is killed past it, or when the
  station stops (`Polis.Cmd`).
  """

  @behaviour Polis.Printer

  # How long CUPS gets: to name its printers (a network printer that went
  # to sleep can keep `lpstat` thinking for a while), and to take a job.
  # Past that the command is killed and the job fails with a sentence,
  # which beats a queue that says "printing" until next week.
  @ask_ms 15_000
  @print_ms 60_000

  @impl true
  def printers do
    case run("lpstat", ["-e"], @ask_ms) do
      {out, 0} ->
        {:ok, parse_names(out)}

      _older_or_failed ->
        case run("lpstat", ["-a"], @ask_ms) do
          {out, 0} -> {:ok, parse_accepting(out)}
          {out, _status} -> {:error, trouble(out)}
        end
    end
  end

  @impl true
  def default_printer do
    case run("lpstat", ["-d"], @ask_ms) do
      {out, 0} -> parse_default(out)
      _failed -> nil
    end
  end

  @impl true
  def print(job) do
    case run("lp", print_args(job), @print_ms) do
      {_out, 0} -> :ok
      {out, _status} -> {:error, trouble(out)}
    end
  end

  @doc "The arguments of `lp` for a job."
  def print_args(job) do
    [
      "-d",
      job.printer,
      "-t",
      job.title,
      "-n",
      Integer.to_string(job.copies),
      "-o",
      "media=" <> media(job.paper),
      job.pdf
    ]
  end

  defp media(:letter), do: "Letter"
  defp media(_a4), do: "A4"

  @doc false
  def parse_names(out),
    do:
      out
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  @doc false
  def parse_accepting(out) do
    out
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, " ", parts: 2) do
        [name, _rest] when name != "" -> [name]
        _other -> []
      end
    end)
  end

  @doc false
  def parse_default(out) do
    case Regex.run(~r/default destination:\s*(\S+)/, out) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp trouble(out) do
    case String.trim(out) do
      "" -> "CUPS refused, without saying why"
      words -> String.slice(words, 0, 300)
    end
  end

  defp run(command, args, timeout) do
    runner = Application.get_env(:polis, :cups_cmd)
    opts = [stderr_to_stdout: true, timeout: timeout]

    cond do
      runner ->
        runner.(command, args, opts)

      System.find_executable(command) ->
        Polis.Cmd.run(command, args, opts)

      true ->
        {"There is no #{command} on this system: CUPS is not installed.", 127}
    end
  end
end
