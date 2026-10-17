import Config

# Where the station keeps what it must not lose: the state file (the
# tournaments it joined, their keys, the settings) and the jobs. Overridden
# per environment and by POLIS_DATA.
config :polis, data_dir: Path.expand("../data", __DIR__)

# Whether the station asks GitHub, on a timer, if a newer version is out.
# Off in tests, which ask when they mean to.
config :polis, updates_timer: true

# Whether the joined tournaments' links are started with the application.
# Off in tests, which start what they test.
config :polis, autostart_links: true

config :polis, PolisWeb.Gettext, default_locale: "en", locales: ~w(en nl)

config :polis, PolisWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: PolisWeb.ErrorHTML], layout: false],
  pubsub_server: Polis.PubSub,
  live_view: [signing_salt: "pQ2s7Lkd"]

# What never goes into a log, at any level: the join link carries a code,
# and the code is as good as a key for fifteen minutes.
config :phoenix, :filter_parameters, ["link", "key", "code", "token", "secret"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
