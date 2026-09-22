# Audit-log metrics port

Replace the ad-hoc metrics trio (`public.search_metric`, `public.icon_metric`,
`public.icon_metric_cube`) with a generic, session-aware **event log** modelled on
`audit.*` in `gcp-documenthub-database`. Full port, with per-visitor sessions and
UTM/referrer capture.

## Why

Today's `/stats` numbers are misleading (diagnosed 2026-09-22 against the prod DB `-e db-01`):

- **Web "searches" are massively over-counted.** Search tracking lives in
  `IconSearchLive.handle_params`, which fires on *every* `push_patch` — every filter
  toggle, pagination, `clear_filters`, initial page load, and each debounced keystroke.
  Result: of **1,438** web "searches", **984 (68%) have an empty query** (pure
  navigation) and the 454 real-query rows collapse to **182 distinct queries**.
  API searches (1,268/1,272 real) are clean by comparison.
- **Copy/download were under-counted** until the 2026-09-21 fixes (basket bulk exports
  untracked, multi-size collapsed).
- **Copy/download read a daily cube** (`icon_metric_cube`, refreshed 04:00) while searches
  read live — two sources at two freshnesses, so the columns never line up.
- We already hand-rolled "survive icon deletion" in v1.20 by denormalizing identity onto
  `icon_metric`/`icon_metric_cube`. The audit pattern gives that for free via a jsonb
  snapshot, in one table, for every signal.

## Target shape (mirrors documenthub `audit.*`)

- **`audit.session`** — one row per visitor session. `session_uid` (app-generated),
  `source_code` (web|api|mcp), `user_data` jsonb, `request_data` jsonb (referrer, UA, ip
  hash, utm). Monthly range-partitioned by `created_at`.
- **`audit.event`** — the event stream. `session_uid` (soft link, no FK), `source_code`,
  `event_type_code`, `event_data` jsonb (the snapshot), `utm_data` jsonb. GIN indexes on
  both jsonb columns; btree on `(event_type_code, created_at)` and `(session_uid)`.
  Monthly range-partitioned by `created_at`.
- **`audit.event_type`** — lookup of allowed codes: `icon_searched`, `icon_copied`,
  `icon_downloaded`, `icons_zip_downloaded`. (Navigation — filter/paginate/empty query —
  is deliberately **not** logged; the taxonomy can grow later if we want a `browse` code.)
- **Constructors** (SQL functions, snapshot identity at write time):
  - `audit.create_session(_source_code, _session_uid, _user_data jsonb, _request_data jsonb)` → session_uid (insert-if-absent).
  - `audit.create_event(_session_uid, _source_code, _event_type_code, _event_data jsonb, _utm_data jsonb)` → void.
  - `audit.track_icon_search(_session_uid, _source_code, _query, _result_count, _size, _style, _icon_set_code, _utm_data)` — builds `event_data = {query, nrm_query, result_count, size, style, icon_set}`. Only called for real searches.
  - `audit.track_icon_action(_session_uid, _source_code, _icon_id, _action_code, _size, _surface_code, _format_code, _platform_code, _utm_data)` — joins `public.icon` to snapshot `{icon_id, icon_set_code, style_code, original_name, size, surface, format, platform}` and maps `action_code` → event_type (`copy`→`icon_copied`, `download`→`icon_downloaded`, zip→`icons_zip_downloaded`).
- **`audit.ensure_partitions(_months_ahead int default 3)`** — idempotent monthly partition
  pre-creation (both tables), copied from `internal.ensure_audit_partitions`. Retention =
  `DROP PARTITION`.
- **Reporting, computed LIVE from `audit.event`** (no cube — at these volumes a grouped
  scan is instant, and it kills the staleness):
  - `get_stats_overview()` — keep the **existing output shape**
    (`__source_code, __period_code, __action_code, __surface_code, __format_code, __count`)
    so `AdminStatsLive` barely changes. Map event_type → action_code
    (`icon_searched`→`search`, etc.). **Searches counted as
    `count(distinct (session_uid, nrm_query))` per period** so repeat/near-repeat searches
    within a session don't inflate; copy/download counted as `count(*)`.
  - `get_popular_icons(...)` — rewrite to read `audit.event` (`event_data->>'original_name'`
    etc.), same output shape. Survives deletion (snapshot).

