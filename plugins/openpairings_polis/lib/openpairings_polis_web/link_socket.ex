defmodule OpenPairingsPolisWeb.LinkSocket do
  @moduledoc """
  The server end of a print station's link (`WebSock`), one process per
  connected station, upgraded by `OpenPairingsPolisWeb.LinkPlug`. Frames
  are the hall-link protocol's, version 1 (`docs/protocol.md` in the Polis
  repository).

  The first frame must be `hello` with the station's key; until then
  nothing else is listened to, and a link that says nothing for ten
  seconds is closed. After `welcome` the station gets the latest published
  round, if there is one.

  It listens on two topics: the core's tournament topic, where any change
  at all is a nudge to look again (debounced, `@debounce_ms`), and the
  plugin's own (`OpenPairingsPolis.Stations.topic/1`), where the page says
  "print again" or "this one was removed". A round goes out only when its
  `rev` differs from the last one this socket sent, and never when it is
  older than that: a round taken back is simply not news.
  """
  @behaviour WebSock

  alias OpenPairingsPolis.{RoundPayload, Stations}
  alias PairingsEngine.Tournaments

  @protocol 1
  @hello_ms 10_000
  @debounce_ms 300
  @idle_check_ms 30_000
  # The station pings every 25 s; three missed is a station that is gone.
  @silence_ms 90_000
  # last_seen_at is written at most this often; "online" allows 90 s.
  @touch_ms 20_000

  @impl true
  def init(_args) do
    Process.send_after(self(), :hello_timeout, @hello_ms)
    Process.send_after(self(), :idle_check, @idle_check_ms)

    {:ok,
     %{
       station: nil,
       ref: :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false),
       last_rev: nil,
       last_round: 0,
       timer: nil,
       heard: now_ms(),
       touched: now_ms()
     }}
  end

  ## ---------- frames in ----------

  @impl true
  def handle_in({text, _opts}, state) do
    state = %{state | heard: now_ms()}

    case Jason.decode(text) do
      {:ok, %{"type" => _} = frame} -> frame(frame, state)
      _ -> {:ok, state}
    end
  end

  defp frame(%{"type" => "hello"} = hello, %{station: nil} = state) do
    with :ok <- version(hello["v"]),
         {:ok, station} <- Stations.authenticate(hello["device"], hello["key"]) do
      welcome(station, state)
    else
      {:error, reason} -> refuse(reason, state)
    end
  end

  # Nothing but hello before hello.
  defp frame(_frame, %{station: nil} = state), do: {:ok, state}

  defp frame(%{"type" => "status"} = status, state) do
    {:ok, %{state | station: Stations.put_status(state.station, status), touched: now_ms()}}
  end

  # Removed on the station: removed here too.
  defp frame(%{"type" => "leave"}, state) do
    Stations.forget(state.station)
    {:stop, :normal, %{state | station: nil}}
  end

  defp frame(%{"type" => "ping"}, state), do: push([%{type: "pong"}], touch(state))

  defp frame(_other, state), do: {:ok, state}

  defp version(@protocol), do: :ok
  defp version(_v), do: {:error, :version}

  defp welcome(station, state) do
    station = Stations.connected(station, state.ref)
    tournament = Tournaments.get_tournament!(station.tournament_id)

    Phoenix.PubSub.subscribe(PairingsEngine.PubSub, Tournaments.tournament_topic(tournament.id))
    Stations.subscribe(tournament.id)

    welcome = %{
      type: "welcome",
      v: @protocol,
      server: Stations.server_name(),
      tournament: %{id: tournament.id, name: tournament.name}
    }

    state = %{state | station: station, touched: now_ms()}
    {rounds, state} = round_frames(state)
    push([welcome | rounds], state)
  end

  defp refuse(reason, state) do
    frame = %{type: "refused", reason: to_string(reason)}
    {:stop, :normal, 1000, [encode(frame)], state}
  end

  ## ---------- control frames ----------

  @impl true
  def handle_control({_payload, _opts}, state) do
    state = %{state | heard: now_ms()}
    {:ok, if(state.station, do: touch(state), else: state)}
  end

  ## ---------- messages ----------

  @impl true
  def handle_info(:hello_timeout, %{station: nil} = state), do: {:stop, :normal, state}
  def handle_info(:hello_timeout, state), do: {:ok, state}

  def handle_info(:idle_check, state) do
    if now_ms() - state.heard > @silence_ms do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :idle_check, @idle_check_ms)
      {:ok, state}
    end
  end

  def handle_info({:tournament_changed, tid, _hint}, %{station: %{tournament_id: tid}} = state) do
    timer = state.timer || Process.send_after(self(), :recompute, @debounce_ms)
    {:ok, %{state | timer: timer}}
  end

  def handle_info(:recompute, %{station: nil} = state), do: {:ok, %{state | timer: nil}}

  def handle_info(:recompute, state) do
    {frames, state} = round_frames(%{state | timer: nil})
    push(frames, state)
  end

  # "Print again": make sure the station has the round as it stands now,
  # then ask for the print.
  def handle_info({:polis_print, round, what}, %{station: %{}} = state) do
    {frames, state} = round_frames(state)
    push(frames ++ [%{type: "print", round: round, what: what}], state)
  end

  def handle_info({:polis_revoked, id}, %{station: %{id: id}} = state) do
    {:stop, :normal, 1000, [encode(%{type: "leave"})], state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{station: %{} = station, ref: ref}) do
    Stations.disconnected(station, ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## ---------- rounds ----------

  # The latest published round, as frames to send: none when nothing is
  # public, when it is older than what this socket already sent, or when
  # its rev is the one sent last.
  defp round_frames(state) do
    with %{} = tournament <- Tournaments.get_tournament(state.station.tournament_id),
         {:ok, number, payload} <- RoundPayload.latest(tournament),
         true <- number >= state.last_round,
         false <- payload["rev"] == state.last_rev do
      {[%{type: "round", round: payload}], %{state | last_rev: payload["rev"], last_round: number}}
    else
      _ -> {[], state}
    end
  end

  ## ---------- helpers ----------

  defp push([], state), do: {:ok, state}
  defp push(frames, state), do: {:push, Enum.map(frames, &encode/1), state}

  defp encode(frame), do: {:text, Jason.encode!(frame)}

  defp touch(state) do
    if now_ms() - state.touched >= @touch_ms do
      %{state | station: Stations.touch(state.station), touched: now_ms()}
    else
      state
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
