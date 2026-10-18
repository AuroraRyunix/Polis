defmodule Polis.Cmd.Reaper do
  @moduledoc """
  Keeps a list of the OS programs the station has running (`lp`, `lpstat`,
  PowerShell) and of who is waiting for each, and kills a program whose
  caller is gone: Erlang closes a dead process's ports, but never stops the
  program on the other end of one.

  It is the first child of the tree, so it is the last to stop, and when it
  does it kills whatever is still on its list. A station that was asked to
  stop does not leave a print job behind to finish the sentence.

  Not running (a mix task, a test that did not start the station): the
  commands run anyway, without the safety net.
  """

  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Watches `os_pid`, run on behalf of `owner`."
  def watch(os_pid, owner \\ self()), do: cast({:watch, os_pid, owner})

  @doc "The program ended by itself; nothing to kill."
  def unwatch(os_pid), do: cast({:unwatch, os_pid})

  @doc "The OS pids on the list now. For tests."
  def watched do
    GenServer.call(__MODULE__, :watched)
  catch
    :exit, _not_running -> []
  end

  defp cast(message) do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, message)
    :ok
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:watch, os_pid, owner}, state) do
    {:noreply, Map.put(state, os_pid, Process.monitor(owner))}
  end

  def handle_cast({:unwatch, os_pid}, state) do
    case Map.pop(state, os_pid) do
      {nil, state} ->
        {:noreply, state}

      {ref, state} ->
        Process.demonitor(ref, [:flush])
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:watched, _from, state), do: {:reply, Map.keys(state), state}

  @impl true
  def handle_info({:DOWN, ref, :process, _owner, _reason}, state) do
    {orphans, state} = Enum.split_with(state, fn {_os_pid, r} -> r == ref end)
    for {os_pid, _ref} <- orphans, do: Polis.Cmd.kill_tree(os_pid)
    {:noreply, Map.new(state)}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    for {os_pid, _ref} <- state, do: Polis.Cmd.kill_tree(os_pid)
    :ok
  end
end
