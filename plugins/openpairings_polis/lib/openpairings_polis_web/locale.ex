defmodule OpenPairingsPolisWeb.Locale do
  @moduledoc """
  Runs after the core's locale hook (the live_session's hooks run before a
  page's own) and puts the plugin's catalogue in the same language.
  """
  def on_mount(:default, _params, _session, socket) do
    OpenPairingsPolis.Gettext.follow_core_locale()
    {:cont, socket}
  end
end
