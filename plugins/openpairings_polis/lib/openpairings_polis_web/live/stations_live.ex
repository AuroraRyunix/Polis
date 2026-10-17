defmodule OpenPairingsPolisWeb.StationsLive do
  @moduledoc """
  The print station pages.

    * `/p/polis` (`:index`) - this account's stations across every
      tournament it can open, or a short word on what a print station is.
    * `/p/polis/tournaments/:id` (`:show`) - the tournament's stations
      (online or not, last seen, what each said about its printer), "Add a
      print station" (a one-time link and its QR code), Remove, and "Print
      round N again".

  Admin-only and signed-in by the core (`:plugins` live_session). Pages and
  stations meet on `OpenPairingsPolis.Stations.topic/1`; nothing here
  holds a socket.
  """
  use OpenPairingsPolisWeb, :live_view

  alias OpenPairingsPolis.{Plugin, Stations}
  alias PairingsEngine.{Features, Tournaments}

  # Online/offline is a matter of time passing, so the page looks again
  # now and then even when nobody says anything.
  @tick_ms 15_000

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: gettext("Print station"),
       enabled?: Features.enabled?(scope, Plugin.feature()),
       tournament: nil,
       join: nil,
       latest_round: 0,
       station_count: 0,
       note: nil,
       error: nil,
       print_form: to_form(%{"what" => "both"}, as: :print)
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    tournament = Tournaments.get_authorized_tournament!(socket.assigns.current_scope, id)

    if connected?(socket) do
      Stations.subscribe(tournament.id)
      Phoenix.PubSub.subscribe(PairingsEngine.PubSub, Tournaments.tournament_topic(tournament.id))
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:noreply,
     socket
     |> assign(tournament: tournament, page_title: gettext("Print station"))
     |> assign_latest_round()
     |> load_stations()}
  end

  def handle_params(_params, _uri, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, @tick_ms)
    {:noreply, load_stations(socket)}
  end

  defp assign_latest_round(socket),
    do:
      assign(socket,
        latest_round: Tournaments.latest_published_round_number(socket.assigns.tournament)
      )

  defp load_stations(%{assigns: %{tournament: nil}} = socket) do
    stations = Stations.list_for_scope(socket.assigns.current_scope)

    socket
    |> assign(station_count: length(stations))
    |> stream(:stations, stations, reset: true)
  end

  defp load_stations(socket) do
    stations = Stations.list_stations(socket.assigns.tournament.id)

    socket
    |> assign(station_count: length(stations))
    |> stream(:stations, stations, reset: true)
  end

  ## ---------- events ----------

  # The buttons are not drawn without the feature; a button not drawn is
  # still an event anybody can send.
  @impl true
  def handle_event(_event, _params, %{assigns: %{enabled?: false}} = socket),
    do: {:noreply, assign(socket, error: gettext("The print station is switched off for your account."))}

  def handle_event("add_station", _params, socket) do
    {:ok, join} = Stations.create_join_code(socket.assigns.current_scope, socket.assigns.tournament)

    {:noreply,
     assign(socket,
       join: Map.put(join, :qr, PairingsEngine.Mobile.qr_svg(join.url)),
       note: nil,
       error: nil
     )}
  end

  def handle_event("close_join", _params, socket), do: {:noreply, assign(socket, join: nil)}

  def handle_event("remove_station", %{"id" => id}, socket) do
    case Stations.revoke(socket.assigns.tournament, id) do
      {:ok, _station} ->
        {:noreply,
         socket
         |> assign(note: gettext("Print station removed."), error: nil)
         |> load_stations()}

      {:error, :not_found} ->
        {:noreply, assign(socket, error: gettext("That print station is not there any more."))}
    end
  end

  def handle_event("print_again", %{"print" => %{"what" => what}}, socket)
      when what in ["pairings", "placecards", "both"] do
    case socket.assigns.latest_round do
      0 ->
        {:noreply, assign(socket, error: gettext("No round is published yet."), note: nil)}

      n ->
        Stations.print_again(socket.assigns.tournament.id, n, what)

        {:noreply,
         assign(socket,
           note: gettext("Sent to every print station that is online: round %{n}.", n: n),
           error: nil,
           print_form: to_form(%{"what" => what}, as: :print)
         )}
    end
  end

  def handle_event("print_again", _params, socket), do: {:noreply, socket}

  ## ---------- messages ----------

  @impl true
  def handle_info(:polis_stations_changed, socket), do: {:noreply, load_stations(socket)}

  def handle_info({:tournament_changed, _tid, _hint}, socket),
    do: {:noreply, assign_latest_round(socket)}

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, load_stations(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## ---------- view ----------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      publish_status={assigns[:publish_status]}
      update_notice={assigns[:update_notice]}
      flash={@flash}
      current_path={assigns[:current_path]}
      current_scope={@current_scope}
      tournament={@tournament}
      active="plugin:polis"
    >
      <div class="page-header">
        <div>
          <h1>{gettext("Print station")}</h1>
          <p class="subtitle" style="margin: 0">
            <%= if @tournament do %>
              {gettext(
                "A PC in the hall with a printer. When you publish a round of %{name}, every print station below prints the pairings and the place cards.",
                name: @tournament.name
              )}
            <% else %>
              {gettext(
                "A print station is a PC in the playing hall with a printer and the Polis program on it. Join it to a tournament from that tournament's menu, under Print station, and it prints every round the moment you publish it."
              )}
            <% end %>
          </p>
        </div>
      </div>

      <p id="polis-note" role="status" aria-live="polite" class={@note && "ok-note"}>{@note}</p>
      <p :if={@error} id="polis-error" role="alert" class="error-note">{@error}</p>

      <section :if={!@enabled?} id="polis-not-enabled" class="card">
        <p class="hint">
          {gettext("The print station is switched off for your account.")}
          <.link navigate="/users/features" id="polis-features-link">
            {gettext("Switch it on in your settings.")}
          </.link>
        </p>
      </section>

      <%= if @tournament do %>
        <section :if={@enabled?} id="polis-add" class="card">
          <h2>{gettext("Add a print station")}</h2>
          <p class="hint">
            {gettext(
              "Open Polis on the hall PC, paste the link (or scan the code) and press Join. The link works once, for %{minutes} minutes.",
              minutes: Stations.code_minutes()
            )}
          </p>

          <%= if @join do %>
            <div id="polis-join" class="polis-join" style="display: flex; flex-wrap: wrap; gap: 20px; align-items: flex-start">
              <div
                id="polis-join-qr"
                style="background: #fff; padding: 8px; border-radius: 8px; line-height: 0"
              >
                {Phoenix.HTML.raw(@join.qr)}
              </div>
              <div style="flex: 1 1 280px; min-width: 0">
                <label for="polis-join-url" class="hint">{gettext("Join link")}</label>
                <div style="display: flex; gap: 8px; margin-top: 4px">
                  <input
                    id="polis-join-url"
                    type="text"
                    readonly
                    value={@join.url}
                    style="flex: 1; min-width: 0; font-family: ui-monospace, monospace"
                  />
                  <button
                    type="button"
                    id="polis-copy-link"
                    class="pe-btn"
                    phx-hook=".CopyJoinLink"
                    data-target="polis-join-url"
                    data-done={gettext("Copied")}
                  >
                    {gettext("Copy")}
                  </button>
                </div>
                <p class="hint" id="polis-join-expiry" style="margin-top: 8px">
                  {gettext("Valid until %{time} UTC, for one print station.",
                    time: Calendar.strftime(@join.expires_at, "%H:%M")
                  )}
                </p>
                <div class="actions">
                  <button type="button" class="pe-btn" id="polis-new-link" phx-click="add_station">
                    {gettext("Make a new link")}
                  </button>
                  <button type="button" class="pe-btn" id="polis-close-link" phx-click="close_join">
                    {gettext("Done")}
                  </button>
                </div>
              </div>
            </div>
          <% else %>
            <div class="actions">
              <button
                type="button"
                class="pe-btn primary"
                id="polis-add-station"
                phx-click="add_station"
              >
                {gettext("Add a print station")}
              </button>
            </div>
          <% end %>
        </section>

        <section :if={@enabled? and @station_count > 0} id="polis-print-again" class="card">
          <h2>{gettext("Print again")}</h2>
          <%= if @latest_round > 0 do %>
            <.form
              for={@print_form}
              id="polis-print-form"
              phx-submit="print_again"
              class="form-grid"
            >
              <.input
                field={@print_form[:what]}
                type="select"
                label={gettext("What")}
                options={[
                  {gettext("Pairings and place cards"), "both"},
                  {gettext("Pairings"), "pairings"},
                  {gettext("Place cards"), "placecards"}
                ]}
              />
              <div class="actions">
                <button type="submit" class="pe-btn" id="polis-print-button">
                  {gettext("Print round %{n} again", n: @latest_round)}
                </button>
              </div>
            </.form>
          <% else %>
            <p class="hint" id="polis-nothing-published">
              {gettext("No round is published yet. The first one prints by itself.")}
            </p>
          <% end %>
        </section>
      <% end %>

      <section id="polis-stations-card" class="card">
        <h2>{gettext("Print stations")}</h2>
        <p :if={@station_count == 0} id="polis-no-stations" class="hint">
          {gettext("No print station has joined yet.")}
        </p>
        <div id="polis-stations" phx-update="stream">
          <article
            :for={{dom_id, s} <- @streams.stations}
            id={dom_id}
            class="polis-station"
            style="display: flex; flex-wrap: wrap; gap: 12px; align-items: center; justify-content: space-between; border-top: 1px solid var(--pe-border, #ddd); padding: 12px 0"
          >
            <div style="min-width: 0">
              <p style="margin: 0">
                <span
                  id={"#{dom_id}-state"}
                  class={["polis-dot", if(Stations.online?(s), do: "ok-note", else: "hint")]}
                  style="font-weight: 600"
                >
                  {if Stations.online?(s), do: gettext("Online"), else: gettext("Offline")}
                </span>
                <strong>&nbsp;{s.name}</strong>
                <span :if={!@tournament} class="hint">
                  &middot;
                  <.link navigate={"/p/polis/tournaments/#{s.tournament_id}"}>
                    {s.tournament.name}
                  </.link>
                </span>
              </p>
              <p class="hint" style="margin: 2px 0 0">
                {seen_text(s.last_seen_at)}
                <span :if={s.status["printer"]}>
                  &middot; {gettext("Printer: %{printer}", printer: s.status["printer"])}
                </span>
                <span :if={s.status["last_printed_round"]} id={"#{dom_id}-printed"}>
                  &middot; {gettext("Last printed: round %{n}", n: s.status["last_printed_round"])}
                </span>
              </p>
            </div>
            <button
              :if={@tournament && @enabled?}
              type="button"
              class="pe-btn"
              id={"#{dom_id}-remove"}
              phx-click="remove_station"
              phx-value-id={s.id}
              data-confirm={gettext("Remove this print station? It stops printing for this tournament.")}
            >
              {gettext("Remove")}
            </button>
          </article>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyJoinLink">
        // Copies the join link. The clipboard API wants a secure context;
        // the fallback selects the text, which is half the job done anyway.
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const input = document.getElementById(this.el.dataset.target)
              if (!input) return
              const done = () => {
                const label = this.el.textContent
                this.el.textContent = this.el.dataset.done
                setTimeout(() => { this.el.textContent = label }, 1500)
              }
              input.select()
              if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(input.value).then(done, () => {})
              } else if (document.execCommand && document.execCommand("copy")) {
                done()
              }
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp seen_text(nil), do: gettext("Never seen")

  defp seen_text(at) do
    seconds = max(DateTime.diff(DateTime.utc_now(), at, :second), 0)

    cond do
      seconds < 60 -> gettext("Seen just now")
      seconds < 3600 -> gettext("Seen %{n} min ago", n: div(seconds, 60))
      true -> gettext("Last seen %{time} UTC", time: Calendar.strftime(at, "%Y-%m-%d %H:%M"))
    end
  end
end
