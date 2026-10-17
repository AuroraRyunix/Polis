defmodule Polis.FakeServer.Socket do
  @moduledoc false
  @behaviour WebSock

  alias Polis.Protocol

  def init(agent) do
    me = self()
    Agent.update(agent, &%{&1 | sockets: [me | &1.sockets]})
    {:ok, %{agent: agent, hello?: false}}
  end

  def handle_in({text, opcode: :text}, state) do
    {:ok, frame} = Protocol.decode(text)
    handle(frame, state)
  end

  def handle_in(_other, state), do: {:ok, state}

  def handle_info({:push, frame}, state), do: {:push, {:text, Jason.encode!(frame)}, state}
  def handle_info(_other, state), do: {:ok, state}

  defp handle(%{"type" => "hello", "key" => key, "v" => v}, state) do
    server = Agent.get_and_update(state.agent, fn s -> {s, %{s | hellos: s.hellos + 1}} end)

    cond do
      v != 1 ->
        {:push, {:text, refused("version")}, state}

      server.revoked ->
        {:push, {:text, refused("revoked")}, state}

      key != server.key ->
        {:push, {:text, refused("key")}, state}

      true ->
        welcome =
          Jason.encode!(%{
            "type" => "welcome",
            "v" => 1,
            "server" => "fake",
            "tournament" => server.tournament
          })

        round =
          if server.round,
            do: [{:text, Jason.encode!(%{"type" => "round", "round" => server.round})}],
            else: []

        {:push, [{:text, welcome} | round], %{state | hello?: true}}
    end
  end

  defp handle(%{"type" => "status"} = frame, %{hello?: true} = state) do
    Agent.update(state.agent, &%{&1 | statuses: [Map.delete(frame, "type") | &1.statuses]})
    {:ok, state}
  end

  defp handle(%{"type" => "leave"}, state) do
    Agent.update(state.agent, &%{&1 | left?: true})
    {:ok, state}
  end

  defp handle(_frame, state), do: {:ok, state}

  defp refused(reason), do: Jason.encode!(%{"type" => "refused", "reason" => reason})

  def terminate(_reason, state) do
    me = self()
    Agent.update(state.agent, &%{&1 | sockets: List.delete(&1.sockets, me)})
    :ok
  catch
    :exit, _reason -> :ok
  end
end
