# Plan: Bulk PNG/SVG ZIP export via API + MCP

Server-side rasterization and multi-icon ZIP download for the JSON API (and, later,
the `@keenmate/pure-admin-icons-mcp` package). Today PNG rendering exists **only**
client-side (canvas → `toBlob`, JSZip) in the basket; the server stores/serves raw
SVGs only. This adds a server path so API/MCP callers can request a ZIP of many icons.

## Decisions locked in

- **Renderer:** `resvg` CLI. Single self-contained binary, packaged in Debian trixie
  (our runtime base), invoked via `System.cmd/3` — same idiom as the 7z/unzip calls in
  the sync pipeline. No NIF, no Rust toolchain, no GNOME/cairo dep chain.
- **ZIP:** Erlang built-in `:zip.create/3` with `[:memory]`. Already used (for
  extraction) in `sync/svg_downloader.ex`. No new dependency.
- **Lookup key:** `(icon_set, name, style)` — each triple resolves to exactly one
  source SVG. Caller must specify style.
- **Client never supplies a filesystem path.** The request carries only
  `(set, name, style)` + output sizes. The name is a **DB lookup key**, not a path
  component. The app builds the path from trusted DB columns via `Icon.local_svg_path/2`.
- **Scope now:** SVG zip + PNG zip over the **API**. MCP tool is a follow-up in the
  separate npm repo.

## Open items (confirm before/while building)

- **Batch caps:** starting values `@max_units 200` (icons × sizes per request),
  `10 zip/min/IP`. Confirm a realistic max export size.
- **Per-icon tracking:** with `icon_id` resolved from the DB we *can* call
  `Icons.track_action/4` per icon (like `DownloadController`). Decide yes/no.
- **MCP binary return:** MCP tools return text/structured content — a raw ZIP is
  awkward. Choose base64 vs. a short-lived download URL when we get to the MCP tool.

---

## Tasks

### 1. Database — batch resolve function  *(separate repo: `../pure-admin-icons-database/`)*
- [x] Author `public.get_icon_details_by_keys(_pairs jsonb)` →
      `069_update_main_v1-19.sql` (v1.19). Expands the jsonb array with
      `jsonb_array_elements … with ordinality` and joins `mv_icon`.
- [x] **Joins on the identity key** `(icon_set_code, nrm_original_name, style_code)`
      via `helpers.normalize_name(name)` = `lower(regexp_replace(name,'[-_\s]+','','g'))`
      — the exact identity column (backed by `uq_icon_identity` /
      `ix_mv_icon_nrm_name`), NOT the trigram/FTS search columns.
- [x] Returns set-of-rows mirroring `get_icon_detail`: `__icon_id, __icon_set_code,
      __icon_set_title, __name, __nrm_name, __style_code, __sizes, __has_single_source,
      __is_scalable, __filenames`. No path returned.
- [x] Found-only semantics + `__request_index` (0-based) so the caller maps results
      back to requested triples and reports the misses.
- [x] CHANGELOG entry added (v1.19).
- [x] **Applied on db-01** (`updateDatabase -s 69 -n 69`, v1.19). SQL smoke-tested:
      mangled-case name resolves via identity, wrong style / missing name excluded.
- [x] Registered `get_icon_details_by_keys` in `db-gen.json` (public allowlist) and ran
      db-gen → `DbContext.get_icon_details_by_keys/1..2` + `GetIconDetailsByKeysModel` +
      `GetIconDetailsByKeysProcessor`. Compiles clean.
- [x] End-to-end verified via `mix run`: list-of-maps → jsonb `$1` → parsed structs;
      `request_index` gaps flag unresolved triples.
- [ ] (Task 8) Add a `tests/test_lookups`-style SQL test for the new function.

### 2. Rasterizer module — `lib/pure_admin_icons/rasterizer.ex`  ✅
- [x] `render_png(svg_path, size)` shells out to `resvg` via `System.cmd/3`
      (`stderr_to_stdout: true`), SVG read from disk, PNG to temp file, `File.rm`
      in `after`.
- [x] **Arg sanitization:** size guarded by `when … size in @allowed_sizes`; options
      first, then `--`, then positional paths. `System.cmd` = no shell.
- [x] `@resvg System.get_env("RESVG_BIN") || "resvg"`; `allowed_sizes/0` public.
- [x] Fallback clause + `rescue ErlangError` → `{:error, :resvg_unavailable}` when the
      binary is missing (verified: :enoent handled gracefully, not a crash).
