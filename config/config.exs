# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pure_admin_icons,
  generators: [timestamp_type: :utc_datetime],
  ecto_repos: [PureAdminIcons.Repo],
  # Translations — DB-backed provider reads from public.get_group_translations
  translate: &PureAdminIcons.Translations.DbProvider.translate/2,
  default_locale: "en",
  supported_locales: ["en", "cs", "de", "fr", "es"]

# Configure the endpoint
config :pure_admin_icons, PureAdminIconsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PureAdminIconsWeb.ErrorHTML, json: PureAdminIconsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PureAdminIcons.PubSub,
  live_view: [signing_salt: "nWU4yO1j"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  pure_admin_icons: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind
config :tailwind,
  version: "4.1.12",
  pure_admin_icons: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Quantum scheduler
config :pure_admin_icons, PureAdminIcons.Scheduler,
  jobs: [
    # Sync icons daily at 3 AM
    {"0 3 * * *", {PureAdminIcons.Sync.Worker, :sync_all, []}}
    # Metrics are computed live from the audit event log (v1.21) — no cube to refresh.
  ]

# MCP client version contract advertised to `@keenmate/pure-admin-icons-mcp`.
# `latest` = newest published version; `min_supported` = hard floor below which
# the API may reject/misbehave. Both are surfaced as `X-MCP-*` response headers
# and via GET /api/mcp/version. Bump `min_supported` only when shipping a change
# that genuinely breaks older clients. `message`/`sunset` are optional extras.
config :pure_admin_icons, :mcp_version,
  latest: "1.3.0",
  min_supported: "1.0.0",
  message: nil,
  sunset: nil,
  changelog_url: "https://icons.pureadmin.io/docs/mcp"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Local overrides — not committed to git
File.regular?("config/.local.exs") && import_config(".local.exs")
File.regular?("config/#{config_env()}.local.exs") && import_config("#{config_env()}.local.exs")
