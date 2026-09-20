# icons.pureadmin.io

Search engine for open-source SVG icons. Aggregates multiple icon libraries into a single searchable catalog with platform-specific identifiers for iOS, Android, React, Vue, and Svelte.

**Live:** [icons.pureadmin.io](https://icons.pureadmin.io)

## Icon Sets

13 aggregated sets, ~59k icons total. Styles use a unified canonical vocabulary (`outline`, `filled`, `thin`, `light`, `regular`, `bold`, `rounded`, `sharp`, `duotone`, `line-duotone`, `broken`, `color`, `brands`). Native source-library names are preserved per-set in `const.icon_set.native_style_names`.

| Set | Icons | Styles | Sizes | License |
|-----|-------|--------|-------|---------|
| [Bootstrap Icons](https://icons.getbootstrap.com/) | ~2050 | outline, filled | scalable | MIT |
| [Carbon Icons](https://carbondesignsystem.com/elements/icons/library/) | ~2600 | outline, filled | scalable | Apache 2.0 |
| [FluentUI System Icons](https://github.com/microsoft/fluentui-system-icons) | ~5400 | outline, filled, color, light | 16, 20, 24, 28, 32, 48 | MIT |
| [Font Awesome Free](https://fontawesome.com/) | ~2850 | filled, outline, brands | scalable | CC BY 4.0 / MIT |
| [Heroicons](https://heroicons.com/) | ~650 | outline, filled | 16, 20, 24 | MIT |
| [Lucide](https://lucide.dev/) | ~1850 | outline | scalable | ISC |
| [Material Symbols](https://fonts.google.com/icons) | ~10750 | filled, outline, rounded, sharp, duotone | scalable | Apache 2.0 |
| [MingCute Icons](https://www.mingcute.com/) | ~3100 | outline, filled | scalable | Apache 2.0 |
| [Phosphor Icons](https://phosphoricons.com/) | ~9000 | thin, light, regular, bold, filled, duotone | scalable | MIT |
| [Remix Icon](https://remixicon.com/) | ~3050 | outline, filled | scalable | Apache 2.0 |
| [Simple Icons](https://simpleicons.org/) | ~3450 | filled | scalable | CC0 1.0 |
| [Solar](https://github.com/480-Design/Solar-Icon-Set) | ~8250 | outline, filled, duotone, line-duotone, broken, thin | scalable | CC BY 4.0 |
| [Tabler Icons](https://tabler.io/icons) | ~6200 | outline, filled | scalable | MIT |

See [icons.pureadmin.io/docs/icon-sets](https://icons.pureadmin.io/docs/icon-sets) for the live list with per-set notes, color methods, and source links.

## API

All endpoints return JSON. No authentication required (except maintenance).

```bash
# Search icons
curl 'https://icons.pureadmin.io/api/icons/search?q=calendar&limit=5'

# Filter by icon set and style
curl 'https://icons.pureadmin.io/api/icons/search?q=arrow&set=heroicons&style=outline'

# Get icon detail
curl 'https://icons.pureadmin.io/api/icons/5403'

# List all icon sets
curl 'https://icons.pureadmin.io/api/icon-sets'

# Plain text format (token-efficient for AI)
curl 'https://icons.pureadmin.io/api/icons/search?q=pen&format=text'
```

**Endpoints:**
- `GET /api/icons/search` — search with filters (q, set, size, style, limit, format)
- `GET /api/icons/:id` — icon detail with filenames, identifiers, categories, phrases
- `GET /api/icon-sets` — all sets with styles, sizes, color methods, icon count
- `GET /api/health` — health check
- `GET /icons/:set/:style/:filename` — SVG file serving
- `POST /api/maintenance/:task` — sync, clean, cube (requires X-API-Key)
- `POST /api/maintenance/sync/:icon_set` — sync a specific icon set

**Docs:** [icons.pureadmin.io/docs/api](https://icons.pureadmin.io/docs/api) · [llms.txt](https://icons.pureadmin.io/llms.txt)

## Download Designer

The icon detail modal includes a Download Designer for generating customized icon exports:

- **Colors** — apply any color preset (built-in or custom) to the icon and background
- **Padding** — adjustable gap around the icon (0–40%)
- **Rounded corners** — adjustable radius (0–50%, where 50% = circle)
- **PNG ZIP** — export at multiple sizes (32–1024px + custom) as a ZIP with manifest.json and readme.txt
- **SVG export** — single SVG with colors, padding, and rounded background baked in
- **Import settings** — restore all settings from a previous manifest.json

Ideal for generating app icons, favicons, or presentation-ready icon assets.

## MCP Server (for Claude Desktop / Claude Code)

```json
{
  "mcpServers": {
    "icons": {
      "command": "npx",
      "args": ["-y", "@keenmate/pure-admin-icons-mcp"]
    }
  }
}
```

Provides 5 tools: `get_usage_guide`, `search_icons`, `get_icon_detail`, `get_icon_svg`, `list_icon_sets`. Source: [`../pure-admin-icons-mcp`](../pure-admin-icons-mcp).

## Stack

- Phoenix 1.8 + LiveView 1.1
- Tailwind CSS v4 + DaisyUI
- PostgreSQL with full-text search + trigram matching
- Quantum scheduler (daily sync at 3 AM)
- Bandit HTTP server

## Architecture

- **Sync adapters** — `lib/pure_admin_icons/sync/adapters/` — one module per icon set implementing the `PureAdminIcons.Sync.Adapter` behaviour (download, parse, move, cleanup)
- **Formatter modules** — `lib/pure_admin_icons/icon_sets/` — one module per icon set implementing the `PureAdminIcons.IconSets.Formatter` behaviour (React/Vue/Svelte/CSS class identifiers and packages)
- **Database layer** — `lib/database/` — auto-generated by `db-gen` from PostgreSQL stored procedures (run `make db-gen` to regenerate)
- **Presets** — `priv/preview_presets.json` — single source of truth for built-in color presets, loaded at compile time and shared between server and JS via `PresetManager`
- **Vendor JS** — `priv/static/assets/vendor/` — floating-ui (popovers), JSZip (PNG ZIP export), loaded via `<script defer>` in root layout

Adding a new icon set requires:
1. New file in `lib/pure_admin_icons/sync/adapters/`
2. New file in `lib/pure_admin_icons/icon_sets/`
3. Both registered in their respective `@adapters` / `@formatters` maps
4. DB row in `const.icon_set` (see [docs/](docs/) for details)

See [`docs/`](docs/) for internal documentation on presets, Copy/Import CSS, and per-set platform prefs.

## Translations

UI strings are pulled from `public.translation` via `public.get_group_translations(lang, 'frontend', 'text', tenant)` and cached per-locale in `:persistent_term`. English defaults live in `lib/pure_admin_icons/translations.ex` as `@defaults` and are used as fallback when the DB has no row for a key/locale.

### Using `t/2` in templates

```elixir
import PureAdminIcons.Translations, only: [t: 1, t: 2]

t("common.buttons.copy")                              # => "Copy"
t("iconSearch.messages.resultsRange",
  %{from: 1, to: 30, total: 392})                     # => "Showing 1-30 of 392 icons"
```

### Key convention

`[domain].[specifier].[identifier]`

- **domain** — page / feature, or `common` for shared strings (`iconSearch`, `iconSets`, `iconDetail`, `docsIndex`, `apiDocs`, `mcpDocs`, `llmsDocs`, `stats`, `syncDiscrepancies`, `nav`, `common`)
- **specifier** — string kind (`labels`, `headers`, `tableHeaders`, `placeholders`, `buttons`, `tooltips`, `messages`, `empty`, `links`, `pagination`, `platforms`, `periods`, `filters`, `cards`)
- **identifier** — camelCase (`iconSet`, `browseIcons`, `copyCss`)

Interpolation uses `%{param}` placeholders — applied by `Translations.interpolate/2` after DB lookup.

### Locale resolution

Per request, `PureAdminIconsWeb.Plugs.Locale` picks the locale in this order:

1. `?lang=xx` query param (explicit opt-in)
2. `Accept-Language` header's first acceptable tag
3. `default_locale` from config (default `"en"`)

Only whitelisted tags in `config :pure_admin_icons, :supported_locales` are honored; everything else falls back to default.

LiveView processes inherit the resolved locale via the `live_session :default, on_mount: {Plugs.Locale, :default}` hook in the router, which reads the value stashed in the session by the plug.

### Adding a language

1. Add rows to `public.translation` with `(language_code, data_group='frontend', data_object_code=<full key>, context='text', value=<translated>)`. See `../pure-admin-icons-database/upsert_frontend_translations.sql` for the template / canonical source of all frontend translations.
2. Refresh the mat view: `SELECT internal.refresh_translation_cache();`
3. Append the language code to `config :pure_admin_icons, :supported_locales`.
4. Drop the in-app cache: `PureAdminIcons.Translations.DbProvider.refresh()`.

### Adding a new UI string

1. Call `t("domain.specifier.identifier")` in your template.
2. Add an English row to `@defaults` in `lib/pure_admin_icons/translations.ex` (fallback when DB has no translation).
3. Insert the same row into `public.translation` for `en` — and any other active language.
4. Refresh both the mat view and the in-app cache.

### Writing to the translation table

Use the SP writers (`public.create_translation`, `public.update_translation`, `public.delete_translation`, `public.copy_translations`) — they handle normalization, auditing, and automatic mat-view refresh. After any out-of-band change, call `PureAdminIcons.Translations.DbProvider.refresh()` to drop the in-app cache.

## Development

```bash
mix setup              # Install deps, build assets
iex -S mix phx.server  # Start dev server at localhost:4020
mix test               # Run tests
mix format             # Format code
make db-gen            # Regenerate DB context from stored procedures
```

### Assets

Sources live in `assets/js/` (entry: `assets/js/app.js`) and `assets/css/app.css`. esbuild bundles JS into `priv/static/assets/js/app.js`; Tailwind compiles CSS into `priv/static/assets/css/app.css`. Both build outputs are **gitignored** — the Dockerfile regenerates them via `mix assets.deploy`. Vendor files under `priv/static/assets/vendor/` (floating-ui, jszip) and `priv/static/assets/default.css` are checked in.

The dev bundle is large (~1.3MB for `app.js`) because esbuild emits an inline base64 source map (~939KB, ~71% of the file) and ships Phoenix + LiveView unminified (~382KB):

| Component | Approx. size (dev, unminified) |
|-----------|-------------------------------|
| Inline source map (base64) | ~939KB |
| `phoenix_live_view`        | ~225KB |
| `phoenix`                  | ~52KB  |
| App + theme + lang switcher + topbar + esbuild shim | ~105KB |

Production (`mix assets.deploy`) minifies, writes the source map to a separate `.js.map` file, and `mix phx.digest` gzips — end users download roughly 110KB minified, ~35KB gzipped.

## Deployment

```bash
docker build -t pure-admin-icons:latest .
docker run -p 8888:8888 \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e DB_USERNAME=... -e DB_PASSWORD=... \
  -e DB_HOSTNAME=... -e DB_DATABASE=pure_admin_icons \
  -e PHX_HOST=icons.pureadmin.io \
  pure-admin-icons:latest
```

### Reverse proxy (Traefik) requirements

This app sits behind Traefik in production. Two non-obvious requirements — without these, LiveView falls back to long-polling (slow back-nav, occasional page reloads):

**1. The websecure entrypoint must allow encoded characters in the request URL.**

Phoenix LiveView's WebSocket connect URL embeds asset URLs in the `_track_static` query parameter (e.g. `_track_static[0]=https%3A%2F%2F...`), which contains `%2F`. Traefik 3.6.4+ rejects requests with `%2F`, `%5C`, `%23`, `%3F`, `%3B`, `%00` in the URL by default (see [Traefik docs](https://doc.traefik.io/traefik/reference/install-configuration/entrypoints/#opt-http-encodedCharacters)). The WS handshake silently 400s → browser falls back to long-poll.

In `traefik.yml`:

```yaml
entryPoints:
  websecure:
    address: ":443"
    http:
      encodedCharacters:
        allowEncodedBackSlash: true
        allowEncodedNullCharacter: true
        allowEncodedQuestionMark: true
        allowEncodedSemicolon: true
        allowEncodedSlash: true
        allowEncodedHash: true
```

**2. The icons router only listens on the `websecure` entrypoint** (HTTPS-only at the proxy layer). Because of this, Phoenix `force_ssl` is intentionally **not** configured — Traefik already enforces HTTPS, and `force_ssl` would 301-loop WebSocket Upgrade requests when Traefik doesn't forward `X-Forwarded-Proto` for them. Phoenix uses `Plug.RewriteOn` instead (in `lib/pure_admin_icons_web/endpoint.ex`) to trust the proxy headers for URL generation without redirecting.

Minimal Traefik labels for the icons service:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.pureadmin-io-icons.rule=Host(`icons.pureadmin.io`)
  - traefik.http.routers.pureadmin-io-icons.entrypoints=websecure
  - traefik.http.routers.pureadmin-io-icons.tls=true
  - traefik.http.routers.pureadmin-io-icons.tls.certresolver=letsencrypt
  - traefik.http.routers.pureadmin-io-icons.service=pureadmin-io-icons
  - traefik.http.services.pureadmin-io-icons.loadbalancer.server.port=4000
```

(`PORT=4000` env var on the container makes Phoenix listen on `:4000` to match the loadbalancer port.)

## License

Application code: MIT. Icon SVGs retain their original licenses (see icon set table above).

Built by [KeenMate](https://keenmate.com).