## Decisions locked in (2026-09-22)

- Full audit-log port; deprecate the three old tables.
- Sessions **with** UTM/referrer capture.
- **No partitioning now** — ship flat tables; monthly partitioning is recorded as future
  work (memory `project-audit-event-log-partitioning`). No `ensure_partitions`/scheduler
  maintenance in this pass.
- **Old-table disposal:** copy rows into `audit.event`, then **rename** the three tables to
  `*_old` (keep). A later cleanup migration drops them once prod is verified.
- **MCP:** deferred until after web is tested; API accepts `x-session-id` now so MCP can
  opt in later without a DB change.

## Status (2026-09-22)

- **Phase 1 (DB migration `071_update_main_v1-21.sql`)** — ✅ applied + verified on **DEV**
  (default env). Backfill exact (1,354 searches after dropping empty-query noise; 40
  actions). All reporting functions run live off the event log. Constructors are
  **procedures** (create_event/track_icon_search/track_icon_action) so the generated
  `call …` wrappers are valid; `create_session` stays a function. **Not yet on PROD.**
- **Phase 2 (db-gen)** — ✅ allowlist updated (dropped retired public writers, added the
  `audit` schema block); regenerated. Wrappers: `audit_ensure_session`, `audit_create_event`,
  `audit_create_search_event`, `audit_create_icon_action_event`, `audit_create_icon_event`
  (named per the KeenMate PG guidelines — `ensure_*` upsert, `create_*_event` writers).
- **Phase 3 (app wiring)** — ✅ new `PureAdminIcons.Audit` context; `SearchMetricsCollector`
  carries session/utm/source; `handle_params` logs only real, changed queries;
  `Icons.track_action` + both API controllers thread `session_uid`; JS mints/persists
  `session_uid` + passes utm/referrer; cube refresher + scheduler job removed; dead Ecto
  schemas + "cube" maintenance task removed. Compiles clean, 15 tests pass, live
  end-to-end write verified on DEV.
- **Engagement events (DB v1.22 `072_…`)** — ✅ on DEV. Added `icon_detail_opened`,
  `icon_basket_added`, `icon_basket_removed` + `audit.track_icon_event` writer; wired
  `select_icon` (detail open) and `toggle_basket` (add/remove, only when the basket
  actually changes) in the LiveView. Captured for analytics; **not yet on the `/stats`
  cards**. Live-verified on DEV.
- **Client IP capture (2026-09-22)** — ✅ on DEV. Stored on `audit.session.request_data.ip`
  for geo (countries, derived **offline** — Traefik injects no country header) and abuse
  attribution/blocking. Web: added `:peer_data` + `:x_headers` to the LiveView
  `connect_info`; mount derives the IP (x-forwarded-for first hop, else peer) via
  `PureAdminIconsWeb.ClientInfo`. API: every tracked call now `ensure_session`s with the IP,
  using `x-session-id` when supplied else a synthetic `"ip:<addr>"` id so anonymous API
  traffic is still grouped + attributable. `ClientInfo` also de-duplicates the
  x-forwarded-for parsing that download/export previously hand-rolled. **Note: raw IP is
  PII** — covered by the blocking/analytics purpose; mind retention + privacy policy.
- **Pending:** user smoke-tests web locally → then PROD migration (`-e db-01`) + app deploy
  (lock-step) → MCP (`x-session-id`) → drop `*_old` tables in a later migration.

## Tasks

### Phase 1 — DB migration (`pure-admin-icons-database`, no `-e` = DEV first, then `-e db-01` = PROD)

- [ ] `071_update_main_v1-21.sql` (component `main`, version `1.21`), wrapped in
      `start_version_update`/`stop_version_update`.
- [ ] `create schema if not exists audit;`
- [ ] `audit.event_type` + seed the 4 codes.
- [x] `audit.session` (flat) + `audit.event` (flat). Created-only (`created_at`/`created_by`,
      no `updated_*` — append-only log, mirrors documenthub `_template_created`).
      Query-driven indexes only on the write-hot `audit.event`: `(event_type_code, created_at)`,
      `(session_uid)`, `((event_data->>'icon_id'))`. No low-cardinality/unused indexes
      (dropped `source_code`, standalone `created_at`, and the `event_data`/`utm_data` GINs).
