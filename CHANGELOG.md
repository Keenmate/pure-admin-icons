# Changelog

## 2026-09-22 — v0.6.2 — Session id is per-session, not permanent

**`session_uid` moved from `localStorage` to `sessionStorage`.** It was minted once and kept forever, making it a permanent browser identity rather than a session — so an `audit.session` spanned months of visits and (being first-seen-immutable) froze its IP/referrer/utm at the very first visit. It now lives in `sessionStorage`: one id per browsing session (survives reloads within the tab, resets when the tab/window closes). A fresh session each sitting also means `audit.session` captures the **current** IP, so the immutable-session design stays correct without a latest-wins update. The old permanent `localStorage` key is cleaned up on load, so existing visitors get a fresh, correctly-scoped session (and their real IP) on next load.

---

## 2026-09-22 — v0.6.1 — Real client IP behind Traefik (remote_ip)

**Fixed web session IPs recording the proxy address.** The audit session's client IP was resolved by a hand-rolled `x-forwarded-for` first-hop parse, which (a) ignored `x-real-ip` — the header Traefik often sends on the websocket upgrade — and (b) didn't skip the private docker/Traefik hop, so many web sessions logged `10.30.0.2` instead of the real client. Switched `PureAdminIconsWeb.ClientInfo` to the `remote_ip` package's pure `RemoteIp.from/2`, which inspects `Forwarded` / `X-Forwarded-For` / `X-Real-Ip` and auto-skips reserved/private hops, falling back to the socket peer only when no forwarded header carries a public address. Applies to both the LiveView `connect_info` path and the API `Plug.Conn` path. No Traefik/compose change needed — it was already forwarding the client IP (a real public address was being captured intermittently); this makes the app read it reliably.

---

## 2026-09-22 — v0.6.0 — Audit-log usage metrics (sessions + IP); live stats

**Metrics moved to a session-aware event log.** Replaced the ad-hoc `search_metric` / `icon_metric` / `icon_metric_cube` trio with a generic `audit.*` event log (DB `v1.21`/`v1.22`) modelled on gcp-documenthub's audit schema: one `audit.session` per visitor and an append-only `audit.event` stream carrying an `event_type_code` + a jsonb identity **snapshot**, so metrics survive an icon being deleted/re-synced with no denormalization dance. Copy, download, search, **and now icon-detail-open + basket add/remove** are all events. `/stats` (`get_stats_overview`, `get_popular_icons`, …) is computed **live** off the log — no cube, no daily-refresh staleness (the `MetricsCubeRefresher` GenServer + 4 AM job are gone).

**Fixed the "strange numbers".** Web "searches" were massively over-counted: search tracking lived in `handle_params`, which fires on every `push_patch` — filter toggles, pagination, initial load, and each debounced keystroke — so ~68% of logged "searches" were empty-query navigation. Searches are now recorded only for a **real, changed** query, and `get_stats_overview` counts them as `count(distinct (session, nrm_query))` per period so repeat/keystroke churn can't inflate. Backfill of history dropped the empty-query rows.

