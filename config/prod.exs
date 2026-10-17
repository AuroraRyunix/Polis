import Config

# The station serves plain HTTP to its own browser, and to the hall's
# network only when POLIS_LISTEN=lan says so. There is no TLS to force and
# no host name to pin.
config :polis, PolisWeb.Endpoint, check_origin: false, server: true

config :logger, level: :info
