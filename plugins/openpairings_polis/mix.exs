defmodule OpenPairingsPolis.MixProject do
  use Mix.Project

  # Never compiled on its own. OpenPairings' hosted edition adds this
  # directory as a path dependency with `compile: false, app: false` and
  # compiles `lib/` together with the core (see openpairings_plugin.exs).
  # Everything the plugin uses - Phoenix, Ecto, Jason, EQRCode, WebSock -
  # OpenPairings already has, so there is nothing to declare. The file is
  # here because a path dependency without one upsets Mix.
  def project do
    [
      app: :openpairings_polis,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: []
    ]
  end
end
