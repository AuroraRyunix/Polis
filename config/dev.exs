import Config

File.mkdir_p!(Path.expand("../data", __DIR__))

config :polis, PolisWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-Polis-xV3mJ0yq9kQwR7b2nL5tH8cD1fG4sA6zE0uI3oP9yT2wX5vB8nM1kJ4hG7fD0",
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/polis_web/.*\.(ex|heex)$"E
    ]
  ]

# Nothing prints for real while somebody develops: the dry run writes the
# PDF and the layout into <data>/dry-run instead. Set
# `config :polis, printer_backend: :auto` in a local file to try a printer.
config :polis, printer_backend: Polis.Printer.DryRun

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
