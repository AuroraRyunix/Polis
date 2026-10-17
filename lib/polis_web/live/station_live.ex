defmodule PolisWeb.StationLive do
  @moduledoc """
  The station's page: the tournaments it is joined to, the field that joins
  one, the printer and the paper, and the queue. In English or Dutch; the
  help is `PolisWeb.HelpLive`.

  Most of what it shows changes by itself (a round arrives, a job comes
  out, a line drops), so it listens to the queue, the state and the lines,
  and looks again every two seconds for what nobody announces (a line that
  is still trying).

  Two buttons here can make paper come out: "Test print" and "Reprint".
  Both are a person's click. Everything else that prints is the station
  doing what the switches say.
  """

  use PolisWeb, :live_view

  alias Polis.{Autostart, Printer, Queue, State, Station, Updates}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        :timer.send_interval(2_000, :refresh)

        for topic <- [Queue.topic(), State.topic(), Station.links_topic(), Updates.topic()],
            do: Phoenix.PubSub.subscribe(Polis.PubSub, topic)

        start_async(socket, :printers, &list_printers/0)
      else
        socket
      end

    {:ok,
     socket
     |> assign(
       join_form: to_form(%{"link" => ""}, as: :join),
       joining?: false,
       message: nil,
       update_message: nil,
       checking?: false,
       printers: nil,
       printers_error: nil
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}
  def handle_info(:queue_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:state_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:links_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:update_changed, socket), do: {:noreply, load(socket)}
  def handle_info(_other, socket), do: {:noreply, socket}

  # --- joining ------------------------------------------------------------------------

  @impl true
  def handle_event("join", %{"join" => %{"link" => link}}, socket) do
    {:noreply,
     socket
     |> assign(joining?: true, message: nil, join_form: to_form(%{"link" => link}, as: :join))
     |> start_async(:join, fn -> Station.join(String.trim(link)) end)}
  end

  def handle_event("remove", %{"id" => id}, socket) do
    if State.tournament(id), do: Station.remove(id)
    {:noreply, load(socket)}
  end

  # --- per tournament -------------------------------------------------------------------

  def handle_event("switch", %{"id" => id, "which" => which} = params, socket)
      when which in ["print_pairings", "print_placecards"] do
    if State.tournament(id), do: Station.set_switch(id, which, params["on"] == "true")
    {:noreply, load(socket)}
  end

  def handle_event("copies", %{"tournament" => id, "copies" => copies}, socket) do
    with %{} <- State.tournament(id),
         {n, ""} when n in 1..5 <- Integer.parse(copies) do
      Station.set_copies(id, n)
    end

    {:noreply, load(socket)}
  end

  def handle_event("reprint_round", %{"id" => id}, socket) do
    if State.tournament(id), do: Station.reprint_round(id)
    {:noreply, load(socket)}
  end

  # --- the printer ------------------------------------------------------------------------

  def handle_event("printer", params, socket) do
    known = socket.assigns.printers || []
    printer = params["printer"]

    # Only a name the list offered (or none): the page is not a way to send
    # jobs to whatever a crafted request names.
    if printer != Station.printer() and (printer == "" or printer in known),
      do: Station.choose_printer(printer)

    if params["paper"] in ["a4", "letter"], do: Station.set_paper(params["paper"])
    {:noreply, load(socket)}
  end

  def handle_event("refresh_printers", _params, socket),
    do: {:noreply, start_async(socket, :printers, &list_printers/0)}

  def handle_event("test_print", _params, socket) do
    Queue.test_print()
    {:noreply, load(socket)}
  end

  # --- the queue ------------------------------------------------------------------------------

  def handle_event("reprint_job", %{"id" => id}, socket) do
    Queue.reprint(id)
    {:noreply, load(socket)}
  end

  # --- the program ------------------------------------------------------------------------------

  def handle_event("update", _params, socket) do
    case Updates.apply() do
      :ok ->
        {:noreply,
         assign(socket,
           update_message:
             {:ok, gettext("Updating. This page reconnects when the station is back.")}
         )}

      {:error, :busy} ->
        {:noreply,
         assign(socket,
           update_message: {:error, gettext("A sheet is printing. Try again when it is out.")}
         )}

      {:error, _reason} ->
        {:noreply, socket |> assign(update_message: nil) |> load()}
    end
  end

  def handle_event("later", %{"version" => version}, socket) do
    Updates.later(version)
    {:noreply, load(socket)}
  end

  def handle_event("update_check", params, socket) do
    Updates.put_mode(if(params["on"] == "true", do: "ask", else: "never"))
    {:noreply, load(socket)}
  end

  def handle_event("check_now", _params, socket) do
    {:noreply,
     socket
     |> assign(checking?: true, update_message: nil)
     |> start_async(:check, fn -> Updates.Checker.check_now() end)}
  end

  def handle_event("autostart", params, socket) do
    case Autostart.set(params["on"] == "true") do
      :ok ->
        {:noreply, load(socket)}

      {:error, _words} ->
        {:noreply,
         assign(socket, update_message: {:error, gettext("Windows would not take that setting.")})}
    end
  end

  # --- what came back --------------------------------------------------------------------------

  @impl true
  def handle_async(:join, {:ok, {:ok, _id}}, socket) do
    {:noreply,
     socket
     |> assign(
       joining?: false,
       message: {:ok, gettext("Joined. The next published round prints by itself.")},
       join_form: to_form(%{"link" => ""}, as: :join)
     )
     |> load()}
  end

  def handle_async(:join, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, joining?: false, message: {:error, join_error(reason)})}

  def handle_async(:join, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, joining?: false, message: {:error, join_error(:unreachable)})}

  def handle_async(:printers, {:ok, {:ok, names}}, socket),
    do: {:noreply, assign(socket, printers: names, printers_error: nil)}

  def handle_async(:printers, {:ok, {:error, words}}, socket),
    do: {:noreply, assign(socket, printers: [], printers_error: words)}

  def handle_async(:printers, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, printers: [], printers_error: "?")}

  def handle_async(:check, {:ok, answer}, socket) do
    message =
      case answer do
        {:ok, _info} -> nil
        :current -> {:ok, gettext("This is the newest version.")}
        :error -> {:error, gettext("Could not reach the release page.")}
      end

    {:noreply, socket |> assign(checking?: false, update_message: message) |> load()}
  end

  def handle_async(:check, {:exit, _reason}, socket),
    do:
      {:noreply,
       assign(socket,
         checking?: false,
         update_message: {:error, gettext("Could not reach the release page.")}
       )}

  defp list_printers do
    case Printer.printers() do
      {:ok, names} -> {:ok, names}
      {:error, words} -> {:error, words}
    end
  end

  defp join_error(:not_a_link),
    do: gettext("That is not a join link. It looks like https://server/p/polis/join/K7Q-4MD.")

  defp join_error({:wrong_product, _product}),
    do:
      gettext(
        "That link is for another hall program, not for a print station. In OpenPairings, add a print station and use its link."
      )

  defp join_error(:used_or_expired),
    do: gettext("That link is used up or expired. Make a new one in OpenPairings.")

  defp join_error(:version),
    do: gettext("That server speaks another version of the link. Update one of the two.")

  defp join_error(:unreachable), do: gettext("The server in that link does not answer from here.")

  defp join_error(_other),
    do: gettext("That address answered, but not like an OpenPairings server.")

  @doc false
  def link_error(nil), do: nil
  def link_error(:nobody_answers), do: gettext("nobody answers at that address")
  def link_error(:no_such_address), do: gettext("that address does not exist")
  def link_error(:timeout), do: gettext("no answer in time")
  def link_error(:closed), do: gettext("the server closed the line")
  def link_error(:silent), do: gettext("the server went quiet")
  def link_error(:not_a_link), do: gettext("that address does not take a line")

  def link_error({:refused, "version"}),
    do: gettext("refused: another version of the link; update one of the two")

  def link_error({:refused, "key"}),
    do: gettext("refused: the server does not know this station's key; trying again in a minute")

  def link_error({:refused, _other}), do: gettext("refused; trying again in a minute")
  def link_error(_other), do: gettext("the line went down; trying again")

  defp load(socket) do
    assign(socket,
      tournaments: safe(&Station.overview/0, []),
      jobs: safe(&Queue.jobs/0, []),
      printer: safe(&Station.printer/0, nil),
      paper: safe(&Station.paper/0, :a4),
      dry_run?: Printer.dry_run?(),
      notice: Updates.notice(),
      install_kind: Updates.install_kind(),
      update_mode: Updates.mode(),
      last_update: Updates.last_result(),
      autostart?: Autostart.supported?() and Autostart.enabled?()
    )
  end

  defp safe(fun, default) do
    fun.()
  catch
    :exit, _reason -> default
  end

  defp megabytes(bytes), do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 1)

  defp held_round(t), do: get_in(t, ["payload", "round"])

  defp time(nil), do: ""
  defp time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} page={:station}>
      <section :if={@notice} id="update">
        <h2>{gettext("Polis %{version} is out.", version: @notice.version)}</h2>
        <p :if={@notice.size} class="note">
          {gettext("The download is %{mb} MB.", mb: megabytes(@notice.size))}
        </p>
        <p :if={@install_kind != :manual} class="note">
          {gettext(
            "Nothing prints for about a minute while it installs. It waits for a sheet that is printing."
          )}
        </p>
        <p :if={@install_kind == :manual && !@notice.no_build} class="note">
          {gettext("This copy is updated by hand: download the new one and replace this.")}
        </p>
        <p :if={@notice.no_build} class="note">
          {gettext("There is no build for this machine.")}
        </p>
        <form id="update-form" phx-submit="update">
          <button :if={@install_kind != :manual} id="update-button" type="submit">
            {gettext("Download and install")}
          </button>
          <a
            :if={@install_kind == :manual && !@notice.no_build}
            id="update-link"
            href={@notice.url}
            rel="noopener"
          >
            {gettext("Releases")}
          </a>
          <button
            id="update-later"
            type="button"
            phx-click="later"
            phx-value-version={@notice.version}
          >
            {gettext("Later")}
          </button>
        </form>
      </section>

      <p :if={match?({:failed, _, _}, @last_update)} id="update-failed" class="error">
        {gettext("The last update, to %{version}, did not work: %{why}",
          version: elem(@last_update, 1),
          why: elem(@last_update, 2)
        )}
      </p>

      <section id="tournaments">
        <h2>{gettext("Tournaments")}</h2>
        <p :if={@tournaments == []} id="no-tournaments" class="note">
          {gettext("Joined to no tournament yet. Paste a join link below.")}
        </p>
        <ul :if={@tournaments != []} id="tournament-list">
          <li :for={t <- @tournaments} id={"tournament-#{t["id"]}"} class="tournament">
            <div class="row">
              <span
                class={["dot", if(t["link"].up?, do: "up", else: "down")]}
                title={if(t["link"].up?, do: gettext("connected"), else: gettext("not connected"))}
              ></span>
              <strong class="tournament-name">{t["name"]}</strong>
              <span :if={!t["link"].up? && t["link"].error} class="note">
                {link_error(t["link"].error)}
              </span>
              <button
                id={"remove-#{t["id"]}"}
                type="button"
                class="danger"
                phx-click="remove"
                phx-value-id={t["id"]}
                data-confirm={gettext("Leave this tournament? Its rounds stop printing here.")}
              >
                {gettext("Remove")}
              </button>
            </div>
            <p class="note">
              <%= if held_round(t) do %>
                {gettext("Round %{n} is the latest published round.", n: held_round(t))}
              <% else %>
                {gettext("No round published yet.")}
              <% end %>
            </p>
            <p :if={t["changed"]} id={"changed-#{t["id"]}"} class="warn">
              {gettext("Round %{n} changed since it was printed.", n: held_round(t))}
              <button
                id={"reprint-round-#{t["id"]}"}
                type="button"
                phx-click="reprint_round"
                phx-value-id={t["id"]}
              >
                {gettext("Reprint")}
              </button>
            </p>
            <div class="switches">
              <label>
                <input
                  id={"switch-pairings-#{t["id"]}"}
                  type="checkbox"
                  checked={t["print_pairings"] != false}
                  phx-click="switch"
                  phx-value-id={t["id"]}
                  phx-value-which="print_pairings"
                  phx-value-on={to_string(t["print_pairings"] == false)}
                />
                {gettext("Print the pairings")}
              </label>
              <label>
                <input
                  id={"switch-placecards-#{t["id"]}"}
                  type="checkbox"
                  checked={t["print_placecards"] != false}
                  phx-click="switch"
                  phx-value-id={t["id"]}
                  phx-value-which="print_placecards"
                  phx-value-on={to_string(t["print_placecards"] == false)}
                />
                {gettext("Print the place cards")}
              </label>
              <form id={"copies-form-#{t["id"]}"} phx-change="copies">
                <input type="hidden" name="tournament" value={t["id"]} />
                <label>
                  {gettext("Copies of the pairings")}
                  <select id={"copies-#{t["id"]}"} name="copies">
                    <option :for={n <- 1..5} value={n} selected={(t["copies"] || 1) == n}>
                      {n}
                    </option>
                  </select>
                </label>
              </form>
            </div>
          </li>
        </ul>
      </section>

      <section id="join">
        <h2>{gettext("Join a tournament")}</h2>
        <.form for={@join_form} id="join-form" phx-submit="join">
          <input
            id="join-link"
            type="text"
            name={@join_form[:link].name}
            value={@join_form[:link].value}
            placeholder="https://server/p/polis/join/K7Q-4MD"
            autocomplete="off"
          />
          <button id="join-button" type="submit" disabled={@joining?}>
            {if @joining?, do: gettext("Joining..."), else: gettext("Join")}
          </button>
        </.form>
        <p :if={@message} id="join-message" class={elem(@message, 0)}>{elem(@message, 1)}</p>
        <p class="note">
          {gettext(
            "In OpenPairings: the tournament's Print station page, Add a print station. Paste the link it shows; that is all."
          )}
        </p>
      </section>

      <section id="printer">
        <h2>{gettext("Printer")}</h2>
        <p :if={@dry_run?} id="dry-run-note" class="note">
          {gettext(
            "Dry run: nothing goes to a printer. The sheets are written as PDF files in the data folder."
          )}
        </p>
        <form id="printer-form" phx-change="printer">
          <label>
            {gettext("Printer")}
            <select id="printer-select" name="printer" disabled={@printers == nil}>
              <option value="" selected={@printer == nil}>{gettext("(choose a printer)")}</option>
              <option :for={name <- @printers || []} value={name} selected={name == @printer}>
                {name}
              </option>
              <option
                :if={@printer && @printers && @printer not in @printers}
                value={@printer}
                selected
              >
                {gettext("%{name} (not found now)", name: @printer)}
              </option>
            </select>
          </label>
          <label>
            {gettext("Paper")}
            <select id="paper-select" name="paper">
              <option value="a4" selected={@paper == :a4}>A4</option>
              <option value="letter" selected={@paper == :letter}>Letter</option>
            </select>
          </label>
        </form>
        <p :if={@printers == nil} class="note">{gettext("Looking for printers...")}</p>
        <p :if={@printers_error} id="printers-error" class="error">
          {gettext("The printer list did not come: %{why}", why: @printers_error)}
        </p>
        <p :if={@printer == nil && @printers != nil} id="no-printer" class="warn">
          {gettext("No printer chosen. Rounds that arrive wait in the queue until one is.")}
        </p>
        <p class="buttons">
          <button id="refresh-printers" type="button" phx-click="refresh_printers">
            {gettext("Look for printers again")}
          </button>
          <button id="test-print" type="button" phx-click="test_print" disabled={@printer == nil}>
            {gettext("Test print")}
          </button>
        </p>
      </section>

      <section id="queue">
        <h2>{gettext("Queue")}</h2>
        <p :if={@jobs == []} id="no-jobs" class="note">{gettext("Nothing printed yet.")}</p>
        <ul :if={@jobs != []} id="job-list">
          <li :for={job <- @jobs} id={"job-#{job.id}"} class={"job #{job.status}"}>
            <span class="mono">{time(job.created_at)}</span>
            <span>
              <strong>{job_what(job)}</strong>
              <span :if={job.tournament_name} class="note">{job.tournament_name}</span>
              <span :if={job.copies > 1} class="note">x{job.copies}</span>
            </span>
            <span class={["status", job.status == :failed && "error"]}>{job_status(job)}</span>
            <span class="actions">
              <a id={"pdf-#{job.id}"} href={"/jobs/#{job.id}/pdf"} target="_blank" rel="noopener">
                {gettext("Open PDF")}
              </a>
              <button
                id={"reprint-#{job.id}"}
                type="button"
                phx-click="reprint_job"
                phx-value-id={job.id}
              >
                {gettext("Reprint")}
              </button>
            </span>
          </li>
        </ul>
      </section>

      <section id="program">
        <h2>{gettext("This program")}</h2>
        <p class="note">
          {gettext("Version")} <span class="mono">{Updates.current_version()}</span>
        </p>
        <p>
          <label>
            <input
              id="update-check"
              type="checkbox"
              checked={@update_mode == "ask"}
              phx-click="update_check"
              phx-value-on={to_string(@update_mode != "ask")}
            />
            {gettext("Look for a newer version now and then")}
          </label>
        </p>
        <p :if={Autostart.supported?()}>
          <label>
            <input
              id="autostart"
              type="checkbox"
              checked={@autostart?}
              phx-click="autostart"
              phx-value-on={to_string(!@autostart?)}
            />
            {gettext("Start Polis when Windows starts")}
          </label>
        </p>
        <p>
          <button id="check-now" type="button" phx-click="check_now" disabled={@checking?}>
            {if @checking?, do: gettext("Looking..."), else: gettext("Look now")}
          </button>
          <span :if={@update_message} id="update-message" class={elem(@update_message, 0)}>
            {elem(@update_message, 1)}
          </span>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
