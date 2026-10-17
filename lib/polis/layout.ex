defmodule Polis.Layout do
  @moduledoc """
  A round payload (docs/protocol.md) laid out as pages: the pairings list
  and the place cards, the two documents OpenPairings prints from
  `PrintController.pairing_list/2` and `place_cards/2`. OpenPairings' are
  HTML and a browser prints them; Polis has no browser, so the same two
  documents are drawn here, once, as a list of drawing operations that both
  printing roads use: `Polis.Pdf` writes them into a PDF (macOS, Linux, and
  "Open PDF" everywhere), `priv/print/print.ps1` draws them on a Windows
  printer.

  ## The document

      %{paper: :a4, width: 595, height: 842, title: "...", pages: [[op]]}

  in PDF points (1/72 inch), origin at the bottom left, y upwards. The ops:

    * `{:text, x, y, font, size, string, opts}` - `font` is `:regular` or
      `:bold` (Helvetica on the PDF, Arial on Windows: the same widths),
      `y` the baseline. `opts`: `align` (`:left`, `:right`, `:center` - at
      `x`, in the direction the text reads), `rotate` (0 or 180), `gray`
      (0 black .. 1 white).
    * `{:line, x1, y1, x2, y2, opts}` - `width`, `dash` (`[on, off]`), `gray`.
    * `{:rect, x, y, w, h, opts}` - `width` of the border (0: none), `fill`
      (a gray, or nil).

  Every string is fitted before it gets here (`fit/4`): shrunk to a
  smallest size, then cut with an ellipsis. Nothing downstream measures.

  ## The two documents

  The pairings list: the tournament, the round and the date on top; the
  columns Board | White | Rtg | Pts | Black | Rtg | Pts; a bye is a row
  with "bye" where Black would be; the heading and the column titles again
  on every page; "Page n of m" below.

  The place cards: one sheet per player with a seat this round (a bye has
  no table to put a card on), folded across the middle into a tent. Each
  half shows the name, large, the title, the rating and federation, and the
  board. The upper half is drawn upside down, so that once folded each
  side of the tent reads the right way up to the player facing it.
  OpenPairings turns the lower half instead; turn the sheet round and it is
  the same card.

  Words on the page follow the payload's `locale` (the tournament owner's
  language), not the language of Polis's own page.
  """

  use Gettext, backend: PolisWeb.Gettext

  alias Polis.Layout.Metrics

  @papers %{a4: {595, 842}, letter: {612, 792}}
  @margin 36

  @doc "Width and height of a paper size in points."
  def paper(paper), do: Map.fetch!(@papers, paper(paper, :atom))

  @doc false
  def paper("letter", :atom), do: :letter
  def paper(:letter, :atom), do: :letter
  def paper(_a4, :atom), do: :a4

  @doc "The pairings list of a round payload."
  def pairings(payload, paper \\ :a4) do
    with_locale(payload, fn -> pairings_doc(payload, paper(paper, :atom)) end)
  end

  @doc "The place cards of a round payload."
  def place_cards(payload, paper \\ :a4) do
    with_locale(payload, fn -> place_cards_doc(payload, paper(paper, :atom)) end)
  end

  @doc "The page the Test print button prints: the printer's name, the time, a frame."
  def test_page(paper \\ :a4, opts \\ []) do
    paper = paper(paper, :atom)
    {w, h} = Map.fetch!(@papers, paper)
    printer = Keyword.get(opts, :printer) || "-"
    at = Keyword.get(opts, :at) || DateTime.utc_now(:second)
    width = w - 2 * @margin

    ops =
      [
        {:rect, @margin, @margin, width, h - 2 * @margin, [width: 1]},
        {:text, w / 2, h - 120, :bold, 28, "Polis", [align: :center]},
        {:text, w / 2, h - 150, :regular, 14,
         fit(gettext("Test print"), :regular, 14, width - 20), [align: :center]},
        {:text, w / 2, h - 190, :regular, 11,
         fit(gettext("Printer: %{name}", name: printer), :regular, 11, width - 20),
         [align: :center]},
        {:text, w / 2, h - 208, :regular, 11, Calendar.strftime(at, "%Y-%m-%d %H:%M UTC"),
         [align: :center]},
        {:text, w / 2, h - 226, :regular, 11,
         gettext("Paper: %{paper}", paper: paper_name(paper)), [align: :center]},
        {:text, w / 2, h - 270, :regular, 11,
         gettext("If this frame is whole, the margins are right."), [align: :center]},
        {:text, w / 2, h - 300, :bold, 14, "Müller · Ødegaard · Ljubojević · Łukasz",
         [align: :center]},
        {:line, @margin + 20, h / 2, w - @margin - 20, h / 2, [width: 0.5, dash: [4, 3]]},
        {:text, w / 2, h / 2 - 40, :bold, 22, "Polis", [align: :center, rotate: 180]}
      ]

    %{paper: paper, width: w, height: h, title: "Polis test print", pages: [ops]}
  end

  defp paper_name(:a4), do: "A4"
  defp paper_name(:letter), do: "Letter"

  defp with_locale(payload, fun) do
    locale = if payload["locale"] == "nl", do: "nl", else: "en"
    Gettext.with_locale(PolisWeb.Gettext, locale, fun)
  end

  # --- the pairings list ------------------------------------------------------

  @row 15
  @body_size 10
  @min_size 7

  defp pairings_doc(payload, paper) do
    {w, h} = Map.fetch!(@papers, paper)
    cols = columns(w)
    rows = payload |> boards() |> Enum.map(&row/1)

    # Above the table: the heading (about 80 points) and the column titles;
    # below it, the page number. What is left is rows.
    table_top = h - @margin - 74
    per_page = max(1, trunc((table_top - 18 - @margin - 24) / @row))

    chunks =
      case Enum.chunk_every(rows, per_page) do
        [] -> [[]]
        chunks -> chunks
      end

    total = length(chunks)

    pages =
      chunks
      |> Enum.with_index(1)
      |> Enum.map(fn {chunk, n} ->
        heading(payload, w, h) ++
          column_titles(payload, cols, table_top) ++
          body(chunk, cols, table_top - 18) ++
          empty_note(chunk, rows, w, table_top) ++
          footer(n, total, w)
      end)

    %{
      paper: paper,
      width: w,
      height: h,
      title: title(payload, gettext("Pairings")),
      pages: pages
    }
  end

  defp boards(payload), do: List.wrap(payload["boards"])

  defp heading(payload, w, h) do
    t = payload["tournament"] || %{}
    width = w - 2 * @margin
    name = to_string(t["name"] || "")

    round_line =
      case payload["rounds"] do
        n when is_integer(n) and n > 0 ->
          gettext("Pairings - round %{n} of %{total}", n: payload["round"], total: n)

        _unknown ->
          gettext("Pairings - round %{n}", n: payload["round"])
      end

    info =
      [t["city"], date(payload) || t["dates"]]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("  ·  ")

    [
      {:text, @margin, h - @margin - 16, :bold, 16, fit(name, :bold, 16, width), []},
      {:text, @margin, h - @margin - 36, :regular, 12, fit(round_line, :regular, 12, width), []},
      {:text, @margin, h - @margin - 52, :regular, 9, fit(info, :regular, 9, width), [gray: 0.3]},
      {:line, @margin, h - @margin - 62, w - @margin, h - @margin - 62, [width: 0.75]}
    ]
  end

  # The day the round was published, as the date on the sheet.
  defp date(payload) do
    with at when is_binary(at) <- payload["published_at"],
         {:ok, dt, _offset} <- DateTime.from_iso8601(at) do
      Date.to_iso8601(DateTime.to_date(dt))
    else
      _none -> nil
    end
  end

  # x positions of the seven columns for a page `w` wide. Numbers are right
  # aligned at their column's right edge; names start at their left.
  defp columns(w) do
    left = @margin
    right = w - @margin
    board = 30
    rating = 34
    points = 30
    gap = 10
    name = (right - left - board - gap - 2 * (rating + points) - gap) / 2

    white = left + board + gap
    black = white + name + rating + points + gap

    %{
      board: left + board,
      white: white,
      white_rating: white + name + rating,
      white_points: white + name + rating + points,
      black: black,
      black_rating: black + name + rating,
      black_points: black + name + rating + points,
      name_width: name - 6,
      left: left,
      right: right
    }
  end

  defp column_titles(payload, c, top) do
    rating = to_string(payload["rating_label"] || "Rtg")
    y = top - 10
    size = 8.5

    [
      {:text, c.board, y, :bold, size, gettext("Board"), [align: :right]},
      {:text, c.white, y, :bold, size, gettext("White"), []},
      {:text, c.white_rating, y, :bold, size, fit(rating, :bold, size, 32), [align: :right]},
      {:text, c.white_points, y, :bold, size, gettext("Pts"), [align: :right]},
      {:text, c.black, y, :bold, size, gettext("Black"), []},
      {:text, c.black_rating, y, :bold, size, fit(rating, :bold, size, 32), [align: :right]},
      {:text, c.black_points, y, :bold, size, gettext("Pts"), [align: :right]},
      {:line, c.left, top - 15, c.right, top - 15, [width: 0.5]}
    ]
  end

  defp row(board) do
    white = board["white"] || %{}
    black = board["black"]
    bye? = is_nil(black) or not is_nil(board["bye"])

    %{
      board: to_string(board["board"] || ""),
      white: player_name(white),
      white_rating: rating(white),
      white_points: to_string(white["score"] || ""),
      black: if(bye?, do: nil, else: player_name(black)),
      black_rating: if(bye?, do: "", else: rating(black)),
      black_points: if(bye?, do: "", else: to_string(black["score"] || ""))
    }
  end

  defp player_name(nil), do: ""
  defp player_name(player), do: to_string(player["name"] || "")

  defp rating(%{"rating" => r}) when is_integer(r) and r > 0, do: Integer.to_string(r)
  defp rating(_none), do: ""

  defp body(rows, c, top) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} ->
      base = top - @row * i - 11
      line_y = top - @row * (i + 1) + 1

      [
        {:text, c.board, base, :regular, @body_size, row.board, [align: :right]},
        name_op(c.white, base, row.white, c.name_width),
        {:text, c.white_rating, base, :regular, @body_size, row.white_rating, [align: :right]},
        {:text, c.white_points, base, :regular, @body_size, row.white_points, [align: :right]},
        if(row.black,
          do: name_op(c.black, base, row.black, c.name_width),
          else: {:text, c.black, base, :regular, @body_size, "- #{gettext("bye")} -", []}
        ),
        {:text, c.black_rating, base, :regular, @body_size, row.black_rating, [align: :right]},
        {:text, c.black_points, base, :regular, @body_size, row.black_points, [align: :right]},
        {:line, c.left, line_y, c.right, line_y, [width: 0.25, gray: 0.6]}
      ]
    end)
  end

  defp name_op(x, y, name, width) do
    {text, size} = fit_size(name, :bold, @body_size, @min_size, width)
    {:text, x, y, :bold, size, text, []}
  end

  defp empty_note([], [], w, top),
    do: [
      {:text, w / 2, top - 40, :regular, 11, gettext("No boards in this round."),
       [align: :center]}
    ]

  defp empty_note(_chunk, _rows, _w, _top), do: []

  defp footer(n, total, w) do
    [
      {:text, w / 2, @margin - 12, :regular, 8,
       gettext("Page %{n} of %{total}", n: n, total: total), [align: :center, gray: 0.3]}
    ]
  end

  defp title(payload, what) do
    name = get_in(payload, ["tournament", "name"]) || "Polis"
    "#{name} - #{what} #{payload["round"]}"
  end

  # --- the place cards ---------------------------------------------------------

  defp place_cards_doc(payload, paper) do
    {w, h} = Map.fetch!(@papers, paper)

    pages =
      for board <- boards(payload),
          player <- seated(board) do
        half = card_half(payload, board, player, w, h / 2)

        half ++
          Enum.map(half, &upside_down(&1, w, h)) ++
          [
            {:line, 0, h / 2, w, h / 2, [width: 0.5, dash: [4, 3], gray: 0.5]},
            {:text, w - 12, h / 2 - 9, :regular, 6.5, gettext("fold here"),
             [align: :right, gray: 0.5]}
          ]
      end

    %{
      paper: paper,
      width: w,
      height: h,
      title: title(payload, gettext("Place cards")),
      pages: pages
    }
  end

  # Who gets a card: both players of a game. A bye has no table.
  defp seated(%{"white" => white, "black" => black}) when is_map(white) and is_map(black),
    do: [white, black]

  defp seated(_bye), do: []

  # One half of a card, upright, in the lower half of the sheet (y from 0
  # to `half`): the reading bottom is the sheet's edge, the fold is above.
  defp card_half(payload, board, player, w, half) do
    width = w - 2 * @margin
    centre = w / 2
    name = to_string(player["name"] || "")
    {name_text, name_size} = fit_size(name, :bold, 40, 16, width)

    meta =
      [rating(player), to_string(player["federation"] || "")]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("  ·  ")

    title = to_string(player["title"] || "")
    board_text = gettext("Board %{n}", n: board["board"])
    board_size = 22
    box_w = Metrics.width(board_text, :bold, board_size) + 36
    box_h = board_size + 16
    tournament = get_in(payload, ["tournament", "name"]) || ""

    round_line =
      gettext("%{tournament} - round %{n}", tournament: tournament, n: payload["round"])

    [
      {:text, centre, half - 34, :regular, 9, fit(round_line, :regular, 9, width),
       [align: :center, gray: 0.35]},
      {:text, centre, half * 0.58, :bold, name_size, name_text, [align: :center]}
    ] ++
      if(title != "",
        do: [
          {:text, centre, half * 0.58 - 28, :regular, 16, fit(title, :regular, 16, width),
           [align: :center]}
        ],
        else: []
      ) ++
      if(meta != "",
        do: [
          {:text, centre, half * 0.58 - 50, :regular, 15, fit(meta, :regular, 15, width),
           [align: :center]}
        ],
        else: []
      ) ++
      [
        {:rect, centre - box_w / 2, 44, box_w, box_h, [width: 2]},
        {:text, centre, 44 + 8 + Metrics.descent(board_size), :bold, board_size, board_text,
         [align: :center]}
      ]
  end

  # The same op, turned half a turn about the centre of the upper half: what
  # sat at the sheet's bottom edge now sits at its top edge, upside down.
  defp upside_down({:text, x, y, font, size, text, opts}, w, h),
    do: {:text, w - x, h - y, font, size, text, Keyword.put(opts, :rotate, 180)}

  defp upside_down({:line, x1, y1, x2, y2, opts}, w, h),
    do: {:line, w - x1, h - y1, w - x2, h - y2, opts}

  defp upside_down({:rect, x, y, rw, rh, opts}, w, h),
    do: {:rect, w - x - rw, h - y - rh, rw, rh, opts}

  # --- fitting --------------------------------------------------------------------

  @doc """
  `text` cut to `width` points at `size`, with an ellipsis where it was cut.
  """
  def fit(text, font, size, width) do
    if Metrics.width(text, font, size) <= width do
      text
    else
      cut(String.graphemes(text), font, size, width - Metrics.width("…", font, size))
    end
  end

  @doc """
  `{text, size}`: the largest size from `size` down to `min` (half a point
  at a time) at which `text` fits in `width`; at `min`, cut with an
  ellipsis.
  """
  def fit_size(text, font, size, min, width) do
    if size <= min or Metrics.width(text, font, size) <= width do
      {fit(text, font, max(size, min), width), max(size, min)}
    else
      fit_size(text, font, size - 0.5, min, width)
    end
  end

  defp cut(graphemes, font, size, room) do
    {kept, _} =
      Enum.reduce_while(graphemes, {[], 0}, fn g, {acc, used} ->
        w = Metrics.width(g, font, size)
        if used + w <= room, do: {:cont, {[g | acc], used + w}}, else: {:halt, {acc, used}}
      end)

    (kept |> Enum.reverse() |> Enum.join() |> String.trim_trailing()) <> "…"
  end

  # --- for the Windows road ----------------------------------------------------------

  @doc """
  The document as plain JSON-ready maps, for `priv/print/print.ps1`:
  `%{"paper", "width", "height", "title", "pages" => [[%{"op" => ...}]]}`.
  """
  def to_json(doc) do
    %{
      "paper" => to_string(doc.paper),
      "width" => doc.width,
      "height" => doc.height,
      "title" => doc.title,
      "pages" => Enum.map(doc.pages, fn ops -> Enum.map(ops, &op_json/1) end)
    }
  end

  defp op_json({:text, x, y, font, size, text, opts}) do
    %{
      "op" => "text",
      "x" => x,
      "y" => y,
      "font" => to_string(font),
      "size" => size,
      "text" => text,
      "align" => to_string(Keyword.get(opts, :align, :left)),
      "rotate" => Keyword.get(opts, :rotate, 0),
      "gray" => Keyword.get(opts, :gray, 0)
    }
  end

  defp op_json({:line, x1, y1, x2, y2, opts}) do
    %{
      "op" => "line",
      "x1" => x1,
      "y1" => y1,
      "x2" => x2,
      "y2" => y2,
      "width" => Keyword.get(opts, :width, 0.5),
      "dash" => Keyword.get(opts, :dash),
      "gray" => Keyword.get(opts, :gray, 0)
    }
  end

  defp op_json({:rect, x, y, w, h, opts}) do
    %{
      "op" => "rect",
      "x" => x,
      "y" => y,
      "w" => w,
      "h" => h,
      "width" => Keyword.get(opts, :width, 0.5),
      "fill" => Keyword.get(opts, :fill)
    }
  end
end