**Sessions + client IP.** A stable per-visitor `session_uid` is minted/persisted in the browser and passed via LiveView connect params; the API honours `x-session-id`, else synthesizes `ip:<addr>` so anonymous API traffic still groups. Sessions store `referrer`/`utm` and the **client IP** (via `:peer_data` + `:x_headers` on the socket / `x-forwarded-for` on the API — we're behind Traefik) for geo (countries, resolved offline) and abuse attribution. New `PureAdminIconsWeb.ClientInfo` centralizes IP/session resolution.

**Notes.** DB writers follow the KeenMate PG guidelines (`ensure_session`, `create_*_event`, query-driven `ix_event_*` indexes, created-only append-only tables). The old three tables are renamed `*_old` (kept for verification, dropped later). No MCP change yet — `x-session-id` support lands after web is validated.

---

## 2026-09-21 — v0.5.1 — Fix PNG export against resvg 0.45

**PNG rasterization argument fix.** `Rasterizer` invoked `resvg --width N --height N -- <in> <out>`, but resvg 0.45.x (Debian trixie) treats the `--` end-of-options separator as the input filename and fails with "failed to open the provided file" — so every `/api/icons/png-zip` request 500'd/422'd in production while SVG export worked. Dropped the `--` (both paths are always absolute and server-controlled, so there's no `-`-prefixed-path injection surface to guard) and switched to the short `-w`/`-h` flags. SVG export, metrics, and the DB changes were unaffected.

---

## 2026-09-21 — v0.5.0 — Bulk PNG/SVG ZIP export API; metrics tracking fixes + retention

**Bulk export endpoints.** Two new API endpoints bundle many icons into a single ZIP: `POST /api/icons/png-zip` (rasterized PNGs at requested sizes) and `POST /api/icons/svg-zip` (raw source SVGs). Both take a list of `(set, name, style)` icons — the caller's `name` is only a DB lookup key (resolved via the new `public.get_icon_details_by_keys` batch function), never a filesystem path; the SVG path is built from trusted DB columns and re-checked to sit inside the icons directory. PNG rasterization uses the **`resvg`** CLI (`PureAdminIcons.Rasterizer`, shelled out like the sync pipeline's 7z/unzip; added to the Docker runtime image). Guardrails: per-IP rate limit (429) and a render-units cap of `icons × sizes` (422) so a request can't ask for 50k icons at every size. Zip entries are namespaced `set/style/name[-size]` (no collisions across styles) with a `manifest.json` reporting resolved/skipped icons and any render failures. Handled by `IconExportController`; 15 unit tests cover the validation/guardrail paths.

**Metrics undercounting fixes.** Two gaps were silently deflating download stats. (1) A multi-size PNG-ZIP sent `size="32,64,128"`, which failed `Integer.parse` and collapsed to a single `nil`-size row; `track_download` now splits it into **one row per size**. (2) Basket bulk exports (SVG/PNG zip) pushed **no** metric events at all — they fetched from the passive `/icons/*` serve. The basket now emits a batched `track_download_batch` after export, recording one row per icon (SVG) / per icon×size (PNG), `surface: "basket"`. The new export endpoints track the same way (`source: "api"`, `format: "png-zip"`/`"svg-zip"`).

**Metrics survive icon deletion.** `icon_metric` and `icon_metric_cube` referenced `icon(icon_id) ON DELETE CASCADE`, so deleting or re-syncing an icon destroyed its historical stats. The durable identity (`icon_set_code`, `style_code`, `original_name`) is now denormalized into both tables, the FK softened to `ON DELETE SET NULL` (`icon_id` is a best-effort pointer), and the cube re-keyed on identity so stats survive both deletion *and* re-creation (relinking via `max(icon_id)`). `track_icon_action` snapshots identity at insert; `get_popular_icons` reads the name from the cube so deleted icons still appear. Function output shapes are unchanged, so there are no Elixir changes beyond the DB layer. (DB migrations `1.19` + `1.20`.)

**Download throttle.** The explicit `/api/download/:set/:style/:filename` endpoint had no rate limiting (only `/api/maintenance/*` did); added a per-IP guard (300/min, 429). The passive `/icons/*` img serve is intentionally left unthrottled — a single page loads dozens of icons.

---

## 2026-09-20 — v0.4.0 — Solar + MingCute icon sets; upstream-normalization disclosure

**Two new icon sets.** Added **Solar** (480 Design, CC BY 4.0 — ~8k icons across six weights: Linear→`outline`, Bold→`filled`, Bold Duotone→`duotone`, plus `line-duotone`, `broken`, and Outline→`thin`) and **MingCute** (Apache 2.0 — ~3k icons, `regular`→`outline` / `filled`→`filled`). Each ships a sync adapter (recursively walks the source's `style/category/*.svg` tree, slugifies names, dedups per style) and a formatter that emits Iconify identifiers (`@iconify/react|vue|svelte` components + the `@iconify/tailwind` class), since neither set has first-party component libraries. Both are registered in the `@adapters` / `@formatters` maps and given `const.icon_set` rows. The catalog is now **13 sets**; the README table and style vocabulary (`+ line-duotone, broken`) were updated.

**Upstream-normalization disclosure on `/docs/icon-sets`.** Solar and MingCute hardcode their colors on the SVG paths, so — like Material/Carbon/Simple Icons — the sync rewrites every non-`none` `fill`/`stroke` to `currentColor` (preserving `opacity`, so duotone survives) to make icons themeable. The served files are therefore not byte-identical to upstream. The icon-sets docs page now flags this two ways: a glanceable **"Normalized SVG"** badge on the affected set cards (`material`, `carbon`, `simpleicons`, `solar`, `mingcute`), and a per-set **notes** disclosure explaining the rewrite and pointing to the source repo for originals (added in all five locales — the earlier three sets only had it for Material). New UI strings `iconSets.labels.normalizedSvg` / `iconSets.tooltips.normalizedSvg` in EN defaults + cs/de/es/fr. The `/api/icon-sets` endpoint now also returns each set's `notes` and `description` (additive, non-breaking) so API consumers see the same disclosure. Refreshed the `/docs/api` page to document the new fields and the current set/style filter values.

**Localized the developer docs.** `/docs/api`, `/docs/mcp`, and `/docs/llms` were English-only (only their page titles were translated); their full prose is now localized across cs/de/es/fr — ~72 new `apiDocs.*` / `mcpDocs.*` / `llmsDocs.*` keys. Code samples, endpoint paths, query params, field names, and set/style codes are left verbatim.

**Icon basket translations (fix).** The basket UI rendered in English under other locales: its keys existed in the locale JSON sources but had never been propagated to the DB seed (the seed predated the basket feature), and runtime reads translations from the DB with an English fallback. Regenerating the frontend-translations seed picked up the basket strings (and the new badge strings) for cs/de/es/fr.

---

## 2026-09-19 — v0.3.0 — Icon basket + designer/detail polish

**Icon basket.** New basket for collecting icons across sets and pages. A shopping-bag button in the navbar (with a live count) opens a right-side drawer that renders the picked icons in the same grid/list cards as the search results. Each card gained an add/remove toggle — a rounded-square `+`/`✓` in the bottom-right corner, aligned to the card's radius. The basket offers three bulk actions — download all as an SVG `.zip`, download all as a PNG `.zip`, and copy every icon's platform identifiers to the clipboard — plus a collapsible Download Designer panel so theme colour, background, padding, corner radius, plain-vs-colorized SVG, sizes and the filename-naming convention all apply to the bulk exports. The basket is persisted in `localStorage` as lightweight icon maps and restored via connect params, so it survives reloads and works across pages without a DB round-trip.

**Shared designer/preset code.** Extracted the preview colour presets and the Download Designer markup that the search page, icon detail modal and basket had been duplicating: `PureAdminIconsWeb.PreviewPresets` (loaded from `priv/preview_presets.json` at compile time) and a `DownloadDesigner` function component with `:modal` and `:compact` variants sharing one `.designer-*` class contract with the JS hook. Also dropped a batch of dead code and dev console logging.

**Global platform preferences (fix).** Platform-identifier preferences (iOS/Android/React/Vue/Svelte/CSS class/HTML tag/filename) were being stored *per icon set*, so toggling React off while viewing a FluentUI icon didn't carry over when you opened a Lucide icon. Preferences are now a single global choice; which platforms a given set actually offers is still filtered per set (via `platform_supported?/2`). Legacy per-set data in `localStorage` is migrated by OR-ing every set's choices together.

**Collapsible Download Designer in the detail panel.** The Download Designer in the icon detail is now collapsed by default behind a show/hide header (matching the basket), reclaiming vertical space. Expanding it repaints the preview so the canvas is never blank on first open.

**Basket action buttons.** Restyled the drawer's SVG/PNG/IDs actions as proper bordered buttons (icon + short label, full description on hover) instead of bare stacked icons that read as ambiguous glyphs.

---

## 2026-09-19 — v0.2.0 — Master/detail icon view + navbar rework

**Master/detail layout for the icon detail on large screens.** On `xl` (≥1280px) viewports, selecting an icon no longer opens a centered dialog — the results container widens to ~80vw and splits 60/40, with the grid on the left and the icon detail as an inline, sticky panel on the right (own scroll, `max-h: calc(100vh - 3rem)`, no backdrop). Below `xl` the detail keeps its previous behaviour as a fixed overlay modal. This is a single `IconModalComponent` made responsive (`fixed inset-0` by default, `xl:static xl:sticky` inline panel), relocated into the content flow next to the grid; `#modal-container` stays as the stable morphdom anchor. Added a `DetailLayout` JS hook that logs the current panel/viewport/layout-mode to the console for verification across breakpoints.

**Navbar rework.** The horizontal nav now collapses to a burger below `lg` (1024px) instead of `sm` (640px), fixing the cramped/wrapping nav that overflowed the content block on tablet widths. The catalog summary ("Hledat 39781 ikon z 8 sad ikon") moved out of the hero and into the navbar as a parenthetical next to the logo — `icons.pureadmin.io (39781 ikon z 8 sad ikon)` — shown inline on `sm`+ and at the top of the burger menu on phones. `site_nav` gained optional `icon_count`/`set_count` attrs; pages that omit them (docs, stats) render no summary. Links tightened (`px-2.5`, `gap-0.5`) and nav padding reduced (`py-2`).

**Hero slimmed.** With the count line moved to the navbar, the hero drops that row, demotes the MCP prompt to small text, and reduces vertical padding (`py-6` → `py-4`) — reclaiming a large chunk of above-the-fold space.

---

## 2026-08-13 — Icon Sets docs: show "Last synced" per set

The `/docs/icon-sets` page now shows when each set was last synced. The data already existed (every sync creates a job run tagged with `icon_set_code`, surfaced by `public.get_last_sync`), but the page only loaded `const.get_icon_sets`, whose result carries no timestamp.

Database side added `public.get_icon_sets` — a superset of `const.get_icon_sets` returning two extra columns, `last_sync_started_at` and `last_synced_at`. Regenerated via db-gen (upgraded to v0.8.0-rc.4; added `public.get_icon_sets` to the `db-gen.json` allowlist), producing `DbContext.get_icon_sets/3` plus its model/processor. `Icons.list_icon_sets/1` now calls the `public` variant instead of `const`; since the model is a strict superset, all callers (home page, brand-color cache, API, docs) keep working and gain the timestamps. `const.get_icon_sets` is still generated but no longer used by app code.

`IconSetsDocsLive` renders a new "Last synced" row on each set card: friendly relative time (`just now`, `3 hours ago`, `2 days ago`) with an absolute `YYYY-MM-DD HH:MM UTC` fallback for anything older than a week and a full-timestamp hover title; `—` for never-synced sets. Added `iconSets.labels.lastSynced` and reusable `common.time.{justNow,minutesAgo,hoursAgo,daysAgo}` keys in EN defaults + all 4 locale files (cs/de/es/fr).

---

## 2026-07-31 — Download Designer: preserve aspect ratio in canvas render

Non-square icons (e.g. FontAwesome's narrow "3", viewBox taller than wide) came out horizontally stretched in the Download Designer's live preview and exported PNGs. Both canvas paths — `DesignerExport.renderToCanvas` (PNG export, also used by the floating popover's quick download) and the `DownloadDesigner` hook's `renderPreview` (live preview) — drew the SVG into a *square* destination rect via `ctx.drawImage(img, pad, pad, size - pad*2, size - pad*2)`, forcing every glyph to a 1:1 aspect. The top inline-`<svg>` preview and the SVG-download path were unaffected because they respect the viewBox.

Added two helpers to `DesignerExport` in `app.js`: `svgAspect(svgText)` reads the intrinsic w/h ratio from the viewBox (falling back to width/height, then 1:1), and `fitContain(aspect, x, y, w, h)` fits the icon into the padded box preserving aspect ratio, centered. Both render paths now compute the destination rect via `fitContain` instead of stretching, so non-square glyphs render correctly in the preview and in exported PNGs.

---

## 2026-05-31 — Stats popular-icons: disable "By copies" under API source

Polish on top of the action toggle: when `source == "api"` the "By copies" button is now visually disabled (opacity, no-click cursor, `disabled` attribute) and gets a tooltip explaining why (`stats.tooltips.copyUnavailableForApi` in all 5 locales). Additionally, `set_source` event handler now flips `action` back to `"download"` if the user switches to API while "By copies" is selected — otherwise they'd be staring at a permanently empty list with no signal as to why.

---

## 2026-05-31 — Stats page: drop API Copies column, add popular-icons action toggle

Two cleanups on `/stats` now that the API surface is settled:

**API table loses the Kopírování/Copies column.** Copy events only originate from explicit button clicks in the LiveView modal — there's no API endpoint to record a copy. So that column was structurally always 0 for API consumers, just adding visual noise. The Web table keeps it. The overview-cards loop in `AdminStatsLive.render/1` now reads `source == "web"` per iteration and conditionally renders the column header + body cell.

**Popular icons section gets a copy/download toggle, defaulting to download.** Previously `load_popular/1` hardcoded `action: "copy"`, which meant the section was effectively blind to download activity once the new `/api/download` endpoint started generating data. Added a `:action` assign (default `"download"`), a third `view-toggle` row next to the existing period + source toggles, and a `set_action` event handler with `~w(copy download)` guard. Section header now reads just "Oblíbené ikony" / "Popular Icons" — the "(by copies)" suffix is gone from `stats.headers.popularIcons` in all 5 locales (EN + cs/de/es/fr), replaced by the new `stats.filters.byCopy` / `stats.filters.byDownload` toggle labels.

---

## 2026-05-31 — Tracked download endpoint for API consumers

Added `GET /api/download/:icon_set/:style/:filename` — an explicit, tracked alternative to the passive `/icons/:icon_set/:style/:filename` file serve. The existing `/icons/...` route stays untracked because browsers fetch it just to render `<img>` tags and a passive image render isn't a download. Hitting `/api/download/...` is treated as an intentional retrieval (the MCP server, scripts, anyone wanting their fetch counted) and records an `icon_metric` row with `action=download`, `source=api`, `surface=direct`, `format=svg`.

The controller resolves `(set, style, filename) → (icon_id, size)` via `DbContext.get_icon_by_filename/3` (new `public.get_icon_by_filename` SP in `../pure-admin-icons-database/`, regenerated via db-gen — added to the `db-gen.json` allowlist), calls `Icons.track_action/4`, then delegates the actual SVG response to `IconFileController.show/2` so ETag/GitHub-fallback/404 logic stays in one place. If resolution or tracking fails, the user still gets their SVG — the failure is logged but never blocks the download.

MCP server change (in `../pure-admin-icons-mcp`) is the follow-up: swap the `get_icon_svg` fetch URL from `/icons/...` to `/api/download/...`. Search results still surface `/icons/...` URLs — only the explicit-download path moves.

---

## 2026-05-31 — Web search metrics + visible flush errors + positional-arg fix

**Web searches now recorded.** `IconSearchLive.handle_params/3` was running `Icons.search/2` but never calling `SearchMetricsCollector.record/6`, so the "Hledání" column for `source=web` on `/stats` was permanently 0 even though `source=api` searches were flowing in fine. Added a `SearchMetricsCollector.record(query, size, style, count, "web", icon_set)` call right after the search runs, guarded by `connected?` so dead renders don't double-count. Filter changes and pagination each produce one record — same granularity as API requests.

**Silent flush failures surfaced.** `SearchMetricsCollector.flush/1` previously called `DbContext.track_search` inside a bare `Enum.each` with no return-value check and no rescue. If the SP signature drifted or the connection blipped, every entry in the 30s batch was dropped silently and the only visible symptom was "stats not updating." Rewrote as `Enum.reduce` that traps both `{:error, reason}` returns and exceptions per-entry, then emits a `Logger.warning` with the dropped count, the offending entry, and the reason if anything failed (plus a `Logger.info` confirming how many succeeded). One bad row no longer poisons the whole batch.

**Root cause: `:eg_value_not_provided` collapses positional args.** With visible warnings on, the first flush showed `DBConnection.EncodeError: expected integer, got "fontawesome"` — the collector was passing `entry.icon_set_code` into `_size int`. The generated `DbContext.track_search` (and `track_icon_action`) build the SP call using *positional* `$N` placeholders and filter out `:eg_value_not_provided` values, which only works when omitted args are trailing. The collector's `entry.size || :eg_value_not_provided` pattern dropped `_size` from the placeholder list while keeping `_icon_set_code`, shifting `"fontawesome"` into position 4. Fixed by passing raw `nil`s through — `nil` survives the filter, arrives as SQL NULL, and the SP's `default null` clause kicks in while positions stay aligned. (The same bug exists in `track_icon_action` but is currently latent because `Icons.track_action/4` always passes `nil`, never `:eg_value_not_provided`.)

---

## 2026-05-02 — Theme & docs styling sync with pureadmin.io

Brought the icons site visually in line with pureadmin.io (which had its day-theme palette and docs chrome reworked the same day). The two share the same `park-morning/day/evening/night` daisyUI themes, so any palette or panel-chrome change has to land on both or they drift.

**Day theme brightness restored.** `--color-base-100/200/300` lifted from `97/93/85% → 99/96/88%` in `assets/css/app.css`. The April readability commit had darkened them for `/70` text contrast, but at near-zero chroma + cool hue 260 the panels read as flat cool-gray rather than the intended "clean cool white." Morning/evening/night untouched.

**Code panel chrome rebuilt.** The `<.code_block>` defp in `api_docs_live.ex` and the inline `<pre>` blocks in `mcp_docs_live.ex` (×2) and `llms_docs_live.ex` (×1) all switched from `!bg-transparent border-base-300/30` to `bg-base-300/70 border-base-300 shadow-sm`. Inline `<code>` tags in the mcp/llms docs got a `class="hljs"` marker so the new CSS selector picks them up. On light themes a `pre:has(> code.hljs)` rule paints the panel pure white. The icons site doesn't currently load highlight.js CDN, but the `.hljs` background/padding reset is added anyway to keep parity with pureadmin.io and pre-empt future divergence if hljs is added.

**Docs cards visible.** The `/docs` index card in `docs_index_live.ex` moved from `bg-base-100/50 border-base-300/50` to solid `bg-base-100 border-base-300 shadow-sm` with `hover:-translate-y-0.5 hover:shadow-md`. With the lifted day palette the half-opaque cards were vanishing into the `bg-base-200` panel.

**Docs text contrast bumped.** Across `api_docs_live.ex`, `llms_docs_live.ex`, `mcp_docs_live.ex`, `icon_sets_docs_live.ex`, and `docs_index_live.ex`: `text-primary/80` → `text-primary` (label-style code refs at full color), `text-base-content/70` → `/85` (descriptions and prose), `text-base-content/60` → `/80` (section labels and page subtitles). Main UI files (`icon_search_live.ex`, `home_live.ex`, `admin_stats_live.ex`, modal/sync screens) intentionally left alone — they have their own design tuned against the live grid.

---

## 2026-04-30 — LiveView WebSocket transport restored, infra docs

### Symptom
Back-navigation to `/` was taking 2.5–30 s with occasional full-page reloads. Server logs showed every LV connection landing as `Transport: :longpoll` instead of `:websocket`. The browser was attempting WS, failing silently, and falling back to long-polling after `longPollFallbackMs: 2500`.

### Three layered causes, fixed together

**Phoenix `force_ssl` 301-looping the WS Upgrade handshake.** Traefik (in this stack) does not forward `X-Forwarded-Proto: https` for Upgrade-style requests. Phoenix's `Plug.SSL` therefore saw `scheme=:http`, redirected to `https://…/live/websocket`, the browser re-issued, looped. The icons router only listens on Traefik's `websecure` entrypoint anyway, so HTTPS is already enforced at the edge — `force_ssl` was redundant and breaking. Replaced with `Plug.RewriteOn [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]` in `endpoint.ex` so Phoenix still trusts proxy headers for URL generation but doesn't redirect.

**Traefik `encodedCharacters` rejecting LV's WS connect URL.** Traefik 3.6.4+ refuses URLs containing `%2F`, `%5C`, `%23`, `%3F`, `%3B`, `%00` by default. LiveView's WS connect URL embeds asset URLs in the `_track_static` query parameter (`_track_static[0]=https%3A%2F%2F…`), which contains `%2F`. Traefik silently 400'd these; browser fell back to long-poll. Fixed in the Traefik static config (`traefik.yml`) by allowing all six encoded characters on the `websecure` entrypoint. Both the required Traefik settings and the rationale for not running `force_ssl` are documented in the README's new "Reverse proxy (Traefik) requirements" section.

**Bumped Traefik 3.6.13 → 3.6.15** as a precaution while diagnosing; not the silver bullet but worth being on latest patch.

### Diagnostic scaffolding (added during, partially removed)

- Added per-step timing telemetry for `IconSearchLive` mount and `handle_params` (DB calls individually timed). Logs as `[icon_search.mount] connected=true total=…ms (get_last_sync=…ms list_icon_sets=…ms count=…ms)` and emits `:telemetry` events registered in `PureAdminIconsWeb.Telemetry` for future Grafana wiring. Confirmed server-side mount is fast (~30 ms) — ruled out DB as the back-nav slowness, pointing at transport.
- Temporarily added a `/api/debug/headers` endpoint that dumps `conn` info + raw request headers as text. Used to verify Traefik was forwarding `X-Forwarded-Proto: https` on normal requests but not on Upgrade requests. Removed once the diagnosis was nailed; kept the timing telemetry.

### Tuning
- `longPollFallbackMs: 2500 → 1500` in `assets/js/app.js`. WS now connects reliably so the LP safety-net can fire faster on the rare networks where WS is genuinely blocked. Not removed entirely — keeps things working on restrictive corporate networks.

### Stop tracking built JS/CSS in git
Added `priv/static/assets/{js,css}/app.{js,css}{,.map}` to `.gitignore` and `git rm --cached`'d the existing tracked copies. The Dockerfile already runs `mix assets.deploy` to regenerate them, so they don't need to live in git. Vendor files in `priv/static/assets/vendor/` (floating-ui, jszip) and `default.css` stay tracked. README's new "Assets" subsection explains the dev-bundle size breakdown (the bundle is ~1.3 MB in dev mostly because of the inline source map; prod is ~110 KB minified, ~35 KB gzipped).

## 2026-04-15 — Upstream synonym extraction, stage.icon_phrase semantics

### Synonyms / tags pulled from upstream metadata
Six of the eight adapters now harvest the upstream keyword/tag lists and feed them to `stage.icon_phrase` as `relation_type='synonym'` rows. FluentUI was already doing this; Heroicons has no meaningful upstream source. Per set:

- **Lucide** — reads `icons/<name>.json` (tags + categories). Files were already extracted by the current 7zip filter; just parsed.
- **Phosphor** — widened the 7zip extract to include `core-main/src/icons/*.ts`, then regex-parses the `tags: [...]` array from each TS module.
- **Material** — fetches `https://fonts.google.com/metadata/icons` at parse time. Strips the `)]}'` XSSI prefix, decodes JSON, uses `tags` + `categories`. Req delivers this as a text/plain string, so decoding is explicit.
- **Tabler** — widened the 7zip extract to include `tabler-icons-main/tags.json`; handles both flat (`name → [tags]`) and nested (`name → {tags: […]}`) shapes.
- **FontAwesome** — fetches `metadata/icons.json` from the main FA repo (the npm free package ships SVGs but not metadata). Combines `search.terms` + `aliases.names`. Delivered as text/plain, decoded explicitly.
- **Remix** — defensive read of `tags.json` anywhere under the extracted root; graceful if missing.

All adapters now return `synonyms: %{display_name => [terms]}` from `parse/1`. Graceful degradation on HTTP failures / missing files — log a warning, continue sync, skip synonym insert.

### Correct `relation_type` / `is_primary` on stage rows
`Sync.Worker.copy_phrases_to_stage/2` previously omitted `relation_type` and `is_primary` from the COPY column list, so the DB defaults kicked in (`relation_type='name'`, `is_primary=false`). That mislabeled upstream tags as the icon's official name. Fixed by adding both columns explicitly and emitting `relation_type='synonym'`, `is_primary=false` for every metadata-sourced row.

One-shot backfill for existing data:
```sql
UPDATE public.icon_phrase
SET relation_type = 'synonym'
WHERE source_code = 'metadata' AND relation_type = 'name' AND is_primary = false;
```
Or just re-sync each set — `stage._process_icon_phrases` deletes stale non-primary metadata-source links before re-inserting.

### COPY null-marker fix
Both `stage.icon` and `stage.icon_phrase` COPY statements specified `NULL 'null'` as the null marker, meaning any icon name / synonym that was literally the four-character string `"null"` got interpreted as SQL NULL by Postgres — which violated NOT NULL constraints on `phrase`. Caught in prod when Lucide's sync crashed importing a tag spelled `"null"`. Switched to PostgreSQL's default null marker (`\N`). `escape_copy_field(nil)` already emitted the correct sequence; no other changes needed.

### Makefile cache-management targets
- `make clear-cache` — nukes `.cache/icons/*` so the next sync re-downloads + re-extracts with current filters
- `make sync-fresh` — one-shot: clear + full sync. Use after any change to an adapter's extract filter (e.g. today's Phosphor `.ts` and Tabler `tags.json` additions)

## 2026-04-15 — Cache-bust asset URLs, wire up `get_stats_overview`

### Fingerprinted static asset URLs
- Added `cache_static_manifest: "priv/static/cache_manifest.json"` to the prod endpoint config. `mix phx.digest` was already running during `assets.deploy`, producing `cache_manifest.json` and `app-<hash>.css/.js` copies — but the endpoint had no reference to the manifest, so `~p"/assets/…"` resolved to logical URLs (e.g. `/assets/js/app.js`) with no content hash. Combined with `Plug.Static`'s `cache-control: public, max-age=31536000, immutable`, deployed JS/CSS changes wouldn't reach browsers for up to a year without a hand-refresh.
- With the manifest wired up, every build produces new hashed URLs → browsers automatically fetch the new bundle on next page load. No more "please hard-refresh" emails after a deploy.

### `get_stats_overview` wrapper
- Added `get_stats_overview` to `db-gen.json` under the `public` schema. The SP existed on the DB since v1.7 but wasn't registered for generation, so `DbContext.get_stats_overview/0` was undefined and the `/stats` overview cards (web/api × period matrix) crashed at runtime.

### `track_copy` crash on scalable icons
- `IconSearchLive.handle_event("track_copy", …)` guarded `params["size"]` with `if size, do: ...` — truthy for empty string, so `String.to_integer("")` raised `ArgumentError` whenever a copy action came from a scalable icon (iOS / Material where `size` is empty). Guard tightened to require a non-empty binary before parsing.

### `track_action` positional-arg misalignment
- `Icons.track_action/4` defaulted omitted `size` / `platform` to `:eg_value_not_provided`, which the generated `DbContext.track_icon_action/5` filters out and packs remaining args positionally. When `size` was omitted but `platform` was supplied (scalable-icon copy path), the platform string landed in the size slot, causing Postgrex to reject `"ios"` as a non-integer. Switched to `nil` for missing middle args so positions stay aligned and the SP sees a NULL for size.

### Metrics coverage for all download paths
- **Quick PNG-ZIP download** (hover popover on grid/list) now fires `track_download` with `surface: "popover"`, `format: "png-zip"`. Previously it downloaded silently without hitting metrics. Added `data-icon-id` to the `.quick-designer-download` button template so the JS handler knows what icon to track.
- **Filename copy** (per-size Copy button in the "Filename (local copy)" section of the icon-detail modal) now fires `track_copy` with `format: "filename"` and the row's size. Previously the clipboard write succeeded but no metric event was emitted.
- **`track_download` handler** parses `size` defensively — accepts single-pixel ("24"), "0" (scalable), "" (no size), rejects comma-joined lists silently (PNG-ZIP batches). The old `String.to_integer/1` would have crashed for any of these.

### v1.11 schema integration
- `get_stats_overview` return shape changed from 5-column wide form (source/period + copies/downloads/searches) to 6-column long form (source/period/action/surface/format/count). `Icons.stats_overview/0` pivots the long form to the wide-legacy shape internally so `AdminStatsLive` keeps rendering without changes. Per-surface/format drill-down in the UI is a future enhancement.
- `track_icon_action` gained a 6th positional `_format_code` arg; the 5th arg was renamed `_platform_code` → `_surface_code`. `Icons.track_action/4` now takes `:surface`/`:format` opts (legacy `:platform` opt still accepted and auto-split on `:`). LiveView `track_download` handler splits the `naming` field (`"designer:png-zip"` / `"popover:png-zip"` → surface + format; bare `"pascal"`/`"kebab"`/… → `surface: "inline"`, `format: "svg-<naming>"`).
- `search_icons` added `__exact_match` smallint as position 2 — the generated model picked it up automatically, no consumer changes needed (additive).

## 2026-04-15 — Colorization fixes for Material, unified live-SVG helper

### Material preset colorization works across the modal
Material's SVGs ship with `fill="currentColor"` on the root and NO fill attribute on child paths — they rely on SVG inheritance. That pattern hit four separate rendering paths in the app, each with a different bug:

- **`ColorPicker.updateSvgColors`** (preset change → modal preview) was walking `svg path, svg circle, …` but never the `<svg>` root, and skipping any element without an existing fill/stroke. Material's root kept whatever colour was applied on first load, paths never got updated. Now touches the root too.
- **`DesignerExport.colorizeSvg`** (designer canvas) colorized via regex then rasterized through `<img src=blob>` — but `<img>`-rasterized SVG doesn't reliably honor root-fill inheritance to child paths. Rewrote to DOM-parse, update root + existing fill/stroke, then explicitly stamp `fill="${color}"` on paths that have neither a fill nor a stroke attribute (only when the root actively uses fill, so Lucide-style stroke-only sets are untouched).
- **`DownloadDesigner.renderPreview`** had a race where rapid preset clicks interleaved async SVG loads and the older render painted on top of the newer one. Added a generation counter — stale `img.onload` callbacks now bail before `drawImage`.
- Download-arrow `<svg>` (inside the preview section's `<a class="download-link">`) was getting recoloured along with the preview icon because `updateSvgColors` was too broad. Narrowed to `.svg-container > svg`.

### Shared `colorizeLiveSvg` helper
Extracted the live-DOM colorization logic as a single top-level function used by three of the four paths:

- Grid/list (`IconColorFilter.colorizeSvg`)
- Modal preview first load (`InlineSvg.loadSvgs` — no longer does regex replacement before `innerHTML`)
- Modal preset change (`ColorPicker.updateSvgColors`)

The designer canvas keeps its own function because it additionally needs the naked-path fill stamp for the `<img>` rasterizer.

### Debug logging in the designer pipeline
Added `console.group` output for preset clicks, `renderPreview` settings, `colorizeSvg` before/after attrs, and post-draw pixel samples from the canvas. Useful for tracing colour-propagation bugs; low volume so left in place.

## 2026-04-14 — Material platform identifiers, Naming helper, modal gating fix

### Material platform identifiers
- Dedicated `PureAdminIcons.IconSets.Material` formatter registered —
  Material icons now surface iOS, Android, React, CSS class, and HTML tag
  identifiers in the detail modal
  - CSS class: `material-symbols-{outlined,rounded,sharp}` (modern Symbols
    convention); `filled` / `outline` both map to `-outlined` since FILL
    is a font-variation axis, not a separate class. `duotone` falls back
    to legacy `material-icons-two-tone`
  - HTML tag: `<span class="material-symbols-outlined">close</span>` — uses
    the icon name as ligature text. New optional `htmltag_identifier/2`
    callback on `IconSets.Formatter` behaviour lets per-set modules override
    the generic `<i class="...">` wrapping
  - React: `@mui/icons-material` with PascalCase + style suffix
    (e.g. `import AddHomeOutlined from '@mui/icons-material/AddHomeOutlined'`)
  - iOS: `UIImage(named: "add_home")` — snake_case name
  - Android: `@drawable/add_home_24` — name + default size (Google Fonts
    Icons default when downloading vector drawables)
- Material adapter updated to emit matching `ios_identifiers` /
  `android_identifiers` shapes; requires a re-sync to propagate

### Naming helper
- New `PureAdminIcons.Naming` module with `snake_case`, `kebab_case`,
  `pascal_case`, `camel_case`, `title_case` — all accept mixed separator
  input (`[-_\s]+`)
- Removed 10 duplicated private helpers (`to_camel_case`, `title_case`,
  `to_snake_case`, `to_lower_camel_case`, `to_fa_camel_case`) across 8
  adapters + `ZipParser` + Material formatter. Single source of truth for
  casing semantics

### Modal gating fix
- Svelte and React platform sections now correctly gate on *both* the
  user's platform preference AND the current icon set having a non-nil
  package. Previously, toggling Svelte on for a Lucide icon and then
  opening a Material icon would render an empty Svelte block; Material
  doesn't ship a canonical Svelte package so the section shouldn't show.
  iOS / Android / Vue / CSS Class / HTML Tag already had this guard;
  React and Svelte were the odd ones out

## 2026-04-14 — Runtime translations (DB-backed, per-locale, cached)

### Translation subsystem
- `PureAdminIcons.Translations` module with `t/1`, `t/2`, and `interpolate/2` — mirrors the `keen-pure-admin` pattern. App-configurable callback via `config :pure_admin_icons, :translate`; falls back to `@defaults` (English) when the callback returns `nil`
- `PureAdminIcons.Translations.DbProvider` — reads from `public.get_group_translations(lang, 'frontend', 'text', tenant_id)`, caches the flat `{code → value}` map per locale in `:persistent_term`. `refresh/0` / `refresh/1` drop the cache after writes
- `PureAdminIcons.Translations.Locale` — process-dict storage for the current locale (`get/0`, `put/1`, `default/0`); used transparently by `t/2`

### Locale resolution
- `PureAdminIconsWeb.Plugs.Locale` — plug + LiveView `on_mount` hook. Priority: `?lang=xx` query param → **session cookie** (sticky choice) → `Accept-Language` header → `default_locale` config. Only whitelisted tags in `supported_locales` are accepted; invalid values fall through
- Plug added to the `:browser` pipeline; live routes wrapped in `live_session :default, on_mount: {Plugs.Locale, :default}` so LiveView processes inherit the session's locale
- Language choice persists via Phoenix session cookie — picking a locale once sticks across navigation

### Language switcher UI
- `Layouts.language_switcher/1` component rendered in the site nav (desktop + mobile), visible only when `length(supported_locales) > 1`
- Positioned with Floating UI (`bottom-end`, `flip`, `shift`, `autoUpdate`) for the same behavior as the theme switcher and preset picker — click to toggle, outside-click / Escape to close
- `assets/js/language-switcher.js` module mirroring `theme-manager.js`
- `Icon Sets` link added to nav between Docs and API (desktop + mobile)

### Key convention
`[domain].[specifier].[identifier]` — e.g. `iconSets.headers.pageTitle`, `iconSearch.messages.resultsRange`, `common.buttons.copy`. ~152 keys seeded across 11 domains; English defaults live in source so the app works without a DB roundtrip for any key. `common.*` absorbs strings repeated across domains (tables headers, buttons, pagination, scalable label)

### Supported languages
- `en` — English (source of truth, lives in `@defaults`)
- `cs`, `de`, `fr`, `es` — translations in `priv/translations/<lang>.json`; missing keys fall back to English at runtime

### Seed & tooling
- `../pure-admin-icons-database/upsert_frontend_translations.sql` — idempotent upsert of all 5 languages (760 rows), ends with `PERFORM internal.refresh_translation_cache()` and a `CALL` of the wrapping procedure
- `mix translations.gen` — regenerates the SQL from `@defaults` (English) + `priv/translations/*.json` (other languages). Deterministic output grouped by language banner then by domain; add a key to `@defaults`, optionally translate in each JSON, then regenerate

### Migrated pages
All user-visible strings behind `t(...)` calls in: `/`, `/docs`, `/docs/icon-sets`, `/docs/api`, `/docs/mcp`, `/docs/llms`, `/stats`, `/sync/discrepancies`, the icon detail modal, and the site nav. Long-form doc prose (API examples, MCP install instructions) is deliberately left inline — better suited to document-level translation than key-based

### DB-gen
- Added `get_group_translations` to `db-gen.json` — generated model + processor handle the single-row flat-map JSONB return shape

## 2026-04-13 — Three new icon sets, canonical style vocabulary, brand colors

### New icon sets
- `phosphor` — Phosphor Icons (MIT), 6 weights: thin/light/regular/bold/filled/duotone
- `remix` — Remix Icon (Apache 2.0), styles: outline/filled
- `material` — Material Symbols (Apache 2.0), styles: filled/outline/rounded/sharp/duotone
- All three are scalable (`has_single_source: true`), single SVG per icon

### Canonical style vocabulary
- Unified style codes across all sets: `outline`, `filled`, `thin`, `light`, `regular`, `bold`, `rounded`, `sharp`, `duotone`, `color`, `brands`
- Adapter renames: fluentui `regular`→`outline`, lucide `regular`→`outline`, heroicons `solid`→`filled`, fontawesome `solid`→`filled`/`regular`→`outline`, phosphor `fill`→`filled`, remix `line`/`fill`→`outline`/`filled`, material `outlined`/`round`/`twotone`→`outline`/`rounded`/`duotone`
- On-disk SVG dirs use canonical names; native names preserved per-set in `const.icon_set.native_style_names`

### Schema-driven brand colors
- New `PureAdminIcons.IconSets.Color` module reads `const.icon_set.brand_color` and renders inline `style="background-color: …; color: …"` with auto-contrast text
- Removed 4 hardcoded `icon_set_color/1` clause stacks from LiveViews
- Cache via `:persistent_term`, refreshed automatically after `Sync.Worker.sync_all`
- New sets get the right colors with no code change

### `has_single_source` / `is_scalable` split
- `is_scalable` (renamed in DB to `has_single_source`) split into two flags: `has_single_source` = single SVG renders any size (drives ∞ pill + size-filter bypass); `is_scalable` = vector vs raster
- LiveViews + API + `Icon.scalable?/1` updated to read `has_single_source` for the "ignore size" semantic

### Unified `platform_identifiers`
- Replaces per-platform `ios_identifiers` / `android_identifiers` columns with one `platform_identifiers jsonb` (`{"ios":…, "android":…}`)
- New `Icon.platform_ids/2` helper centralizes the lookup; tolerates both old and new shapes during transition
- Worker collapses adapter-emitted `ios_identifiers`/`android_identifiers` into the unified jsonb at COPY time — no adapter changes needed

### Sync pipeline fixes
- Material/Remix dedupe on the DB's normalized identity (lowercase + strip `[-_\s]`), matching `nrm_original_name`. Fixes `add_chart`/`addchart` collision in Material's multi-category source tree
- Worker COPY column list updated to `platform_identifiers` (was `ios_identifiers, android_identifiers`)

## 2026-04-13 — Floating UI dropdowns, cursor polish

### Theme switcher uses Floating UI
- Collapsible theme switcher panel is now positioned with Floating UI (`placement: top-end`, `flip`, `shift`, `autoUpdate`) so it stays on screen on narrow viewports
- Inline `onclick` toggle and inline `<script>` in `root.html.heex` replaced by `initThemeSwitcherDropdown()` in `theme-manager.js`
- Outside-click and Escape close the panel; active label/icon update moved into the module

### Preset dropdown uses Floating UI
- `QuickPresets` dropdown ("Road Sign"/preset picker above the icon list) switched from `absolute right-0` to Floating UI `bottom-end` with `flip` + `shift`, fixing mobile clipping off the left edge
- Dropdown width pinned to `w-44` so fixed-positioning doesn't let content expand it

### Cursor polish
- Added `cursor-pointer` to the three "Copy" buttons in the icon detail modal (Svelte identifier + CSS Class blocks)

---

## 2026-04-12 — DesignerExport shared module, quick download from popovers

### DesignerExport shared JS module
- Extracted `colorizeSvg`, `renderToCanvas`, `downloadPngZip` (with manifest + readme generation) from the DownloadDesigner hook into a standalone `DesignerExport` module
- Reads all settings (padding, radius, colors, sizes) from localStorage — works without the DownloadDesigner hook being mounted
- DownloadDesigner hook now delegates to `DesignerExport` for all export operations

### Quick PNG ZIP download from grid/list popovers
- Every floating popover (hover tooltip on size pills and checkmarks) now includes a download icon button at the end
- Clicking it calls `DesignerExport.downloadPngZip()` with the icon's SVG URL and saved designer settings — one-click export without opening the detail modal
- Button dims while generating; handler is delegated via the FloatingPopover hook

### Designer size persistence
- Size checkboxes and custom size input now persist to localStorage across dialog close/reopen
- Custom size field widened to `w-28` with "Custom size" placeholder

---

## 2026-04-12 — Theme switcher, metrics tracking, event loop fix

### Collapsible theme switcher
- Theme switcher is now collapsible: collapsed state shows a small box with "Theme" label + active theme name and icon
- Clicking opens a vertical panel that slides up above the trigger with all 5 options
- Clicking outside closes the panel
- Distinct icons per theme: outline sun (Morning), solid sun (Day), outline moon (Evening), solid moon (Night), clock (Auto)
- Active theme icon displayed in the collapsed trigger, updates on selection

### Designer download metrics tracking
- PNG ZIP and SVG downloads from the Download Designer now tracked via `track_download` with `platform: "designer:png-zip"` / `"designer:svg"`

### ColorPicker event loop fix
- `updateSvgColors()` no longer dispatches `iconColorChanged` — callers dispatch explicitly when they intend to notify the grid
- Eliminates infinite loop where ColorPicker's `iconColorChanged` listener called `updateSvgColors` → dispatched `iconColorChanged` → re-entered the listener
- Modal preview SVGs still update correctly on external color changes (QuickPresets, DownloadDesigner import)

---

## 2026-04-12 — Download Designer

### Download Designer section in icon detail modal
- New section between icon previews and platform identifiers for generating customized icon exports
- **Live preview** (128px retina canvas) — updates in real-time as settings change
- **Include colors** — applies the active preset's icon color + background
- **Padding** — 0–40% slider for gap around the icon
- **Corner radius** — 0–50% slider for rounded corners (50% = circle, good for app icons)
- **Size selection** — checkboxes for 32/64/128/256/512/1024px + custom size input (1–4096px)
- **Download PNG ZIP** — renders at all selected sizes with padding, corners, and colors baked into PNGs, packed into a ZIP with:
  - `manifest.json` — machine-readable settings (colors, padding, radius, preset name, file list, source URL, timestamp)
  - `readme.txt` — human-readable summary with icon info, settings, file list, re-import instructions, license note
- **Download SVG** — exports a single SVG with expanded viewBox for padding, `<rect rx>` rounded background, and colorized paths
- **Import Settings** — file picker for `manifest.json` from a previous ZIP; restores all settings (padding, radius, sizes, colors). If the preset name doesn't exist locally, auto-creates a custom preset with that name and colors
- All settings persist to localStorage; preview listens for `iconColorChanged` events so preset changes in the combo are reflected immediately
- Vendored JSZip 3.10.1 (~98KB UMD) for client-side ZIP generation

### SVG download with colors (per-size buttons)
- The individual SVG download buttons per size still respect the designer's "Include colors" checkbox — fetches the SVG, colorizes, and downloads the modified file as a blob

---

## 2026-04-12 — Preset system rework, UI polish

### PresetManager — single source of truth for color presets
- New shared `PresetManager` JS module replaces duplicated preset logic across ColorPicker (modal) and QuickPresets (results bar) hooks
- Built-in presets parsed once from `#quick-presets` `data-presets` attribute (cached); custom presets from localStorage
- `getAll()`, `getSorted()`, `renderDropdown(container)`, `syncTrigger(swatch, label)` — both hooks delegate all preset operations here
- No more duplicated merge/sort/render code between hooks

### Preset combo dropdown (results bar + modal)
- Both the results bar and modal now use the same dropdown combo pattern: trigger (swatch + label + chevron) → vertical A-Z sorted list of all presets (built-in + custom merged)
- Replaced the old modal More/Less toggle + badge list with the combo dropdown
- Both combos stay in sync via `iconColorChanged` event — selecting in the modal updates the results bar and vice versa
- QuickPresets `updated()` rebuilds the dropdown and syncs trigger after LiveView DOM patches

### Custom preset management in modal
- **"Preview:" → "Colors:"** label rename
- **New button**: opens the custom color area with Icon/Bg pickers pre-filled from the currently selected preset's colors (not reset to defaults)
- **Delete button**: next to "Save as preset", removes the active custom preset
- **Transparent background**: checker-pattern toggle button next to the Bg picker; save handler reads bg from localStorage so "checker" value is preserved
- Custom area shown automatically when a custom preset is selected (from either combo or on dialog open), hidden when a built-in preset is selected

### Button height consistency
- `.btn-action` bumped to `py-3 rounded-lg` to match the search input height
- `.view-toggle` wrapper bumped to `p-1.5` for breathing room
- Filters button wrapped in `.view-toggle` container for identical height/border as Grid/List toggle

### Filter panel layout
- Labels (Sets, Styles, Sizes) are now block headings above their checkboxes instead of inline — wraps cleanly on narrow screens
- Smaller checkboxes (`w-4 h-4`) and text (`text-sm`) for a tighter, cleaner look

---

## 2026-04-12 — Modal LiveComponent extraction, SVG preservation fix

### Icon modal extracted to LiveComponent
- Moved the ~570-line `defp icon_modal/1` from `IconSearchLive` into a standalone `IconModalComponent` (`lib/pure_admin_icons_web/live/icon_modal_component.ex`)
- Stateful LiveComponent with `id="icon-modal"` — provides a rendering boundary so modal open/close only re-renders the component, not the parent grid/list
- Events (`close_modal`, `toggle_platform`, `track_download`, `track_copy`) bubble to the parent LiveView — existing handlers work unchanged
- Helper functions (Formatter wrappers, color/preset helpers) are self-contained in the component
- Modal conditional wrapped in stable `<div id="modal-container">` to prevent morphdom sibling count changes
- Parent `icon_search_live.ex` shrunk by ~560 lines

### SVG preservation with `phx-update="ignore"`
- Root cause: LiveView's morphdom was wiping JS-loaded SVG innerHTML from icon preview elements on modal open/close, but `updated()` only fired on open (not close), so SVGs were never restored after closing
- Grid view appeared unaffected because hidden (`display:none`) elements never had SVGs loaded by IntersectionObserver in the first place
- Fix: each icon's SVG container now has `phx-update="ignore"` with a unique ID (`grid-svg-{id}`, `list-svg-{id}`, `mobile-svg-{id}`), telling LiveView to never touch the element after initial render
- `IconColorFilter.updated()` cleaned up — `loadAllSvgs` only runs when icons actually change (new search/page), no more band-aid reload on every patch

---

## 2026-04-12 — Stats page, source tracking, SVG hash, version detection

### Stats page (`/stats`)
- New `AdminStatsLive` page showing overview metrics (copies, downloads, searches) broken down by source (web/api) and period (today, 7d, 30d, all time)
- Popular icons table with period toggle (1d/7d/30d/all) and source filter (all/web/api)
- Auto-refreshes every 30s; cube refreshes every 3 min (prod) / 10s (dev)
- New `get_stats_overview()` DB function, model, and processor
- Stats link added to desktop and mobile nav

### Source tracking
- `source_code` added to `icon_metric`, `icon_metric_cube`, and `search_metric` tables — all callers now pass `"web"` or `"api"` explicitly
- `track_icon_action` and `track_search` require `source_code` as 3rd parameter (no default)
- Cube groups by `source_code` as a new dimension; `get_popular_icons` and `get_popular_icon_sets` gained optional `_source_code` filter
- Updated `Icons.track_action/4`, `SearchMetricsCollector.record/6`, LiveView handlers (`"web"`), API controller (`"api"`)

### SVG content hash
- Each sync adapter now computes SHA-256 of actual SVG file content during `parse()` and includes `:svg_hash` in the icon map
- Multi-size icons (FluentUI, Heroicons) hash all size variants concatenated in sorted order
- Worker's `compute_icon_hash` prefers the adapter's `svg_hash` over the legacy metadata-only MD5
- DB migration added `svg_hash` column to `public.icon` and `first_seen_version` to `public.icon`; `stage._process_icons()` compares and stores it

### Version detection
- Worker's `detect_version/1` scans `package.json`/`lerna.json` in the extracted directory to find the package version
- Version is passed in `job_data` when creating the job run; DB procedure reads it to populate `first_seen_version` on new icons and `last_synced_version` on `const.icon_set`
- Download step moved before job run creation so version is available in the job_data

### Metrics cube refresher
- New `MetricsCubeRefresher` GenServer replaces reliance on Quantum for frequent cube updates
- Dev: refreshes every 10s; Prod: every 3 min; disabled when config not set

### Logo dark theme fix
- Added `text-base-content` to the logo `<a>` tag so non-"pure" text follows the theme (white in dark themes, black in light themes)

### Download naming tracking
- Download events now include the filename convention (original/kebab/snake/pascal) in `platform_code` as `"download:{convention}"`

---

## 2026-04-10 — Styled error pages, per-icon popover fix

### Custom error pages
- Replaced the plain-text Phoenix error pages with styled, self-contained HTML pages matching the site's branding
- Big `icons.pureadmin.io` logo header with golden "pure" accent, status code, title, description, and "Back to icon search" button
- GitHub icon link in top-right corner linking to `KeenMate/pure-admin-icons`
- Time-of-day theme support via inline script — morning/day/evening/night color schemes matching the main site, CSS variable swap with no FOWT
- Generic handler covers all HTTP status codes (named messages for 400/403/404/408/500/502/503/504, fallback for others)
- Error preview route at `/errors/:code` for testing (e.g. `/errors/404`, `/errors/500`)

### Per-icon platform popover fix
- Fixed grid/list hover popover buttons showing iOS/Android for all icons regardless of icon set — now each icon's popover only shows platforms the set actually supports (via `Formatter.*_package/1` callbacks)
- Fixed Formatter module alias scope crash (500 on every page load in production)

---

## 2026-04-09 — Per-icon platform popover fix ✅ PUBLISHED

### Grid/list popover buttons leaked across icon sets
- The hover popover on grid pills and list checkmarks used a single global `@platform_prefs` for **all** icons regardless of icon set, so every icon (Heroicons, Lucide, Tabler, Font Awesome) was showing iOS/Android copy buttons — even though only FluentUI has native iOS/Android distributions
- After opening any icon detail modal, `@platform_prefs` got replaced by that one icon's per-set prefs and then leaked back into all the grid/list buttons (e.g., open a Heroicons icon → close → now every icon in the grid shows Svelte/CSS Class buttons)
- New helper `preferred_platforms_for/3` resolves the prefs **per icon**: looks up the icon's set's own prefs from `@platform_prefs_by_set`, then filters to only the platforms the set actually supports (via `Formatter.{ios,android,react,vue,svelte,cssclass}_package(icon)` returning a non-nil package name)
- New helpers `platform_supported?/2` and `package_present?/1` perform the support check
- `icon_grid` and `icon_list` now receive `platform_prefs_by_set={@platform_prefs_by_set}` instead of the global `platform_prefs` and use `preferred_platforms_for(icon, @platform_prefs_by_set, 2)` at the four popover call sites — each icon now shows only the platforms relevant to its own set, computed independently
- The modal still uses `@platform_prefs` since it only ever shows one icon at a time and the existing `select_icon` handler already populates that correctly

---

## 2026-04-09 — Floating-UI popovers, semantic CSS extraction, control polish ✅ PUBLISHED

### Floating-UI for copy-button popovers
- Vendored `@floating-ui/core@1.6.9` and `@floating-ui/dom@1.6.13` UMD bundles into `priv/static/assets/vendor/`, loaded via `<script defer>` in `root.html.heex` before `app.js`
- New `Hooks.FloatingPopover` JS hook (attached to a `#icon-display-popovers` wrapper around `#icon-display`) — uses event delegation to find `.has-popover` triggers and position their child `.floating-popover` element
- Uses `computePosition` with `strategy: 'fixed'` so ancestor `overflow:hidden` (table wrapper) no longer clips popovers
- Middleware: `offset(2)` (sits 2px above trigger so cursor barely needs to traverse a gap), `flip()` (auto-flips below if no room above), `shift({padding: 8})` (slides horizontally to stay within viewport)
- 150ms hide-debounce so the user can move from trigger to popover without it disappearing; cancelled by `mouseenter` on the popover itself
- **Grid view** — size pills (`24px`, `∞`) replaced their `.size-cell` + `.size-popover` markup with the unified `.has-popover` pattern
- **List view** — `✓` checkmarks and `∞ Scalable` cells replaced the old `.list-cell-hover` opacity-overlay pattern with the same `.has-popover` markup
- Size column widths reverted to compact `w-16` — popovers no longer affect column layout since they float on top of neighboring cells

### Semantic CSS class extraction
- Added one block of semantic component classes at the bottom of `app.css` to replace repeated utility-class soup in templates
- New classes: `.view-toggle`, `.btn-action`, `.btn-pager` / `.btn-pager-disabled`, `.icon-card-body`, `.icon-card-name`, `.icon-card-thumb`, `.icon-card-sizes`, `.list-row`, `.has-popover`, `.floating-popover`, `.floating-popover-btn`
- `icon_grid` and `icon_list` templates significantly slimmer — popover-button markup now writes once and applies to all 4 places (grid scalable, grid sized, list scalable, list sized)
- Renamed grid card `.icon-card-preview` → `.icon-card-thumb` to avoid colliding with the existing JS slider hook that targets `.icon-card-preview` for the **mobile** card layout

### Pager and control polish
- **Pager buttons** (Previous / Next) now use `btn btn-sm btn-ghost border border-base-content/20` matching `pure-admin-io`'s ghost button style — clearly visible white borders in night theme (was unstyled `bg-base-300` blending into the background)
- **Top pager moved** out of the hero `max-w-5xl` section into the main `max-w-7xl` content area so it aligns vertically with the bottom pager regardless of view mode
- **View toggle wrapper** (Grid/List segmented control) and the Filters button now both have visible `border-base-content/20` outlines for consistency with the new ghost-button style

---

## 2026-04-08 — MCP package rename

- All references to `@keenmate/fluentui-icons-mcp` updated to the new `@keenmate/pure-admin-icons-mcp` package
- Updated home page MCP link, API docs MCP example, MCP docs page (Claude Desktop config + Claude Code command)
- Claude Desktop config example now uses Windows-friendly form: `npx -y -p @keenmate/pure-admin-icons-mcp pure-admin-icons-mcp`

---

## 2026-04-08 — Honest platforms, download naming, mobile polish ✅ PUBLISHED

### Honest platform identifiers
- iOS and Android sections only shown for icon sets that have **real** native distributions (currently only FluentUI)
- Removed the fake `calendar24` / `ic_heroicons_calendar_24_solid` style identifiers that were generated for icon sets without iOS/Android packages (Heroicons, Lucide, Tabler, Font Awesome Free)
- iOS/Android section headers now include linked package name like the other platforms
- Two new behaviour callbacks `ios_package/1` and `android_package/1` on `IconSets.Formatter` — only FluentUI returns non-nil

### Download filename naming
- New "Filename:" dropdown next to "Available Sizes" in the detail modal
- Choose **Original / kebab-case / snake_case / PascalCase** for SVG downloads
- Selection persists to localStorage
- Extension preserved from the original filename
- Heroicons-style icons keep their `-{size}` suffix when the original had one

### Filename template fix
- `{filename}` placeholder now uses the **real filename from the DB** instead of hardcoded `ic_fluent_*` (was a leftover from FluentUI-only days)
- When using `{name_kebab}` etc, the extension is auto-appended from the original filename if not already present

### Grid layout polish
- Card grid now uses `flex flex-wrap justify-center` with fixed `w-44` cards — results centered horizontally regardless of count
- "Showing 1-30 of N icons" hidden when there are zero results
- "Filters" / "Grid" / "List" buttons show only icons on mobile (labels appear at `sm` breakpoint)

### Svelte code formatting
- Heroicons Svelte identifier now respects newline (`whitespace-pre-line` added to the `<code>` element)
- Import line and `<Icon>` line now appear on separate lines

---

## 2026-04-08 — Universal/scalable size, grid sizes polish ✅ PUBLISHED

### Universal "Scalable" size
- New `is_scalable` flag (DB-side) for icon sets that have a single SVG that scales to any size
- **Lucide, Tabler, Font Awesome** marked as scalable — instead of pretending they're "24px", we now show them as scalable
- **FluentUI and Heroicons** stay non-scalable since they have hand-tuned variants per size
- **Grid card** shows `∞` symbol (large, bold) with hover-to-copy popup for scalable icons
- **List view (mobile)** shows `∞` badge instead of size badges
- **List view (desktop)** uses `colspan` to merge size columns into a single "∞ Scalable" cell with hover-to-copy
- **Detail modal** shows a single "Preview — Scalable, renders at any size" with one preview at 96px instead of multiple size previews
- **Sizes filter** gets a new "∞ Scalable" pseudo-checkbox at the top (only when scalable sets exist in the union)
- **Active filter badges** show "∞ Scalable" instead of "0px"
- **API responses** include `is_scalable` flag on icons and icon sets
- **Search context** translates `size: 0` filter to `is_scalable: true` criterion
- **Icon helpers** — `Icon.svg_url`, `Icon.svg_filename` ignore the size argument for scalable icons
- **Formatter modules** — identifier sizes return `[0]` for scalable icons so the modal renders one row instead of looping

### Grid card sizes polish
- Sizes use a custom `font-size: 0.8rem` with `font-semibold` and primary color
- ∞ symbol is `text-2xl font-bold` so it stands out as the focal point
- ∞ symbol in detail modal preview is `text-3xl font-bold` (was tiny `text-xs`)

### Preset toggle button
- "More / Less" button now uses an SVG chevron icon on the left, matching the Copy CSS / Import CSS button style
- Icon rotates 180° when expanded (down → up chevron) with smooth transition
- Label is a separate `<span>` so it can be swapped without re-rendering the icon

---

## 2026-04-08 — Grid card redesign ✅ PUBLISHED

### Grid card layout
- **Top accent bar** colored by icon set (blue=fluentui, violet=heroicons, orange=lucide, cyan=tabler, yellow=fontawesome) — replaces the icon set badge, follows card's rounded corners
- **Title moved to top** above the icon
- **Style badge under the title** (centered) — only shown when the result set contains multiple styles, hidden when all icons share one style
- **Larger icon preview** (w-20 h-20 wrapper, w-12 h-12 icon — was 16/10)
- **Sizes at bottom**, expanded (all sizes shown inline as plain text, wrap to multiple lines for FluentUI's 6 sizes)
- Card title attribute shows full `set / name` on hover

### Tooltip fix
- Removed `overflow-hidden` from icon cards so hover-to-copy tooltips can escape card boundaries
- Top accent bar now uses `rounded-t-lg` directly to keep matching the card's rounded corners
- Tooltips bumped to `z-50` so they appear above adjacent cards

---

## 2026-04-08 — Icon set formatter modules, Import CSS, Copy CSS dual block ✅ PUBLISHED

### Refactor: per-icon-set formatter modules
- All icon-set-specific identifier and package logic moved out of `icon_search_live.ex`
- New `lib/pure_admin_icons/icon_sets/` folder with one module per icon set:
  - `formatter.ex` — behaviour + dispatcher (registry + delegating helpers)
  - `generic.ex` — fallback for unknown sets
  - `fluentui.ex`, `fontawesome.ex`, `heroicons.ex`, `lucide.ex`, `tabler.ex`
- Each module implements `PureAdminIcons.IconSets.Formatter` behaviour with React/Vue/Svelte/CSS class identifiers and package metadata
- LiveView now has thin delegating wrappers — adding a new icon set requires creating one file in `icon_sets/` and registering it in `formatter.ex`'s `@formatters` map
- Removed ~150 lines of pattern-matched clauses from the LiveView

### Copy CSS — dual block output
- Output now includes both a **scoped** rule (with preset class) and a **global override** rule (no scope)
- New header format: `/* Generated by icons.pureadmin.io */`
- Preset comment is machine-parseable: `/* Preset — Transit (fontawesome) [color: #000000, background-color: #fbbf24] */`
- Both blocks share the same identifying header so users can paste either back to recreate the preset
- More professional comment formatting throughout

### Import CSS
- New "Import CSS" button next to "Copy CSS" — opens a paste textarea
- Two parsing strategies:
  1. **Preset comment** — parses `/* Preset — Name [color: #..., background-color: #...] */` to recover label + colors
  2. **Fallback** — extracts the first `color:` and `background-color:` from any CSS rule (label defaults to "Imported")
- Successful import creates a custom preset, activates it immediately, and updates all live previews
- Backwards compatible: accepts both `background:` and `background-color:` in the preset comment

---

## 2026-04-08 — Per-set platform prefs, CSS class platform, preview presets, Copy CSS ✅ PUBLISHED

### Per-icon-set platform preferences
- Platform toggle prefs (iOS, React, Vue, Svelte, etc.) are now stored **per icon set** in localStorage
- Switching from FluentUI to Font Awesome remembers each set's separate selection
- Migration: legacy flat shape is auto-applied to all sets on first load

### CSS Class & HTML Tag platforms
- New `cssclass` platform — bare class string (e.g., `fa-solid fa-arrow-right`) for menu configs, JSON, etc.
- New `htmltag` platform — full `<i class="..."></i>` element ready to paste
- Both only shown for Font Awesome and Tabler (icon sets with web font APIs)
- Hidden for FluentUI, Heroicons, Lucide

### Preview presets
- 10 built-in color presets: Classic Light/Dark, Neon Dark, Blueprint, Warm, Transit, Transit Inv, Expressway, Road Sign, Transparent
- Loaded from `priv/preview_presets.json` (single source of truth, shared between server and client)
- Custom presets — user can save their own color combinations with custom names
- Custom preset badges have a dedicated theme-colored × delete button
- Active preset always visible next to "Preview:" label, others hidden behind "More ▾" toggle
- Selecting a preset updates icon previews live across grid, list, and detail modal
- Background color picker added (separate from icon color)

### Copy CSS button
- New "Copy CSS" button next to "More" — generates ready-to-paste CSS for the active preset
- Icon-set-aware selectors:
  - Font Awesome: `i.{preset}.fa-solid, ...`
  - Tabler: `i.{preset}.ti`
  - SVG sets (Lucide, Heroicons, FluentUI): `svg.{preset}`
- Color-method aware: outputs `fill: currentColor` or `stroke: currentColor` based on each icon's actual color method
- Includes usage example for each framework (React, Vue, Svelte, plain HTML)
- CSS class name derived from preset key (e.g., "Neon Dark" → `neon-dark`)

### Tracking fixes
- Copy events now actually round-trip to the server (was JS-only, never written to `icon_metric`)
- Both modal copy buttons and grid/list hover-to-copy buttons track to DB now

### MCP server
- New `@keenmate/pure-admin-icons-mcp` package (`../pure-admin-icons-mcp`)
- 5 tools: `get_usage_guide`, `search_icons`, `get_icon_detail`, `get_icon_svg`, `list_icon_sets`

### llms.txt
- Rewritten to follow [llmstxt.org spec](https://llmstxt.org/) format

---

## 2026-04-08 — MCP server, llms.txt update ✅ PUBLISHED

### MCP server
- New `@keenmate/pure-admin-icons-mcp` package (separate repo at `../pure-admin-icons-mcp`)
- 5 tools: `get_usage_guide`, `search_icons`, `get_icon_detail`, `get_icon_svg`, `list_icon_sets`
- Multi-set support, format options (text/json/compact), Vue platform identifiers
- `get_usage_guide` tool (and `icons://docs` resource) returns the llms.txt content for AI clients

### llms.txt
- Rewritten to follow the [llmstxt.org spec](https://llmstxt.org/): H1 title, blockquote summary, bulleted markdown links
- Updated content: 16,000+ icons, 5 sets, all current API endpoints, color methods, MCP server reference
- Was: outdated FluentUI-only documentation

---

## 2026-04-07 — API endpoints, docs, footer, SEO

### API
- `GET /api/icons/:id` — single icon detail with full metadata (filenames, categories, phrases, svg_urls per size)
- `GET /api/icon-sets` — all icon sets with styles, sizes, license, `style_color_methods`, icon count
- `POST /api/maintenance/sync/:icon_set` — per-set sync (e.g., `fontawesome`, `fluentui`)
- Search response now includes `style_color_method` per icon
- Icon sets response includes `style_color_methods` jsonb map
- API docs page updated with all new endpoints, response fields, and examples

### Footer
- Proper 3-column footer: branding + icon count, resource links, icon sets with homepage links
- Bottom bar with license note and last sync time
- Sticky to viewport bottom when content is short

### SEO
- Updated meta tags: "16,000+ icons from 5 icon sets", Font Awesome and Vue mentioned
- Added keywords meta tag
- Dynamic page titles: search query in title (e.g., "calendar — Icon Search — icons.pureadmin.io")
- Page titles for all LiveViews (search, docs, discrepancies)
- Updated README with project overview, icon set table, API examples, stack info

### Fixes
- Discrepancies page now collects from all sync runs (was only showing latest, missing FluentUI's 783)
- Discrepancies page uses shared site nav and DaisyUI theme (was hardcoded light colors)
- Sync worker now stores full discrepancies list in `success_data` (was only storing count)
- Maintenance controller route added (was missing from router)
- Icon size slider hidden in grid mode (only relevant in list view)
- HEEx compilation error in API docs (JSON curly braces needed `phx-no-curly-interpolation`)
- Filename copy in grid/list hover buttons now applies the saved filename template from the detail modal (was copying raw filename only)

---

## 2026-04-07 19:50 — Font Awesome, dynamic filters, color method, UI polish ✅ PUBLISHED

### UI polish
- **Page loader** — full-screen themed loader while LiveView connects, prevents layout flash
- **Collapsible filters** — filters hidden behind a toggle button next to Grid/List; highlighted when active
- **Grid/List toggle** moved to search bar line with active state highlighting
- **Icon size slider** — adjustable icon preview size in list view (24–64px), persists to localStorage
- **Preview presets** — combined color+background presets in detail modal (Classic Light/Dark, Neon Dark, Blueprint, Warm, Transparent)
- **Responsive list view** — stacked cards on mobile, table on desktop
- **Icon set badge colors** — unique color per set across grid, list, active filters, and detail modal
- **Hover-to-copy on grid sizes** — hovering size badges shows platform copy buttons (same as list view)
- **Range slider** uses DaisyUI `range` component for dark theme visibility
- **Icon preview backgrounds** sync across grid, list, and detail modal from presets

### Bug fixes
- **Filter pruning** — switching icon sets now clears incompatible style/size selections (e.g., "filled" removed when switching from FluentUI to Font Awesome)
- **Filter persistence** — saved filters only restore on initial page load, not on every navigation (fixed loop bug)
- **SVG color replacement** — now handles `stroke`, `fill`, and `currentColor` (fixes invisible Lucide/Tabler outline icons)
- **db-gen template** — fixed hardcoded `FluentuiIcons.Repo` → `PureAdminIcons.Repo`

---

## 2026-04-07 19:50 — Font Awesome, dynamic filters, color method, UI improvements ✅ PUBLISHED

### Font Awesome Free
- New sync adapter downloading from npm registry (auto-fetches latest version)
- 3 styles: solid, regular, brands (~2855 icons after alias dedup)
- Platform identifiers for React (`@fortawesome/react-fontawesome`), Vue (`@fortawesome/vue-fontawesome`), Svelte (`svelte-fa`)
- Alias deduplication: `thumbtack`/`thumb-tack`, `eyedropper`/`eye-dropper`, etc. — identical SVGs, keep canonical name

### Dynamic filters
- Styles and sizes filters now adapt to selected icon sets (e.g., selecting Heroicons shows only outline/solid and 16/20/24)
- Filter order: Sets → Styles → Sizes (each on its own row)
- Filter selections persist to localStorage and restore on next visit
- Active filter badges match icon set colors; "Clear all" moved inline with active filters

### Color method
- New `style_color_method` from DB: `"fill"`, `"stroke"`, or `"multicolor"` per icon
- Detail modal shows CSS hint (`CSS: fill / color` or `CSS: stroke / color`)
- Multicolor icons hide the color picker with "not recolorable" message
- SVG color replacement now handles both `fill` and `stroke` attributes, including `currentColor`
- Icon previews use light background (`bg-white/80`) instead of theme-dependent recoloring

### UI improvements
- Grid/List toggle moved next to search bar with active state highlighting
- Icon set badges colored per set (FluentUI blue, Heroicons violet, Lucide orange, Tabler cyan, Font Awesome yellow)
- Set column added to list view
- List view: responsive cards on mobile, table on desktop
- Vue platform section added to icon detail modal (Lucide, Tabler, Heroicons, Font Awesome)
- All non-FluentUI identifiers include import statements
- Package names in section headers link to npmjs

### Tooling
- `make db-gen` command (cross-platform, uses `db-gen-win.exe` / `db-gen-linux`)
- db-gen files, templates, and config added to project

---

## 2026-04-07 19:50 — Mobile-responsive nav, spring time schedule ✅ PUBLISHED

### Added
- **Shared site navigation** — `Layouts.site_nav` component with consistent header across all pages (search, docs, API, MCP, LLMs)
- **Mobile burger menu** — hamburger toggle with dropdown nav on small screens
- **Cross-site link** — "Themes" link to pureadmin.io in the nav bar

### Changed
- **Unified navigation** — replaced per-page "Back to docs/search" headers with shared `site_nav` on all pages
- **Higher contrast search & filters** — search bar and filter checkboxes use `base-content` opacity borders instead of `base-300`, visible on dark themes (evening/night)
- **Spring time-of-day schedule** — adjusted theme transition times for longer daylight:
  - Morning: 5:00–9:00 (was 6:00–11:00)
  - Day: 9:00–20:00 (was 11:00–16:00)
  - Evening: 20:00–22:00 (was 16:00–20:00)
  - Night: 22:00–5:00 (was 20:00–6:00)

### Removed
- Per-page "Back to docs/search" link headers — replaced by unified nav

---

## 2026-04-07 19:50 — Icon-set-aware platform identifiers ✅ PUBLISHED

### Platform identifiers now match each icon library's actual conventions

Previously, the React and Svelte sections in the icon detail modal were hardcoded to FluentUI conventions. Now each icon set generates correct import statements and component syntax for its own packages.

- **React**: FluentUI (`@fluentui/react-icons`), Lucide (`lucide-react`), Tabler (`@tabler/icons-react`), Heroicons (`@heroicons/react`) — each with correct component naming and import paths
- **Vue** (new section): Lucide (`lucide-vue-next`), Tabler (`@tabler/icons-vue`), Heroicons (`@heroicons/vue`) — hidden for FluentUI (no official Vue package)
- **Svelte**: FluentUI (`svelte-fluentui`), Lucide (`lucide-svelte`), Tabler (`@tabler/icons-svelte`), Heroicons (`svelte-hero-icons`)
- All non-FluentUI identifiers now include the import statement alongside the component usage
- Package names in section headers link to npmjs (React, Vue) or project homepage (Svelte)
- Single identifier row for icon sets where the component name doesn't vary by size (avoids duplicate rows)
- "Include color" checkbox in Svelte section only shown for FluentUI (svelte-fluentui-specific feature)

## 2026-04-06 — Initial release

### New project: icons.pureadmin.io

Rebuilt from scratch as a Phoenix 1.8 project, replacing the old fluentui-icons Phoenix 1.7 codebase. Now shares the same visual stack as pureadmin.io.

### Stack

- Phoenix 1.8 + LiveView 1.1
- Tailwind CSS v4 + DaisyUI (same theme plugin as pureadmin.io)
- Heroicons v2.2.0 via Tailwind plugin
- Time-of-day theme system (4 themes: morning, day, evening, night)
- Same OKLCH color definitions as pureadmin.io

### Features ported from fluentui-icons

- Icon search with full-text + trigram + synonym matching
- Multi-icon-set support: FluentUI, Heroicons, Lucide, Tabler
- Grid and list view with lazy-loaded SVG previews
- Icon detail modal with platform identifiers (iOS, Android, React, Svelte, filename)
- Color picker for SVG preview customization
- Filename template system with placeholders
- Copy to clipboard for all identifiers
- Style, size, and icon set filters
- Pagination
- SVG file serving from local storage
- Daily sync from GitHub (Quantum scheduler, 3 AM)
- Dev icon cache (.cache/icons/) to avoid re-downloading
- API: /api/icons/search, /api/health
- Sync discrepancies page
- Plausible analytics

### Branding

- Logo: icons.**pure**admin.io (matching pureadmin.io pattern)
- Navbar with heroicon-decorated links (API, MCP, LLMs, Keenmate)
- Hero gradient section for search/filters
- Floating theme switcher (bottom-right)
- FOWT prevention (inline script in head)

### Icon color sync

- Color picker in icon detail modal persists to localStorage
- Grid/list icons apply saved color on load (fill replacement)
- Changing color in modal instantly updates all visible icons via `iconColorChanged` event
- Works across all icon sets (FluentUI, Tabler, Lucide, Heroicons)

### Performance

- SVG icon routes served outside the `:browser` pipeline (no session/CSRF/LiveView overhead)
- Lazy loading with IntersectionObserver + SVG caching

### Config

- DB credentials via `.local.exs` / `dev.local.exs` (gitignored), following dhl-location-factory pattern
- `config.exs` loads `.local.exs` and `{env}.local.exs` if they exist
- Production config via environment variables in runtime.exs (DB credentials required)
- Dockerfile with 7zip/unzip for icon sync
- Dev port: 4020

### Database

- `filenames` jsonb column added to icons table (maps size to actual filename)
- Eliminates per-icon-set filename computation — direct lookup from DB
