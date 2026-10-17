defmodule Polis.Layout.Metrics do
  @moduledoc """
  How wide a string is in Helvetica or Helvetica-Bold, in points.

  The widths are Adobe's (the Core 14 AFM files, see NOTICE), in thousandths
  of the font size, for the 224 characters of WinAnsiEncoding from 32 to
  255 - the only characters a PDF with a standard font can show
  (`Polis.WinAnsi`). Arial was drawn to the same widths, character for
  character, so a line measured here fits the same on the Windows road,
  which draws with Arial.

  A character outside WinAnsi is measured as what the PDF will print for it
  (`Polis.WinAnsi.encode/1`): a transliteration, or `?`. Windows prints the
  real character, which may be a little wider or narrower; the layout
  leaves a few points of air for that.
  """

  alias Polis.WinAnsi

  # Codes 32..255 of WinAnsiEncoding.
  @regular {278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556,
            556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667,
            667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722,
            667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500,
            556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278,
            556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 350, 556, 350, 222, 556, 333, 1000,
            556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350, 350, 222, 222, 333, 333, 350, 556,
            1000, 333, 1000, 500, 333, 944, 350, 500, 667, 278, 333, 556, 556, 556, 556, 260, 556,
            333, 737, 370, 556, 584, 333, 737, 333, 400, 584, 333, 333, 333, 556, 537, 278, 333,
            333, 365, 556, 834, 834, 834, 611, 667, 667, 667, 667, 667, 667, 1000, 722, 667, 667,
            667, 667, 278, 278, 278, 278, 722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722,
            722, 722, 667, 667, 611, 556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556,
            278, 278, 278, 278, 556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556,
            500, 556, 500}

  @bold {278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556,
         556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611, 975, 722, 722, 722,
         722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722,
         667, 944, 667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556, 333, 611,
         611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556, 333, 611, 556, 778, 556, 556,
         500, 389, 280, 389, 584, 350, 556, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667,
         333, 1000, 350, 611, 350, 350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333,
         944, 350, 500, 667, 278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333,
         737, 333, 400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,
         722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278, 722,
         722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611, 556, 556, 556,
         556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278, 611, 611, 611, 611, 611,
         611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556}

  # The font's own vertical measures, in thousandths: what a line needs
  # above and below its baseline.
  @ascent 718
  @descent 207

  def ascent(size), do: size * @ascent / 1000
  def descent(size), do: size * @descent / 1000

  @doc "The width of `text` in `font` (`:regular` or `:bold`) at `size` points."
  def width(text, font, size) when is_binary(text) do
    table = if font == :bold, do: @bold, else: @regular

    units =
      text
      |> WinAnsi.encode()
      |> :binary.bin_to_list()
      |> Enum.reduce(0, fn code, acc -> acc + glyph(table, code) end)

    units * size / 1000
  end

  defp glyph(table, code) when code >= 32 and code <= 255, do: elem(table, code - 32)
  defp glyph(_table, _control), do: 0
end
