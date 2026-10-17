defmodule OpenPairingsPolis.Gettext do
  @moduledoc """
  The plugin's own message catalogue, in its own `priv/gettext`, so not a
  word of it leaks into the published application's translations.
  `mix gettext.extract --merge`, run from an OpenPairings checkout in the
  hosted edition with this plugin selected, writes both.

  The reader's language is set on the core's backend; `follow_core_locale/0`
  copies it here before the plugin opens its mouth.
  """
  use Gettext.Backend,
    otp_app: :pairings_engine,
    priv: Path.expand("../../priv/gettext", __DIR__)

  @doc "Puts this process in the language the core's backend is in."
  def follow_core_locale do
    Gettext.put_locale(__MODULE__, Gettext.get_locale(PairingsEngineWeb.Gettext))
  end
end
