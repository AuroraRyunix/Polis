defmodule Polis.PdfTest do
  @moduledoc """
  The PDF writer: a header a reader accepts, a cross-reference table whose
  offsets point at the objects they name, a page count that is the
  document's, and names in WinAnsi - accents kept, the rest transliterated.
  """

  use ExUnit.Case, async: true

  alias Polis.{FakeServer, Layout, Pdf, WinAnsi}

  defp xref(pdf) do
    [_, at] = Regex.run(~r/startxref\n(\d+)\n%%EOF\n\z/, pdf)
    at = String.to_integer(at)
    "xref\n0 " <> rest = binary_part(pdf, at, byte_size(pdf) - at)
    [count | _] = String.split(rest, "\n", parts: 2)
    count = String.to_integer(count)
    entries = rest |> String.split("\n", parts: 2) |> List.last() |> binary_part(0, 20 * count)
    {at, count, for(<<entry::binary-size(20) <- entries>>, do: entry)}
  end

  test "starts as a PDF 1.4 and ends with %%EOF" do
    pdf = Pdf.render(Layout.pairings(FakeServer.payload(1)))
    assert String.starts_with?(pdf, "%PDF-1.4\n%")
    assert String.ends_with?(pdf, "%%EOF\n")
    assert Pdf.selftest() == "ok"
  end

  test "every xref entry is twenty bytes and points at the object it names" do
    pdf = Pdf.render(Layout.place_cards(FakeServer.payload(3)))
    {_at, count, [free | entries]} = xref(pdf)

    assert free == "0000000000 65535 f\r\n"
    assert length(entries) == count - 1

    for {entry, id} <- Enum.with_index(entries, 1) do
      assert <<offset::binary-size(10), " 00000 n\r\n">> = entry
      offset = String.to_integer(offset)
      assert binary_part(pdf, offset, byte_size("#{id} 0 obj")) == "#{id} 0 obj"
    end

    assert pdf =~ ~r/trailer\n<< \/Size #{count} \/Root 1 0 R/
  end

  test "the page count is the document's" do
    doc = Layout.place_cards(FakeServer.payload(3))
    pdf = Pdf.render(doc)
    assert pdf =~ "/Count #{length(doc.pages)} >>"
    assert length(Regex.scan(~r{/Type /Page /Parent}, pdf)) == length(doc.pages)
    assert pdf =~ "/BaseFont /Helvetica /Encoding /WinAnsiEncoding"
    assert pdf =~ "/BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding"
  end

  test "a stream's length is its length" do
    pdf = Pdf.render(Layout.pairings(FakeServer.payload(2)))

    for [_, length, stream] <-
          Regex.scan(~r/<< \/Length (\d+) >>\nstream\n(.*?)\nendstream/s, pdf) do
      assert byte_size(stream) == String.to_integer(length)
    end
  end

  test "upside-down text is turned with a matrix, not drawn mirrored" do
    pdf = Pdf.render(Layout.place_cards(FakeServer.payload(3)))
    assert pdf =~ ~r/-1 0 0 -1 [\d.]+ [\d.]+ cm/
  end

  describe "WinAnsi" do
    test "Latin letters with accents are one byte each, as WinAnsi has them" do
      assert WinAnsi.encode("Café") == <<"Caf", 0xE9>>
      assert WinAnsi.encode("Šarić") == <<0x8A, "ari", ?c>>
      assert WinAnsi.encode("Žemaitė") == <<0x8E, "emait", ?e>>
      assert WinAnsi.encode("Müller-Øst") == <<"M", 0xFC, "ller-", 0xD8, "st">>
    end

    test "what WinAnsi lacks is transliterated, and the rest is a question mark" do
      assert WinAnsi.encode("Łukasz Wąs") == "Lukasz Was"
      assert WinAnsi.encode("Đorđe") == "Dorde"
      assert WinAnsi.encode("Иван") == "????"
      # Decomposed input is taken as composed.
      assert WinAnsi.encode("Café") == <<"Caf", 0xE9>>
    end

    test "in the file, bytes outside printable ASCII are octal escapes, parentheses escaped" do
      assert Pdf.string("Café (B)") == "(Caf\\351 \\(B\\))"
      assert Pdf.string("a\\b") == "(a\\\\b)"
    end
  end
end
