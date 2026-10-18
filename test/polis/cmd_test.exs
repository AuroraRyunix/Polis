defmodule Polis.CmdTest do
  @moduledoc """
  Commands with a deadline, programs that do not outlive whoever waited for
  them, and a station that stops in seconds with a printer command stuck.

  The stuck command is `sleep` (`ping` on Windows): a program that takes
  thirty seconds and prints nothing, which is what `lp` looks like to a
  printer that went to sleep. Nothing is printed.
  """

  use Polis.StationCase, async: false

  alias Polis.Cmd

  defp slow do
    case :os.type() do
      {:win32, _} -> {"ping", ["-n", "30", "127.0.0.1"]}
      _unix -> {"sleep", ["30"]}
    end
  end

  defp quick do
    case :os.type() do
      {:win32, _} -> {"cmd", ["/c", "echo", "hello"]}
      _unix -> {"sh", ["-c", "echo hello"]}
    end
  end

  defp alive?(os_pid) do
    case :os.type() do
      {:win32, _} ->
        {out, _} = System.cmd("tasklist", ["/FI", "PID eq #{os_pid}", "/NH"])
        out =~ ~r/\b#{os_pid}\b/

      _unix ->
        match?({_, 0}, System.cmd("kill", ["-0", "#{os_pid}"], stderr_to_stdout: true))
    end
  end

  defp gone?(os_pid), do: eventually(fn -> not alive?(os_pid) end, 5_000)

  test "a command that answers: its output and its status" do
    {exe, args} = quick()
    assert {out, 0} = Cmd.run(exe, args, timeout: 10_000)
    assert out =~ "hello"
    assert Polis.Cmd.Reaper.watched() == []
  end

  test "a command that does not: stopped at the deadline, and killed" do
    {exe, args} = slow()
    started = System.monotonic_time(:millisecond)
    me = self()

    task =
      Task.async(fn ->
        send(me, :running)
        Cmd.run(exe, args, timeout: 500)
      end)

    assert_receive :running

    [os_pid] =
      eventually(fn -> match?([_], Polis.Cmd.Reaper.watched()) && Polis.Cmd.Reaper.watched() end)

    assert {out, :timeout} = Task.await(task, 5_000)
    assert out =~ "gave no answer"
    assert System.monotonic_time(:millisecond) - started < 4_000
    assert gone?(os_pid)
  end

  test "a caller that dies: its program dies with it" do
    {exe, args} = slow()
    pid = spawn(fn -> Cmd.run(exe, args, timeout: 60_000) end)

    [os_pid] =
      eventually(fn -> match?([_], Polis.Cmd.Reaper.watched()) && Polis.Cmd.Reaper.watched() end)

    Process.exit(pid, :kill)
    assert gone?(os_pid)
    eventually(fn -> Polis.Cmd.Reaper.watched() == [] end)
  end

  test "a program that does not exist raises, as System.cmd does" do
    assert_raise ErlangError, fn -> Cmd.run("polis-no-such-program", []) end
  end

  describe "stopping the station" do
    setup do
      on_exit(fn ->
        Application.delete_env(:polis, :cups_cmd)
        Application.put_env(:polis, :printer_backend, Polis.Printer.DryRun)
        {:ok, _} = Application.ensure_all_started(:polis)
      end)
    end

    test "with lp stuck on a printer: over in seconds, and lp with it" do
      {exe, args} = slow()

      # The real road (Polis.Printer.Cups and Polis.Cmd), with `lp` swapped
      # for a program that never finishes.
      Application.put_env(:polis, :printer_backend, Polis.Printer.Cups)
      Application.put_env(:polis, :cups_cmd, fn _lp, _args, opts -> Cmd.run(exe, args, opts) end)

      Station.choose_printer("Hall printer")
      Queue.test_print()

      [os_pid] =
        eventually(fn ->
          match?([_], Polis.Cmd.Reaper.watched()) && Polis.Cmd.Reaper.watched()
        end)

      assert Enum.any?(Queue.jobs(), &(&1.status == :printing))

      {microseconds, :ok} = :timer.tc(fn -> Application.stop(:polis) end)
      assert div(microseconds, 1000) < 3_000
      assert gone?(os_pid)
    end
  end
end
