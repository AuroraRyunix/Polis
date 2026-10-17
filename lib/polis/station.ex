defmodule Polis.Station do
  @moduledoc """
  The print station, as the page and the links see it: join a tournament,
  leave one, what to do with a round that arrives, and what the station
  tells the servers about itself.

  ## What arrives, and what is printed

  A `round` from a server (`round_received/2`) is kept as that
  tournament's latest payload. Then:

    * a round number this station has not printed for that tournament:
      the pairings list (`copies` of it) and the place cards go into the
      queue, as the two switches say - both on unless somebody turned one
      off. With no printer chosen yet they wait, as "waiting for a
      printer", and go once one is chosen;
    * a round already printed, with a different `rev` (the arbiter changed
      a pairing after publishing): nothing is printed by itself. A sheet on
      the wall that changes by itself is worse than one that is old; the
      page says "changed since it was printed" and offers Reprint;
    * the same round with the same `rev` (a reconnect): nothing.

  A `print` from the server - "Print round N again" pressed in OpenPairings -
  queues what it names, for the round it names, when that is the round
  this station holds.

  ## What the station tells the servers

  `status` with `printer` (the chosen printer's name, or null) and
  `last_printed_round` (the highest round of that tournament whose
  pairings or place cards came out of the printer), after `welcome` and
  whenever either changes (`broadcast_status/0`).
  """

  alias Polis.{Join, Link, Protocol, Queue, State}

  @status_topic "station:status"
  @links_topic "station:links"

  def status_topic, do: @status_topic
  def links_topic, do: @links_topic

  # --- joining and leaving ------------------------------------------------------

  @doc """
  Joins the tournament of a join link: `{:ok, id}` or `{:error, reason}`
  (`Polis.Join.redeem/3`).
  """
  def join(link, req_options \\ []) do
    identity = %{
      "v" => Protocol.version(),
      "device" => State.device_id(),
      "name" => State.device_name(),
      "software" => Protocol.software()
    }

    with {:ok, attrs} <- Join.redeem(link, identity, req_options),
         {:ok, id} <- State.add_tournament(attrs) do
      restart_link(id)
      broadcast_links()
      {:ok, id}
    end
  end

  @doc """
  Removes a tournament here: the server is told (`leave`, when the line is
  up now), the line goes, and the tournament is forgotten. Its printed jobs
  stay in the queue's history.
  """
  def remove(id) do
    Link.leave(id)
    stop_link(id)
    State.remove_tournament(id)
    broadcast_links()
    :ok
  end

  @doc "The server removed this station: forget the tournament (called by its link)."
  def forget(id) do
    State.remove_tournament(id)
    broadcast_links()
  end

  @doc "Starts a line for every joined tournament (at start-up)."
  def start_links do
    for t <- State.tournaments(), do: restart_link(t["id"])
    :ok
  end

  def restart_link(id) do
    stop_link(id)
    DynamicSupervisor.start_child(Polis.Links, {Link, tournament: id})
  end

  defp stop_link(id) do
    case Link.whereis(id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(Polis.Links, pid)
    end
  end

  # --- rounds ---------------------------------------------------------------------

  @doc "A `round` frame's payload for tournament `id`. See the moduledoc."
  def round_received(id, %{"round" => round} = payload) when is_integer(round) do
    key = Integer.to_string(round)
    rev = payload["rev"]

    case State.tournament(id) do
      nil ->
        :ignored

      t ->
        handled = t["printed"] || %{}
        new? = not Map.has_key?(handled, key)

        {:ok, t} =
          State.update_tournament(id, fn t ->
            t = Map.merge(t, %{"payload" => payload, "last_round" => round})
            if new?, do: put_in(t, ["printed", key], rev), else: t
          end)

        if new?, do: enqueue_round(t, payload, [:pairings, :placecards])
        broadcast_links()
        if new?, do: :printing, else: :kept
    end
  end

  def round_received(_id, _payload), do: :ignored

  @doc "A `print` from the server: `what` is pairings, placecards or both."
  def print_command(id, round, what) do
    with %{"payload" => %{"round" => ^round} = payload} = t <- State.tournament(id) do
      whats =
        case what do
          "pairings" -> [:pairings]
          "placecards" -> [:placecards]
          _both -> [:pairings, :placecards]
        end

      # Asked for by name, so printed whatever the switches say.
      for w <- whats, do: Queue.enqueue(job_attrs(t, payload, w))
      :ok
    else
      _other -> :unknown_round
    end
  end

  @doc """
  Reprint of the round a tournament holds now - the pairings list and the
  place cards, whatever the switches say, since somebody asked - and the
  round counted as printed at this `rev`: the button beside "changed since
  it was printed".
  """
  def reprint_round(id) do
    with %{"payload" => %{"round" => round} = payload} = t <- State.tournament(id) do
      State.update_tournament(
        id,
        &put_in(&1, ["printed", Integer.to_string(round)], payload["rev"])
      )

      enqueue_round(t, payload, [:pairings, :placecards], force: true)
      broadcast_links()
      :ok
    else
      _other -> :nothing
    end
  end

  defp enqueue_round(t, payload, whats, opts \\ []) do
    for w <- whats, Keyword.get(opts, :force, false) or switch_on?(t, w) do
      Queue.enqueue(job_attrs(t, payload, w))
    end
  end

  defp switch_on?(t, :pairings), do: t["print_pairings"] != false
  defp switch_on?(t, :placecards), do: t["print_placecards"] != false

  defp job_attrs(t, payload, what) do
    %{
      tournament: t["id"],
      tournament_name: get_in(payload, ["tournament", "name"]) || t["name"],
      round: payload["round"],
      rev: payload["rev"],
      what: what,
      copies: if(what == :pairings, do: copies(t), else: 1),
      payload: payload
    }
  end

  defp copies(t) do
    case t["copies"] do
      n when is_integer(n) and n in 1..5 -> n
      _other -> 1
    end
  end

  @doc "Whether the round a tournament holds changed after it was printed."
  def changed_since_printed?(t) do
    with %{"round" => round, "rev" => rev} <- t["payload"],
         {:ok, printed} <- Map.fetch(t["printed"] || %{}, Integer.to_string(round)) do
      printed != rev
    else
      _ -> false
    end
  end

  # --- the switches -------------------------------------------------------------------

  def set_switch(id, which, on) when which in ["print_pairings", "print_placecards"],
    do: State.update_tournament(id, &Map.put(&1, which, on == true))

  def set_copies(id, n) when is_integer(n) and n in 1..5,
    do: State.update_tournament(id, &Map.put(&1, "copies", n))

  # --- the printer ---------------------------------------------------------------------

  @doc "The chosen printer, or nil."
  def printer, do: State.setting("printer")

  @doc "Chooses the printer: what waited for one goes, and the servers hear of it."
  def choose_printer(name) do
    name = if name in [nil, ""], do: nil, else: name
    State.put_setting("printer", name)
    if name, do: Queue.printer_chosen()
    broadcast_status()
    :ok
  end

  @doc "`a4` or `letter`."
  def paper do
    case State.setting("paper") do
      "letter" -> :letter
      _a4 -> :a4
    end
  end

  def set_paper(paper) when paper in ["a4", "letter"], do: State.put_setting("paper", paper)

  @doc "What `status` says to the server of tournament `id`."
  def status_for(id) do
    t = State.tournament(id) || %{}
    %{"printer" => printer(), "last_printed_round" => t["last_printed_round"]}
  end

  @doc "A job of tournament `id` and round `round` came out of the printer."
  def printed(id, round) when is_integer(round) do
    State.update_tournament(id, fn t ->
      Map.put(t, "last_printed_round", max(t["last_printed_round"] || 0, round))
    end)

    broadcast_status()
  end

  def printed(_id, _round), do: :ok

  def broadcast_status, do: Phoenix.PubSub.broadcast(Polis.PubSub, @status_topic, :status_changed)
  def broadcast_links, do: Phoenix.PubSub.broadcast(Polis.PubSub, @links_topic, :links_changed)

  # --- what the page shows ---------------------------------------------------------------

  @doc "The joined tournaments with their line's state."
  def overview do
    for t <- State.tournaments() do
      t
      |> Map.put("link", Link.info(t["id"]))
      |> Map.put("changed", changed_since_printed?(t))
    end
  end
end
