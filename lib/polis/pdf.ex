defmodule Polis.Pdf do
  @moduledoc """
  A `Polis.Layout` document as a PDF 1.4 file, written here in a few
  hundred lines rather than by a library: there are two fonts, three kinds
  of mark and no images, and a PDF of that is a short, well-documented
  text format.

    * Fonts: Helvetica and Helvetica-Bold, two of the fourteen standard
      fonts every PDF reader and every CUPS filter has, so nothing is
      embedded and a pairings list is a few kilobytes. Their encoding is
      WinAnsiEncoding, one byte a character (`Polis.WinAnsi`): a name in
      Latin letters prints as it is, accents and all; others are
      transliterated, and what has no Latin letter at all prints as `?`.
      That is this road's limit; the Windows road draws every name.
    * Content streams uncompressed: a pairings list is small, and a
      readable file is one a test can look into.
    * The cross-reference table with the byte offset of every object, as
      the specification wants it - ten digits, five digits, `n`, and an
      end-of-line of exactly two bytes.
  """

  alias Polis.Layout.Metrics
  alias Polis.WinAnsi

  @doc "The PDF of a document, as a binary."
  def render(%{pages: pages, width: w, height: h} = doc) do
    page_count = length(pages)
    # 1 catalog, 2 pages, 3 Helvetica, 4 Helvetica-Bold, 5 info; then a
    # page and its content stream per page.
    first = 6
    page_ids = for i <- 0..(page_count - 1)//1, do: first + 2 * i

    objects =
      [
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2,
         "<< /Type /Pages /Kids [#{Enum.map_join(page_ids, " ", &"#{&1} 0 R")}] /Count #{page_count} >>"},
        {3, font("Helvetica")},
        {4, font("Helvetica-Bold")},
        {5, info(doc)}
      ] ++
        Enum.flat_map(Enum.zip(page_ids, pages), fn {id, ops} ->
          stream = content(ops)

          [
            {id,
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{num(w)} #{num(h)}] " <>
               "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{id + 1} 0 R >>"},
            {id + 1, "<< /Length #{byte_size(stream)} >>\nstream\n" <> stream <> "\nendstream"}
          ]
        end)

    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    {body, offsets, _at} =
      Enum.reduce(objects, {[], [], byte_size(header)}, fn {id, dict}, {acc, offs, at} ->
        chunk = "#{id} 0 obj\n#{dict}\nendobj\n"
        {[acc, chunk], [{id, at} | offs], at + byte_size(chunk)}
      end)

    xref_at = byte_size(header) + IO.iodata_length(body)
    size = length(objects) + 1

    xref =
      [
        "xref\n0 #{size}\n",
        "0000000000 65535 f\r\n",
        offsets
        |> Enum.sort()
        |> Enum.map(fn {_id, off} ->
          String.pad_leading(Integer.to_string(off), 10, "0") <> " 00000 n\r\n"
        end)
      ]

    trailer =
      "trailer\n<< /Size #{size} /Root 1 0 R /Info 5 0 R >>\nstartxref\n#{xref_at}\n%%EOF\n"

    IO.iodata_to_binary([header, body, xref, trailer])
  end

  @doc """
  Lays out and writes the test page, and says `"ok"` when the result is a
  PDF. The release workflow runs it inside each built release
  (`bin/polis eval`): a release that cannot write a PDF should not ship.
  """
  def selftest do
    pdf = render(Polis.Layout.test_page(:a4, printer: "selftest"))

    if String.starts_with?(pdf, "%PDF-1.4") and String.ends_with?(pdf, "%%EOF\n"),
      do: "ok",
      else: "not a PDF"
  rescue
    error -> Exception.message(error)
  end

  defp font(name),
    do: "<< /Type /Font /Subtype /Type1 /BaseFont /#{name} /Encoding /WinAnsiEncoding >>"

  defp info(doc) do
    "<< /Title #{string(Map.get(doc, :title) || "Polis")} /Producer (Polis) >>"
  end

  # --- drawing ------------------------------------------------------------------

  defp content(ops), do: ops |> Enum.map(&op/1) |> IO.iodata_to_binary()

  defp op({:text, _x, _y, _font, _size, "", _opts}), do: []

  defp op({:text, x, y, font, size, text, opts}) do
    width = Metrics.width(text, font, size)

    shift =
      case Keyword.get(opts, :align, :left) do
        :right -> width
        :center -> width / 2
        _left -> 0
      end

    f = if font == :bold, do: "/F2", else: "/F1"

    matrix =
      if Keyword.get(opts, :rotate, 0) == 180,
        do: "-1 0 0 -1 #{num(x)} #{num(y)} cm\n",
        else: "1 0 0 1 #{num(x)} #{num(y)} cm\n"

    [
      "q\n",
      gray_fill(opts),
      matrix,
      "BT #{f} #{num(size)} Tf #{num(-shift)} 0 Td #{string(text)} Tj ET\n",
      "Q\n"
    ]
  end

  defp op({:line, x1, y1, x2, y2, opts}) do
    dash =
      case Keyword.get(opts, :dash) do
        [on, off] -> "[#{num(on)} #{num(off)}] 0 d\n"
        _solid -> ""
      end

    [
      "q\n",
      "#{num(Keyword.get(opts, :gray, 0))} G\n",
      "#{num(Keyword.get(opts, :width, 0.5))} w\n",
      dash,
      "#{num(x1)} #{num(y1)} m #{num(x2)} #{num(y2)} l S\n",
      "Q\n"
    ]
  end

  defp op({:rect, x, y, w, h, opts}) do
    fill = Keyword.get(opts, :fill)
    width = Keyword.get(opts, :width, 0.5)

    paint =
      cond do
        fill && width > 0 -> "B"
        fill -> "f"
        true -> "S"
      end

    [
      "q\n",
      if(fill, do: "#{num(fill)} g\n", else: ""),
      if(width > 0, do: "#{num(width)} w\n", else: ""),
      "#{num(x)} #{num(y)} #{num(w)} #{num(h)} re #{paint}\n",
      "Q\n"
    ]
  end

  defp gray_fill(opts) do
    case Keyword.get(opts, :gray, 0) do
      0 -> ""
      gray -> "#{num(gray)} g\n"
    end
  end

  # A PDF string: WinAnsi bytes, with the three characters that would end or
  # escape it escaped, and anything outside printable ASCII as an octal
  # escape - so the file stays text, whatever the name.
  @doc false
  def string(text) do
    escaped =
      text
      |> WinAnsi.encode()
      |> :binary.bin_to_list()
      |> Enum.map(fn
        ?( -> "\\("
        ?) -> "\\)"
        ?\\ -> "\\\\"
        c when c < 32 or c > 126 -> "\\" <> String.pad_leading(Integer.to_string(c, 8), 3, "0")
        c -> <<c>>
      end)

    IO.iodata_to_binary(["(", escaped, ")"])
  end

  # Numbers as a PDF wants them: no exponent, at most two decimals.
  defp num(n) when is_integer(n), do: Integer.to_string(n)

  defp num(n) when is_float(n) do
    rounded = Float.round(n, 2)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: :erlang.float_to_binary(rounded, [:compact, decimals: 2])
  end
end