- [ ] Constructors: `create_session`, `create_event`, `track_icon_search`,
      `track_icon_action`.
- [ ] New `public.get_stats_overview()` (live, session-deduped searches) — same columns.
- [ ] New `public.get_popular_icons(...)` / `get_popular_icon_sets(...)` /
      `get_icon_metrics(...)` reading the event log — same columns.
- [ ] Backfill: `search_metric` → `icon_searched` events (no session);
      `icon_metric` → `icon_copied`/`icon_downloaded` events (identity snapshot from the
      row's denormalized cols; `created_at` preserved via OVERRIDING/explicit insert).
- [ ] Rename old tables → `*_old`; drop `track_search`, `refresh_icon_metrics_cube`,
      old `track_icon_action` (keep signature compat shim? no — app is updated in lock-step).
- [ ] `CHANGELOG.md` v1.21 entry.
- [ ] Apply to DEV (no `-e`), verify, then PROD (`-e db-01`).

### Phase 2 — db-gen regeneration (`pure-admin-icons`)

- [ ] `db-gen.json`: add `audit.create_session`, `audit.create_event`,
      `audit.track_icon_search`, `audit.track_icon_action`, `audit.ensure_partitions`;
      keep `get_stats_overview`, `get_popular_icons`. Remove `track_search`,
      `track_icon_action` (public), `refresh_icon_metrics_cube` from allowlist.
- [ ] Regenerate models/processors (do **not** hand-edit `lib/database/`).

### Phase 3 — App wiring (`pure-admin-icons`)

- [ ] New `PureAdminIcons.Audit` context: `ensure_session/…`, `track_search/…`,
      `track_action/…`, building `event_data`/`utm_data` maps.
- [ ] **Session id + UTM.** Web: generate `session_uid` on LiveView connect, persist via
      localStorage (connect params) so it's stable across navigations/reconnects; capture
      referrer/utm/UA from connect params. API: honor `x-session-id`, else synthesize; pull
      utm from query/headers.
- [ ] Rework `SearchMetricsCollector` to buffer→`audit.track_icon_search` with
      session_uid/source/utm.
- [ ] **Fix search logging** in `IconSearchLive.handle_params`: record only when query is
      non-empty **and** changed vs `last_tracked_query` (skip prefix-growth churn); do not
      log filter/paginate/empty. Track `last_tracked_query` in assigns.
- [ ] Repoint `Icons.track_action` (+ `handle_event("track_download"/"track_download_batch"/"track_copy")`) to `audit.track_icon_action`.
- [ ] Repoint API controllers (`download_controller`, `icon_export_controller`,
      `icon_controller` search) to the audit context with session/utm.
- [ ] `AdminStatsLive` + API stats view: consume new `get_stats_overview` (shape preserved
      → minimal change); confirm labels still map (`1d/7d/30d/all`).
- [ ] Scheduler: drop the 04:00 `refresh_icon_metrics_cube` job and delete
      `metrics_cube_refresher.ex` + `Icons.refresh_metrics_cube` (stats are live now).
- [ ] Tests: audit context, search-dedup logic, stats overview shape.
- [ ] `mix precommit`.

### Phase 4 — MCP (optional, `pure-admin-icons-mcp`)

- [ ] Send a stable `x-session-id` + optional utm on API calls so MCP traffic groups into
      sessions. Bump version, changelog. (Can defer.)

### Phase 5 — Rollout

- [ ] Deploy app in lock-step with the PROD DB migration (SP signatures change).
- [ ] Verify `/stats` shows sane search:action ratios; spot-check `audit.event` counts
      vs old `*_old` tables.
- [ ] Follow-up migration later: drop `*_old` tables once confirmed.

## Notes / gotchas

- **Env topology:** DEV = default env (`db-01.km8.local`); PROD = `-e db-01`. Apply &
  verify on DEV first, then PROD. (`__version` on db-01 under-stamps — check columns, not
  just `__version`.)
- Partitioned tables can't have a PK/UNIQUE without the partition key → PK is
  `(id, created_at)`; no FK from event→session (integrity in the function layer), exactly
  as documenthub does.
- `nrm_query` uses `helpers.normalize_text` (same normalization already used elsewhere).
- Keep the `SearchMetricsCollector` GenServer buffering — batching writes is still good;
  only the target SP + payload change.
