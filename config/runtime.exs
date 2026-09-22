import Config

if System.get_env("PHX_SERVER") do
  config :pure_admin_icons, PureAdminIconsWeb.Endpoint, server: true
end

if config_env() == :prod do
  db_hostname =
    System.get_env("DB_HOSTNAME") ||
      raise "environment variable DB_HOSTNAME is missing."

  db_username =
    System.get_env("DB_USERNAME") ||
      raise "environment variable DB_USERNAME is missing."

  db_password =
    System.get_env("DB_PASSWORD") ||
      raise "environment variable DB_PASSWORD is missing."

  db_database =
    System.get_env("DB_DATABASE") ||
      raise "environment variable DB_DATABASE is missing."

  config :pure_admin_icons, PureAdminIcons.Repo,
    hostname: db_hostname,
    username: db_username,
    password: db_password,
    database: db_database,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing."

  host = System.get_env("PHX_HOST") || "icons.pureadmin.io"

  config :pure_admin_icons, PureAdminIconsWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "8888")
    ],
    secret_key_base: secret_key_base

  config :pure_admin_icons,
    icons_path: System.get_env("ICONS_PATH") || ".icons",
    use_icon_cache: System.get_env("USE_ICON_CACHE") == "true"

  if api_key = System.get_env("MAINTENANCE_API_KEY") do
    config :pure_admin_icons, maintenance_api_key: api_key
  end
end
