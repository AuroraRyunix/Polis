defmodule Polis.LayoutTest do
  @moduledoc """
  The sheets, as ops: the pairings list breaks into pages with the header
  on each, a bye reads as one, a name too long for its column is shrunk and
  then cut, and the upper half of a place card is the lower half turned
  round.
  """

  use ExUnit.Case, async: true

  alias Polis.{FakeServer, Layout}
  alias Polis.Layout.Metrics

  defp texts(ops), do: for({:text, _, _, _, _, text, _} <- ops, do: text)

  defp payload_with(n) do
    boards =
      for i <- 1..n do
        %{
          "board" => Integer.to_string(i),
          "white" => %{"name" => "White #{i}", "rating" => 2000, "score" => "1"},
          "black" => %{"name" => "Black #{i}", "rating" => 1900, "score" => "1"},
          "bye" => nil
        }
      end

    %{FakeServer.payload(3) | "boards" => boards}
  end

  describe "the pairings list" do
    test "one page for a small round, with the column titles and the page number" do
      doc = Layout.pairings(FakeServer.payload(3))
      assert %{paper: :a4, width: 595, height: 842, pages: [page]} = doc

      t = texts(page)
      assert "Club Open" in t
      assert "Pairings - round 3 of 7" in t
      for title <- ~w(Board White Rtg Pts Black), do: assert(title in t)
      assert "Player One" in t and "Player Two" in t
      assert "Page 1 of 1" in t
    end

    test "many boards break into pages, and every page has the header and its number" do
      doc = Layout.pairings(payload_with(120))
      pages = doc.pages
      assert length(pages) > 2

      for {page, n} <- Enum.with_index(pages, 1) do
        t = texts(page)
        assert "Club Open" in t
        assert "White" in t and "Black" in t
        assert "Page #{n} of #{length(pages)}" in t
      end

      # Every board once, in order, across the pages.
      boards =
        for page <- pages,
            {:text, x, _, :regular, _, text, [align: :right]} <- page,
            x < 100,
            text =~ ~r/^\d+$/,
            do: text

      assert boards == Enum.map(1..120, &Integer.to_string/1)
    end

    test "nothing on a page falls below the bottom margin or off the paper" do
      for paper <- [:a4, :letter],
          doc = Layout.pairings(payload_with(90), paper),
          page <- doc.pages do
        for {:text, x, y, _, _, _, _} <- page do
          assert y >= 20 and y <= doc.height
          assert x >= 0 and x <= doc.width
        end
      end
    end

    test "a bye is a row with a bye where the opponent would be" do
      [page] = Layout.pairings(FakeServer.payload(3)).pages
      t = texts(page)
      assert "Player Five" in t
      assert "- bye -" in t
    end

    test "the sheet speaks the tournament's language, not the page's" do
      payload = %{FakeServer.payload(2) | "locale" => "nl"}
      [page] = Layout.pairings(payload).pages
      t = texts(page)
      assert "Paringen - ronde 2 van 7" in t
      assert "Wit" in t and "Zwart" in t
    end

    test "a round without boards says so" do
      [page] = Layout.pairings(%{FakeServer.payload(1) | "boards" => []}).pages
      assert "No boards in this round." in texts(page)
    end

    test "a long name is shrunk, then cut with an ellipsis, and never wider than its column" do
      long = String.duplicate("Longname-Longername ", 7) |> String.trim()

      payload =
        put_in(FakeServer.payload(1), ["boards"], [
          %{
            "board" => "1",
            "white" => %{"name" => long, "rating" => 2000},
            "black" => %{"name" => "Shorty", "rating" => 2000},
            "bye" => nil
          }
        ])

      [page] = Layout.pairings(payload).pages

      {:text, _x, _y, :bold, size, text, _} =
        Enum.find(page, &match?({:text, _, _, :bold, _, "Longname" <> _, _}, &1))

      assert size == 7
      assert String.ends_with?(text, "…")
      # The column of a name on A4 is about 182 points wide.
      assert Metrics.width(text, :bold, size) < 185

      {:text, _, _, :bold, short_size, "Shorty", _} =
        Enum.find(page, &match?({:text, _, _, :bold, _, "Shorty", _}, &1))

      assert short_size == 10
    end
  end

  describe "fitting" do
    test "fit_size shrinks in half points before it cuts" do
      text = "Abcdefghijklmnop"
      w = Metrics.width(text, :bold, 10)
      assert {^text, 10} = Layout.fit_size(text, :bold, 10, 7, w)
      assert {^text, size} = Layout.fit_size(text, :bold, 10, 7, w * 0.8)
      assert size < 10 and size >= 7
      assert {cut, size} = Layout.fit_size(text, :bold, 10, 7, w * 0.3)
      assert size == 7
      assert String.ends_with?(cut, "…")
    end
  end

  describe "the place cards" do
    test "one card per seated player; a bye gets none" do
      doc = Layout.place_cards(FakeServer.payload(3))
      # Two games, four players; the bye is left out.
      assert length(doc.pages) == 4
      # The name is the big bold line of each card.
      names =
        Enum.map(doc.pages, fn page ->
          Enum.find_value(page, fn
            {:text, _, _, :bold, size, text, _} when size >= 16 -> text
            _other -> nil
          end)
        end)

      assert names == ["Player One", "Player Two", "Player Three", "Player Four"]
    end

    test "the upper half is the lower half turned half a turn, with a fold line between" do
      doc = Layout.place_cards(FakeServer.payload(3))
      [page | _] = doc.pages
      {w, h} = {doc.width, doc.height}

      upright =
        for {:text, _, y, _, _, _, opts} = op <- page, y < h / 2, opts[:rotate] != 180, do: op

      turned = for {:text, _, _, _, _, _, opts} = op <- page, opts[:rotate] == 180, do: op

      assert length(upright) > 2
      # Every text of the half twice, but "fold here", which sits below the
      # fold once.
      assert length(turned) == length(upright) - 1

      for {:text, x, y, font, size, text, _} <- turned do
        # Turned about the sheet's centre: its twin sits at (w - x, h - y).
        assert Enum.any?(upright, fn {:text, ux, uy, f, s, t, _} ->
                 t == text and f == font and s == size and abs(ux - (w - x)) < 0.01 and
                   abs(uy - (h - y)) < 0.01
               end)

        assert y > h / 2
      end

      assert Enum.any?(page, &match?({:line, 0, _, ^w, _, _}, &1))
      assert "fold here" in texts(page)
      assert Enum.count(page, &match?({:text, _, _, _, _, "Board 1", _}, &1)) == 2
    end
  end

  describe "the test page" do
    test "names the printer and the paper" do
      doc = Layout.test_page(:letter, printer: "Hall printer")
      assert %{width: 612, height: 792, pages: [page]} = doc
      t = texts(page)
      assert "Printer: Hall printer" in t
      assert "Paper: Letter" in t
    end
  end

  describe "for the Windows road" do
    test "to_json keeps every op, in plain maps" do
      doc = Layout.place_cards(FakeServer.payload(3))
      json = Layout.to_json(doc)
      assert json["width"] == 595 and json["paper"] == "a4"
      assert length(json["pages"]) == 4
      [first | _] = json["pages"]
      assert length(first) == length(hd(doc.pages))
      assert Enum.any?(first, &(&1["op"] == "text" and &1["rotate"] == 180))
      assert Enum.any?(first, &(&1["op"] == "line" and &1["dash"] == [4, 3]))
      assert Jason.encode!(json)
    end
  end
end
