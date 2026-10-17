defmodule PolisWeb.Gettext do
  @moduledoc """
  The words of the page and of the printed sheets, in English and Dutch
  (`priv/gettext`). The page speaks the visitor's language; a printed sheet
  speaks the tournament's (`Polis.Layout`).
  """
  use Gettext.Backend, otp_app: :polis
end
