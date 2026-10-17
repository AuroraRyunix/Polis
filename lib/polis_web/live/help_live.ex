defmodule PolisWeb.HelpLive do
  @moduledoc """
  The station's short help, at `/help`, in English and Dutch: what Polis
  is, how to join a tournament, the printer, what prints by itself and what
  does not, and what to do when something is red. Nothing is read from the
  station: it is text, and it stays right when the station itself is the
  thing that is wrong.

  Written per language rather than through gettext: a manual is prose, and
  prose translated a sentence at a time reads like it.
  """

  use PolisWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(%{locale: "nl"} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} page={:help} subtitle="Help">
      <article id="manual">
        <section id="help-what">
          <h2>Wat Polis is</h2>
          <p>
            Polis is het printstation van de zaal: een klein programma op een computer met een printer. Het sluit aan bij een toernooi in OpenPairings en drukt van elke nieuwe ronde de paringslijst en de tafelkaartjes af, zodra de arbiter de ronde publiceert. Wie tegen wie speelt, beslis je in OpenPairings, niet hier.
          </p>
          <p>
            Polis belt zelf naar de server. In het netwerk van de zaal hoeft niets open te staan.
          </p>
        </section>

        <section id="help-join">
          <h2>Aansluiten bij een toernooi</h2>
          <ol>
            <li>
              Open in OpenPairings de pagina Printstation van het toernooi en druk op "Printstation toevoegen". Er verschijnt een link, goed voor één station en vijftien minuten.
            </li>
            <li>Plak de link in het veld "Aansluiten bij een toernooi" op deze pagina.</li>
            <li>
              Druk op "Aansluiten". Het toernooi staat dan in de lijst, met een groen bolletje zodra de verbinding open is.
            </li>
          </ol>
          <p>
            Een sleutel hoef je nooit te zien of te typen; Polis haalt hem zelf op. Is de link verlopen of al gebruikt, maak dan een nieuwe. Een link voor een ander zaalprogramma (bijvoorbeeld de omroeper) werkt hier niet, en dat zegt de pagina ook.
          </p>
        </section>

        <section id="help-printer">
          <h2>De printer</h2>
          <p>
            Kies de printer en het papier (A4 of Letter) onder "Printer". Polis kiest nooit zelf een printer: een paringslijst op de printer van de bar is erger dan geen. Zolang er geen printer gekozen is, wachten de rondes in de wachtrij, en ze gaan zodra je er een kiest.
          </p>
          <p>
            "Testafdruk" drukt één blad af met een kader langs de rand: is het kader heel, dan kloppen de marges.
          </p>
        </section>

        <section id="help-what-prints">
          <h2>Wat vanzelf afgedrukt wordt, en wat niet</h2>
          <ul class="prose">
            <li>
              Een nieuwe ronde: de paringslijst (zoveel exemplaren als je kiest, één tot vijf) en de tafelkaartjes, elk met zijn eigen schakelaar. Eén keer per ronde.
            </li>
            <li>
              Een ronde die de arbiter na het afdrukken nog wijzigt: niets vanzelf. Er komt "gewijzigd sinds het afgedrukt is" bij het toernooi te staan, met een knop "Opnieuw afdrukken". Een blad aan de muur dat vanzelf verandert, is erger dan een blad dat oud is.
            </li>
            <li>
              "Ronde opnieuw printen" in OpenPairings: wat het noemt, meteen.
            </li>
          </ul>
          <p>
            Een tafelkaartje is een tentje: vouw het blad op de stippellijn, en elke kant leest goed voor wie ervoor zit. Wie een bye heeft, krijgt geen kaartje.
          </p>
        </section>

        <section id="help-queue">
          <h2>De wachtrij</h2>
          <p>
            Elke afdruk staat in de wachtrij, de nieuwste bovenaan, met wat ermee gebeurd is: wacht op een printer, in de wachtrij, wordt afgedrukt, afgedrukt, of mislukt met de reden. "PDF openen" toont het blad zoals het afgedrukt wordt; "Opnieuw afdrukken" stuurt het nog een keer. De laatste vijftig blijven bewaard.
          </p>
        </section>

        <section id="help-trouble">
          <h2>Als iets rood is</h2>
          <ul class="prose">
            <li>
              Een rood bolletje bij een toernooi: de verbinding met de server is weg. Polis probeert het zelf opnieuw; de reden staat erbij. Wat er intussen gepubliceerd wordt, komt als de verbinding terug is.
            </li>
            <li>
              Een toernooi dat uit de lijst verdwijnt: het station is in OpenPairings verwijderd. Sluit opnieuw aan met een nieuwe link als dat een vergissing was.
            </li>
            <li>
              Een afdruk die mislukt: de reden is wat de printer of het systeem zei. Kijk of de printer aan staat en papier heeft, en druk op "Opnieuw afdrukken".
            </li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} page={:help} subtitle="Help">
      <article id="manual">
        <section id="help-what">
          <h2>What Polis is</h2>
          <p>
            Polis is the hall's print station: a small program on a computer with a printer. It joins a tournament in OpenPairings and prints the pairings list and the place cards of every new round as soon as the arbiter publishes it. Who plays whom is decided in OpenPairings, not here.
          </p>
          <p>
            Polis calls the server itself. Nothing needs to be opened in the hall's network.
          </p>
        </section>

        <section id="help-join">
          <h2>Joining a tournament</h2>
          <ol>
            <li>
              In OpenPairings, open the tournament's Print station page and press "Add a print station". A link appears, good for one station and fifteen minutes.
            </li>
            <li>Paste the link into the "Join a tournament" field on this page.</li>
            <li>
              Press "Join". The tournament is then in the list, with a green dot once the line is up.
            </li>
          </ol>
          <p>
            You never see or type a key; Polis fetches it itself. When the link is expired or used, make a new one. A link for another hall program (the announcer, say) does not work here, and the page says so.
          </p>
        </section>

        <section id="help-printer">
          <h2>The printer</h2>
          <p>
            Choose the printer and the paper (A4 or Letter) under "Printer". Polis never picks a printer by itself: a pairings list on the bar's printer is worse than none. Until a printer is chosen, rounds wait in the queue, and they go as soon as you choose one.
          </p>
          <p>
            "Test print" prints one sheet with a frame along the edge: if the frame is whole, the margins are right.
          </p>
        </section>

        <section id="help-what-prints">
          <h2>What prints by itself, and what does not</h2>
          <ul class="prose">
            <li>
              A new round: the pairings list (as many copies as you choose, one to five) and the place cards, each with its own switch. Once per round.
            </li>
            <li>
              A round the arbiter changes after it was printed: nothing by itself. The tournament shows "changed since it was printed", with a Reprint button. A sheet on the wall that changes by itself is worse than one that is old.
            </li>
            <li>
              "Print round N again" in OpenPairings: what it names, at once.
            </li>
          </ul>
          <p>
            A place card is a tent: fold the sheet on the dashed line, and each side reads the right way up for whoever sits in front of it. A player with a bye gets no card.
          </p>
        </section>

        <section id="help-queue">
          <h2>The queue</h2>
          <p>
            Every print is in the queue, newest first, with what happened to it: waiting for a printer, queued, printing, printed, or failed with the reason. "Open PDF" shows the sheet as it prints; "Reprint" sends it once more. The last fifty are kept.
          </p>
        </section>

        <section id="help-trouble">
          <h2>When something is red</h2>
          <ul class="prose">
            <li>
              A red dot by a tournament: the line to the server is down. Polis tries again by itself; the reason is beside it. Whatever is published meanwhile arrives when the line is back.
            </li>
            <li>
              A tournament that disappears from the list: the station was removed in OpenPairings. Join again with a new link if that was a mistake.
            </li>
            <li>
              A print that failed: the reason is what the printer or the system said. Check that the printer is on and has paper, and press Reprint.
            </li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end
end
