defmodule OpenPairingsPolis.Stations do
  @moduledoc """
  Print stations and the join links that make them.

  ## Joining

  `create_join_code/2` makes a code (16 characters of the 32-letter base32
  alphabet, valid `@code_minutes` minutes, one use, bound to a tournament)
  and stores only its SHA-256. `redeem/2` spends it and registers the
  station, handing back a key (32 random bytes, base64url) that is never
  stored either - only its SHA-256 is. A station that joins the same
  tournament again (same device id) gets its row back with a new key and
  its removal undone: joining again is the arbiter saying so.

  ## The link

  `authenticate/2` checks a station's `hello`; `connected/2`,
  `touch/1`, `put_status/2` and `disconnected/2` keep its row honest while
  the socket lives. Pages and sockets talk over `topic/1` on
  `PairingsEngine.PubSub`; there is no process of the plugin's own to talk
  through.
  """
  import Ecto.Query

  alias OpenPairingsPolis.{JoinCode, Station}
  alias PairingsEngine.Accounts.Scope
  alias PairingsEngine.Repo
  alias PairingsEngine.Tournaments
  alias PairingsEngine.Tournaments.Tournament

  @code_minutes 15
  @online_seconds 90
  @status_keys 12
  @status_value_bytes 200

  @doc "Minutes a join link stays good."
  def code_minutes, do: @code_minutes

  @doc "The plugin's own PubSub topic for one tournament: pages and sockets meet here."
  def topic(tournament_id), do: "polis:tournament:#{tournament_id}"

  @doc "Subscribes the calling process to `topic/1`."
  def subscribe(tournament_id),
    do: Phoenix.PubSub.subscribe(PairingsEngine.PubSub, topic(tournament_id))

  defp broadcast(tournament_id, message),
    do: Phoenix.PubSub.broadcast(PairingsEngine.PubSub, topic(tournament_id), message)

  @doc "SHA-256 of a secret, lowercase hex. Codes and keys are only ever stored like this."
  def hash(secret) when is_binary(secret),
    do: :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower)

  ## ---------- join codes ----------

  @doc """
  A fresh join link for `tournament`: `%{code:, url:, expires_at:}`. The
  caller has already authorised the tournament for `scope`.
  """
  def create_join_code(%Scope{} = scope, %Tournament{} = tournament) do
    code = :crypto.strong_rand_bytes(10) |> Base.encode32(case: :lower, padding: false)

    expires_at =
      DateTime.utc_now() |> DateTime.add(@code_minutes * 60, :second) |> DateTime.truncate(:second)

    %JoinCode{
      tournament_id: tournament.id,
      created_by_id: scope.user.id,
      code_hash: hash(code),
      expires_at: expires_at
    }
    |> Repo.insert!()

    {:ok, %{code: code, url: join_url(code), expires_at: expires_at}}
  end

  @doc "The absolute link a station is given: `<endpoint url>/p/polis/join/<code>`."
  def join_url(code) do
    PairingsEngineWeb.Endpoint.url() <> PairingsEngineWeb.Endpoint.path("/p/polis/join/#{code}")
  end

  @doc "The path of the link socket, as the station is told it on joining."
  def socket_path, do: PairingsEngineWeb.Endpoint.path("/p/polis/link")

  @doc "What a station shows as the server's name: the endpoint's host."
  def server_name, do: URI.parse(PairingsEngineWeb.Endpoint.url()).host || "OpenPairings"

  @doc """
  Spends `code` and registers the station `attrs` describes
  (`device`, `name`, `software`). `{:ok, station, key, tournament}`, or
  `{:error, :not_found}` for a code nobody made (or whose tournament is
  gone), `{:error, :gone}` for one used or expired.
  """
  def redeem(code, attrs) when is_binary(code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    code_hash = code |> String.trim() |> String.downcase() |> hash()

    Repo.transact(fn ->
      with {:ok, join} <- usable_code(code_hash, now),
           %Tournament{} = tournament <-
             Tournaments.get_tournament(join.tournament_id) || {:error, :not_found},
           :ok <- spend(join, now) do
        key = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        station = register!(tournament, attrs, hash(key), now)
        {:ok, {station, key, tournament}}
      end
    end)
    |> case do
      {:ok, {station, key, tournament}} ->
        broadcast(tournament.id, :polis_stations_changed)
        {:ok, station, key, tournament}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp usable_code(code_hash, now) do
    case Repo.get_by(JoinCode, code_hash: code_hash) do
      nil -> {:error, :not_found}
      %JoinCode{used_at: %DateTime{}} -> {:error, :gone}
      %JoinCode{expires_at: at} = join -> if expired?(at, now), do: {:error, :gone}, else: {:ok, join}
    end
  end

  defp expired?(at, now), do: DateTime.compare(at, now) != :gt

  # Conditional on `used_at` still being empty, so two stations racing for
  # one code cannot both win it.
  defp spend(join, now) do
    case Repo.update_all(
           from(j in JoinCode, where: j.id == ^join.id and is_nil(j.used_at)),
           set: [used_at: now]
         ) do
      {1, _} -> :ok
      _ -> {:error, :gone}
    end
  end

  defp register!(tournament, attrs, key_hash, now) do
    device = attrs.device

    fields = [
      name: attrs.name,
      software: attrs.software,
      key_hash: key_hash,
      revoked_at: nil,
      connected: false,
      connection_ref: nil,
      updated_at: now
    ]

    case Repo.get_by(Station, tournament_id: tournament.id, device_id: device) do
      nil ->
        Repo.insert!(struct!(%Station{tournament_id: tournament.id, device_id: device}, fields))

      station ->
        station |> Ecto.Changeset.change(fields) |> Repo.update!()
    end
  end

  ## ---------- the link ----------

  @doc """
  The station `device_id` holding `key`, or `{:error, :key}` for no such
  pair and `{:error, :revoked}` for a station removed in OpenPairings (or
  whose tournament went to the recycle bin). Every candidate's hash is
  compared in constant time.
  """
  def authenticate(device_id, key) when is_binary(device_id) and is_binary(key) do
    key_hash = hash(key)

    candidates = Repo.all(from s in Station, where: s.device_id == ^device_id)

    case Enum.find(candidates, &Plug.Crypto.secure_compare(&1.key_hash, key_hash)) do
      nil ->
        {:error, :key}

      %Station{revoked_at: %DateTime{}} ->
        {:error, :revoked}

      station ->
        if Tournaments.get_tournament(station.tournament_id),
          do: {:ok, station},
          else: {:error, :revoked}
    end
  end

  def authenticate(_device_id, _key), do: {:error, :key}

  @doc "Marks `station` connected by the socket that calls itself `ref`."
  def connected(%Station{} = station, ref) do
    station =
      station
      |> Ecto.Changeset.change(connected: true, connection_ref: ref, last_seen_at: now())
      |> Repo.update!()

    broadcast(station.tournament_id, :polis_stations_changed)
    station
  end

  @doc """
  Marks `station` disconnected - but only if `ref` is still the socket on
  record. A station that reconnected before its old socket noticed it was
  dead must not be marked offline by the corpse.
  """
  def disconnected(%Station{} = station, ref) do
    Repo.update_all(
      from(s in Station, where: s.id == ^station.id and s.connection_ref == ^ref),
      set: [connected: false, last_seen_at: now()]
    )

    broadcast(station.tournament_id, :polis_stations_changed)
    :ok
  end

  @doc "Writes down that `station` was heard from just now."
  def touch(%Station{} = station) do
    at = now()
    Repo.update_all(from(s in Station, where: s.id == ^station.id), set: [last_seen_at: at])
    %{station | last_seen_at: at}
  end

  @doc """
  Keeps what the station said about itself in its `status` frame: a small
  map of short values, trimmed to `@status_keys` keys of at most
  `@status_value_bytes` bytes. It is shown on a page, not trusted.
  """
  def put_status(%Station{} = station, status) when is_map(status) do
    clean =
      status
      |> Enum.reject(fn {k, _v} -> k == "type" end)
      |> Enum.filter(fn {k, v} -> is_binary(k) and byte_size(k) <= 40 and scalar?(v) end)
      |> Enum.take(@status_keys)
      |> Map.new(fn {k, v} -> {k, trim_value(v)} end)

    station =
      station
      |> Ecto.Changeset.change(status: clean, last_seen_at: now())
      |> Repo.update!()

    broadcast(station.tournament_id, :polis_stations_changed)
    station
  end

  defp scalar?(v), do: is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)

  defp trim_value(v) when is_binary(v) and byte_size(v) > @status_value_bytes,
    do: binary_part(v, 0, @status_value_bytes)

  defp trim_value(v), do: v

  @doc "Removes the station on the station's own say-so (its `leave` frame)."
  def forget(%Station{} = station) do
    Repo.delete(station)
    broadcast(station.tournament_id, :polis_stations_changed)
    :ok
  end

  ## ---------- pages ----------

  @doc "The tournament's stations still joined, by name."
  def list_stations(tournament_id) do
    Repo.all(
      from s in Station,
        where: s.tournament_id == ^tournament_id and is_nil(s.revoked_at),
        order_by: [asc: s.name, asc: s.id]
    )
  end

  @doc "Every joined station of every tournament `scope` may open, with its tournament."
  def list_for_scope(%Scope{} = scope) do
    ids = Tournaments.authorized_tournament_ids(scope)

    Repo.all(
      from s in Station,
        where: s.tournament_id in subquery(ids) and is_nil(s.revoked_at),
        order_by: [desc: s.tournament_id, asc: s.name],
        preload: [:tournament]
    )
  end

  @doc """
  Removes station `id` from `tournament`: it is told `leave` if it is
  connected and `refused revoked` the next time it calls.
  """
  def revoke(%Tournament{} = tournament, id) do
    case Repo.get_by(Station, id: id, tournament_id: tournament.id) do
      nil ->
        {:error, :not_found}

      station ->
        station =
          station
          |> Ecto.Changeset.change(revoked_at: now(), connected: false)
          |> Repo.update!()

        broadcast(tournament.id, {:polis_revoked, station.id})
        broadcast(tournament.id, :polis_stations_changed)
        {:ok, station}
    end
  end

  @doc ~s(Tells every station of the tournament to print round `round` again: "pairings", "placecards" or "both".)
  def print_again(tournament_id, round, what)
      when is_integer(round) and what in ["pairings", "placecards", "both"] do
    broadcast(tournament_id, {:polis_print, round, what})
  end

  @doc "Online: a live socket that was heard from in the last #{@online_seconds} seconds."
  def online?(%Station{connected: true, last_seen_at: %DateTime{} = at}) do
    DateTime.diff(DateTime.utc_now(), at, :second) <= @online_seconds
  end

  def online?(_station), do: false

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