- [x] Verified via `mix run`: off-allowlist size & non-integer size → `:invalid_size`
      without invoking resvg; missing binary → `:resvg_unavailable`.

### 3. API endpoint — `lib/pure_admin_icons_web/controllers/api/png_zip_controller.ex`  ✅
- [x] `create/2` accepting `{"icons": [{set,name,style}], "sizes": [ints]}`.
- [x] Guardrail 1 — render-units cap (`@max_units 200`) → 422.
- [x] Guardrail 2 — per-IP rate limit (`@rate_limit 10` / min) → 429 + `retry-after`.
- [x] Validate sizes against `Rasterizer.allowed_sizes/0`; validate icon triples.
- [x] Resolve all triples in one `DbContext.get_icon_details_by_keys/1` call.
- [x] Path via `Icon.local_svg_path/2` (largest source) + `within_icons_dir?/1`
      containment check.
- [x] Rasterize each (icon × size), `:zip.create(…, [:memory])` with `manifest.json`;
      `application/zip` + `content-disposition`. Empty result → 422 `nothing_rendered`.
- [x] Manifest reports `skipped` (unresolved triples via `request_index` gaps) +
      `render_failures`.
- [x] **Tracking: one row per rendered PNG** (per icon × size) — `format: "png-zip"`,
      `source: "api"`, `surface: "direct"`, real `size`. (Decision: per icon+size.)
- [x] Full data path verified via `mix run` (resolve → `local_svg_path` → render → zip
      → extract): 4 triples (1 bogus) → 3 resolved + skipped, 3×2 = 6 real PNGs, valid
      7-entry zip that round-trips. Rendering used a dev ImageMagick shim (see below);
      real `resvg` runs in Docker/prod.
- [x] `resvg_bin/0` resolved at runtime: `RESVG_BIN` env → `:resvg_bin` app config →
      `resvg`. (Was a compile-time `@resvg` attr — would have ignored release env.)
- [ ] Live HTTP happy path through the router + `track_action` writes — deferred to
      avoid writing test metric rows to db-01; sub-parts all verified.

> **Dev rendering on Windows:** no resvg CLI / Docker / cargo available. Compiled a
> tiny C# shim (`tmp/resvg.exe`, gitignored) that maps resvg args → ImageMagick, and
> point at it via `config :pure_admin_icons, :resvg_bin, "…/tmp/resvg.exe"` or
> `RESVG_BIN`. Source: `tmp/resvg_shim.cs`. Production uses the apt `resvg`.

### 4. SVG-only zip variant  ✅
- [x] Merged PNG + SVG into one `IconExportController` (`png_zip/2`, `svg_zip/2`)
      sharing guardrails/resolve/manifest/tracking. SVG action reads source SVGs from
      disk (no resvg), caps on icon count (`@max_icons 500`). Old `PngZipController`
      removed. Zip entries namespaced `set/style/name[-size]` (no style collisions).
- [x] SVG tracking: one row per icon, `format: "svg-zip"`, `size: nil`.
- [x] Verified over HTTP: `POST /api/icons/svg-zip` → valid zip
      (`lucide/outline/house.svg`, `tabler/outline/home.svg` + manifest).

### 5. Routing — `router.ex`  ✅
- [x] `post "/icons/png-zip", IconExportController, :png_zip`.
- [x] `post "/icons/svg-zip", IconExportController, :svg_zip`.

### 6b. Metrics undercounting fixes  *(surfaced during design — the "low download stats" cause)*  ✅
Two existing gaps found while deciding how the batch endpoint should track:
- [x] **Multi-size single downloads collapsed to one nil-size row.** The designer
      sent `size="32,64,128"`; the server's `Integer.parse` failed the `""`-remainder
      check → `size: nil`. Counted, but the size dimension was lost. Fixed in
      `icon_search_live.ex` `handle_event("track_download")`: `download_sizes/1` now
      splits comma-joined sizes → **one metric row per size** (decision: per icon+size).
