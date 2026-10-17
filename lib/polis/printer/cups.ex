defmodule Polis.Printer.Cups do
  @moduledoc """
  Printing on macOS and Linux: CUPS, through its own command-line tools.

    * printers: `lpstat -e` (the destinations, one per line); where that
      flag is unknown (older CUPS), `lpstat -a` and the first word of each
      line;
    * the default: `lpstat -d` ("system default destination: NAME");
    * printing: `lp -d NAME -t TITLE -n COPIES -o media=A4|Letter FILE.pdf`.

  Every command is run with its arguments as a list (`System.cmd/3`), never
  through a shell: a printer or tournament name with a quote or a
  semicolon in it is a name, not a command. The runner can be swapped
  (`config :polis, :cups_cmd`, a function like `System.cmd/3`) so that the
  tests check the arguments without printing anything.
  """

  @behaviour Polis.Printer

  @impl true
  def printers do
    case run("lpstat", ["-e"]) do
      {out, 0} ->
        {:ok, parse_names(out)}

      _older_or_failed ->
        case run("lpstat", ["-a"]) do
          {out, 0} -> {:ok, parse_accepting(out)}
          {out, _status} -> {:error, trouble(out)}
        end
    end
  end

  @impl true
  def default_printer do
    case run("lpstat", ["-d"]) do
      {out, 0} -> parse_default(out)
      _failed -> nil
    end
  end

  @impl true
  def print(job) do
    case run("lp", print_args(job)) do
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

  defp run(command, args) do
    runner = Application.get_env(:polis, :cups_cmd)

    cond do
      runner ->
        runner.(command, args, stderr_to_stdout: true)

      System.find_executable(command) ->
        System.cmd(command, args, stderr_to_stdout: true)

      true ->
        {"There is no #{command} on this system: CUPS is not installed.", 127}
    end
  end
end
