import Config

# The station serves plain HTTP to its own browser, and to the hall's
# network only when POLIS_LISTEN=lan says so. There is no TLS to force and
# no host name to pin. The socket's origin and every request's Host are
# checked against the list in `PolisWeb.HostGuard` (config/config.exs), so
# that a web page cannot reach the station by renaming 127.0.0.1.
config :polis, PolisWeb.Endpoint, server: true

config :logger, level: :info
