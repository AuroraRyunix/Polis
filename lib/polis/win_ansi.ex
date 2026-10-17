defmodule Polis.WinAnsi do
  @moduledoc """
  Text as a PDF with a standard font can show it: WinAnsiEncoding, one byte
  a character, 224 characters - Latin-1 and a few typographic extras (the
  euro, curly quotes, dashes, Š Ž Œ and their small letters).

  That is the PDF's limit, and this module is where it is met:

    1. A character WinAnsi has is that byte.
    2. Otherwise its compatibility decomposition without the accents
       (NFKD, combining marks dropped): ő → o, ć → c, ș → s, ĳ → ij.
    3. Otherwise a small table of letters that do not decompose:
       ł → l, đ → d, ı → i, ħ → h, ŋ → n, ŧ → t, and their capitals.
    4. Otherwise `?`.

  So a Polish, Czech, Hungarian or Turkish name prints a letter that is
  nearly right, and a Cyrillic, Greek, Armenian, Georgian or Chinese name
  prints question marks. The Windows road (`Polis.Printer.Windows`) draws
  the page itself with a TrueType font and prints every name as it is;
  this limit is the PDF's, which macOS and Linux print and every system can
  open.
  """

  @extras %{
    0x20AC => 0x80,
    0x201A => 0x82,
    0x0192 => 0x83,
    0x201E => 0x84,
    0x2026 => 0x85,
    0x2020 => 0x86,
    0x2021 => 0x87,
    0x02C6 => 0x88,
    0x2030 => 0x89,
    0x0160 => 0x8A,
    0x2039 => 0x8B,
    0x0152 => 0x8C,
    0x017D => 0x8E,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x02DC => 0x98,
    0x2122 => 0x99,
    0x0161 => 0x9A,
    0x203A => 0x9B,
    0x0153 => 0x9C,
    0x017E => 0x9E,
    0x0178 => 0x9F
  }

  @table %{
    "ł" => "l",
    "Ł" => "L",
    "đ" => "d",
    "Đ" => "D",
    "ı" => "i",
    "İ" => "I",
    "ħ" => "h",
    "Ħ" => "H",
    "ŋ" => "n",
    "Ŋ" => "N",
    "ŧ" => "t",
    "Ŧ" => "T",
    "ĸ" => "k",
    "ŀ" => "l",
    "Ŀ" => "L",
    "ſ" => "s",
    "ə" => "e",
    "Ə" => "E",
    "‐" => "-",
    "‑" => "-",
    "−" => "-",
    "′" => "'",
    "″" => "\""
  }

  @doc "Whether `codepoint` is one of WinAnsi's characters."
  def encodable?(cp) when cp in 0x20..0x7E or cp in 0xA0..0xFF, do: true
  def encodable?(cp), do: Map.has_key?(@extras, cp)

  @doc "The WinAnsi bytes of `text`."
  def encode(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfc_binary()
    |> case do
      nfc when is_binary(nfc) -> nfc
      _invalid -> text
    end
    |> String.codepoints()
    |> Enum.map(&char/1)
    |> IO.iodata_to_binary()
  end

  @doc "`text` as it will print in the PDF, back in UTF-8 - for the page that says so."
  def printable(text) do
    text
    |> encode()
    |> :binary.bin_to_list()
    |> Enum.map(&decode_byte/1)
    |> List.to_string()
  end

  defp decode_byte(byte) do
    case Enum.find(@extras, fn {_cp, b} -> b == byte end) do
      {cp, _} -> cp
      nil -> byte
    end
  end

  defp char(<<cp::utf8>> = char) do
    cond do
      cp in 0x20..0x7E or cp in 0xA0..0xFF -> <<cp>>
      Map.has_key?(@extras, cp) -> <<Map.fetch!(@extras, cp)>>
      # Tabs, newlines and other controls are a space; a name has none.
      cp < 0x20 -> " "
      # A combining mark left over after NFC belongs to the letter before.
      combining?(char) -> ""
      true -> fallback(char)
    end
  end

  defp char(_invalid_byte), do: "?"

  defp fallback(char) do
    decomposed =
      char
      |> :unicode.characters_to_nfkd_binary()
      |> String.codepoints()
      |> Enum.reject(&combining?/1)

    cond do
      Map.has_key?(@table, char) ->
        Map.fetch!(@table, char)

      decomposed != [] and decomposed != [char] and Enum.all?(decomposed, &simple?/1) ->
        Enum.map(decomposed, &char/1)

      true ->
        "?"
    end
  end

  defp simple?(<<cp::utf8>>), do: encodable?(cp) or Map.has_key?(@table, <<cp::utf8>>)
  defp simple?(_other), do: false

  defp combining?(char), do: Regex.match?(~r/^\p{Mn}$/u, char)
end