- [x] **Basket bulk exports were completely untracked** — `BasketActions` →
      `downloadSvgZip`/`downloadPngZipBatch` pushed no events (fetched from the passive
      `/icons/*` serve). Fixed: `trackExport/2` in `app.js` pushes a single
      `track_download_batch` (icon-ids + sizes) after export; new
      `handle_event("track_download_batch")` records **one row per icon** (SVG) /
      **per icon × size** (PNG), `surface: "basket"`, `format: "svg-zip"`/`"png-zip"`.
- [x] Compiles clean (no new warnings); `mix esbuild` builds `app.js`.
- [ ] Verify live: trigger a basket PNG/SVG export, confirm N rows land in
      `icon_metric` with correct `surface`/`format`/`size`.

### 6. Throttling gap on existing single downloads  *(surfaced during design)*  ✅
- [x] Added per-IP `RateLimiter.hit("download:#{ip}", …)` to `DownloadController.show/2`
      — 300/min/IP, 429 + `retry-after` on deny.
- [x] Left the passive `/icons/*` img serve **unthrottled** on purpose (one page loads
      dozens of icons via `<img>`; throttling it would break browsing).

### 6c. Metrics survive icon deletion  *(surfaced while reviewing tracking)*  ✅
`icon_metric` + `icon_metric_cube` referenced `icon(icon_id) ON DELETE CASCADE`, so
deleting/re-syncing an icon wiped its historical stats.
- [x] DB migration `070_update_main_v1-20.sql` (v1.20, applied to the app DB):
      denormalize identity (`icon_set_code`, `style_code`, `original_name`) into both
      tables, backfill, `NOT NULL`; soften FK to `ON DELETE SET NULL` (`icon_id` now a
      nullable pointer); re-key the cube on **identity** (survives delete AND
      re-creation, relinks via `max(icon_id)`).
- [x] `track_icon_action` snapshots identity at insert; `refresh_icon_metrics_cube`
      groups by identity; `get_popular_icons` reads name from the cube (deleted icons
      still appear). Output shapes unchanged → **no Elixir changes**, db-gen no-op.
- [x] Verified on app DB: FK = `SET NULL`, identity cols populated, 0 orphans, cube
      rebuilt; `get_popular_icons` returns names from the cube.
- Note: env gotcha — apply/verify with debee **no `-e`** (default env = the app DB);
  `-e db-01` is a different stale DB. See memory `project-debee-env-topology`.

### 7. Docker  ✅
- [x] Added `resvg` to the runtime-stage `apt-get install` line (Debian trixie has it).
- [ ] Smoke-test a render inside the built image (needs a Docker host — none locally).

### 8. Tests  ✅ (11 passing)
- [x] `rasterizer_test.exs` — off-allowlist / non-integer / flag-looking / zero-neg
      sizes rejected before resvg; `allowed_sizes/0` sane.
- [x] `icon_export_controller_test.exs` — png 400 (missing), 422 (bad size), 422 (units
      cap, `requested_units`), 422 (malformed triple); svg 400, 422 (icon cap); 429 rate
      limit. All pre-DB paths, so they run without an Ecto sandbox.
- [ ] DB-function SQL test in the DB repo (`tests/test_lookups`) — still open.
- [x] Live happy path verified via HTTP (curl) against db-01 + shim: png-zip &
      svg-zip return valid zips; manifest reports `skipped`; metric rows land
      (png-zip per icon×size, svg-zip per icon).

### 9. Follow-up (separate) — MCP tool  *(not in this repo)*
- [ ] In `@keenmate/pure-admin-icons-mcp` (separate npm repo), add a tool that calls
      `POST /api/icons/png-zip` / `svg-zip`. Return base64 or a short-lived URL (MCP
      can't stream raw zip bytes).
- [ ] Update `/docs/mcp` (`McpDocsLive`) tool list + `/docs/api` (`ApiDocsLive`).

## Key files (reference)
- Path helpers: `lib/pure_admin_icons/icons/icon.ex` (`local_svg_path/2`, `svg_filename/2`)
- Rate-limit pattern: `lib/pure_admin_icons_web/controllers/api/maintenance_controller.ex`
- Tracked download pattern: `lib/pure_admin_icons_web/controllers/api/download_controller.ex`
- ZIP precedent: `lib/pure_admin_icons/sync/svg_downloader.ex`
- DB wrapper pattern: `lib/database/db_context.ex` (`get_icon_detail/1`, `get_icon_by_filename/4`)
- Client-side precedent (for parity): `assets/js/app.js` (`downloadSvgZip`, `downloadPngZipBatch`)
