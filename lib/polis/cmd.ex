defmodule Polis.Cmd do
  @moduledoc """
  `System.cmd/3` with a deadline, and with an undertaker.

  `System.cmd/3` waits for as long as the program takes, and a CUPS that
  is looking for a printer somebody switched off takes a long time. Worse,
  when the process that called it is stopped - a print task at shutdown -
  Erlang closes the port and walks away: the program itself keeps running,
  outlives the server, and is found the next morning by whoever has to kill
  it by hand. So here:

    * every command has a `:timeout` (ms, default 30 seconds); a program
      still running then is killed, with what it started, and the result is
      `{output, :timeout}`, the output ending in a line that says so;
    * every program is registered with `Polis.Cmd.Reaper` while it runs,
      which kills it when its caller dies first, and kills whatever is left
      when the station stops.

  Options: `:timeout`, `:stderr_to_stdout` (as in `System.cmd/3`). Raises,
  as `System.cmd/3` does, when the program does not exist.
  """

  @default_timeout 30_000

  @doc "Runs `command` with `args`. `{output, exit_status}` or `{output, :timeout}`."
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    exe = executable(command)

    port_opts =
      [:binary, :exit_status, :hide, args: args] ++
        if(Keyword.get(opts, :stderr_to_stdout, false), do: [:stderr_to_stdout], else: [])

    port = Port.open({:spawn_executable, exe}, port_opts)
    os_pid = os_pid(port)
    if os_pid, do: Polis.Cmd.Reaper.watch(os_pid)
    deadline = System.monotonic_time(:millisecond) + timeout

    try do
      collect(port, {command, os_pid}, [], deadline, timeout)
    after
      if os_pid, do: Polis.Cmd.Reaper.unwatch(os_pid)
    end
  end

  defp collect(port, {command, os_pid} = who, acc, deadline, timeout) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, who, [acc | data], deadline, timeout)

      {^port, {:exit_status, status}} ->
        {IO.iodata_to_binary(acc), status}
    after
      left ->
        if os_pid, do: kill_tree(os_pid)
        close(port)

        note =
          "#{Path.basename(command)} gave no answer within #{div(timeout, 1000)} s and was stopped"

        {IO.iodata_to_binary([acc, "\n", note]) |> String.trim_leading(), :timeout}
    end
  end

  defp close(port) do
    if Port.info(port), do: Port.close(port)

    receive do
      {^port, _anything} -> :ok
    after
      0 -> :ok
    end
  catch
    _kind, _reason -> :ok
  end

  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      _gone -> nil
    end
  end

  defp executable(command) do
    cond do
      Path.type(command) == :absolute and File.exists?(command) -> command
      exe = System.find_executable(command) -> exe
      true -> :erlang.error(:enoent, [command])
    end
  end

  @doc """
  Kills an OS process and everything it started, at once and without
  asking: `taskkill /T /F` on Windows, `kill -KILL` on the process and
  every descendant `pgrep -P` finds elsewhere. Never raises.
  """
  def kill_tree(os_pid, os \\ :os.type())

  def kill_tree(os_pid, {:win32, _}) do
    quick("taskkill", ["/T", "/F", "/PID", Integer.to_string(os_pid)])
    :ok
  end

  def kill_tree(os_pid, _unix) do
    pids = os_pid |> descendants(8) |> Enum.map(&Integer.to_string/1)
    quick("kill", ["-KILL" | pids])
    :ok
  end

  # The process and its children, children's children..., the process first
  # (so that it cannot start another one meanwhile). Erlang puts every port
  # program in a session of its own, so a process-group kill would not
  # reach what the program started; its parentage does.
  defp descendants(pid, 0), do: [pid]

  defp descendants(pid, depth) do
    children =
      case quick("pgrep", ["-P", Integer.to_string(pid)]) do
        {out, 0} ->
          for line <- String.split(out), {child, ""} <- [Integer.parse(line)], do: child

        _none ->
          []
      end

    [pid | Enum.flat_map(children, &descendants(&1, depth - 1))]
  end

  # A small command of our own (kill, pgrep, taskkill): five seconds, no
  # registration - it is the undertaker's own shovel.
  defp quick(command, args) do
    case System.find_executable(command) do
      nil ->
        {"", 127}

      exe ->
        port =
          Port.open({:spawn_executable, exe}, [
            :binary,
            :exit_status,
            :hide,
            :stderr_to_stdout,
            args: args
          ])

        quick_collect(port, [])
    end
  catch
    _kind, _reason -> {"", 1}
  end

  defp quick_collect(port, acc) do
    receive do
      {^port, {:data, data}} -> quick_collect(port, [acc | data])
      {^port, {:exit_status, status}} -> {IO.iodata_to_binary(acc), status}
    after
      5_000 ->
        close(port)
        {IO.iodata_to_binary(acc), :timeout}
    end
  end
end
