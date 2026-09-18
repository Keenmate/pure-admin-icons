# Adding a New Icon Set

End-to-end checklist for adding a new icon set to the catalog. Adding a set touches
**four** systems (sync adapter, app enum, DB registration, formatter) plus a final
sync run. Only the formatter step was previously documented (see
[icon-set-formatters.md](icon-set-formatters.md)); this covers the whole flow.

> The systems are intentionally decoupled — the sync pipeline, the DB `const.icon_set`
> row, and the formatter modules evolve independently. A set will render (degraded)
> even if you skip the formatter, because unknown codes fall back to `Generic`.

## Overview

| # | Step | Location | Required? |
|---|------|----------|-----------|
| 1 | Sync adapter | `lib/pure_admin_icons/sync/adapters/{name}.ex` + register in `adapter.ex` | Yes |
| 2 | App enum | `lib/pure_admin_icons/icons/icon.ex` → `@icon_sets` | Yes |
| 3 | DB registration | new migration in `../pure-admin-icons-database/` → `const.icon_set` | Yes |
| 4 | Formatter module | `lib/pure_admin_icons/icon_sets/{name}.ex` + register in `formatter.ex` | Optional (falls back to `Generic`) |
| 5 | Run the sync | `Worker.sync_icon_set/2` | Yes |

Keep the icon-set **code** (e.g. `"bootstrap"`) identical across all five places.

---

## 1. Sync adapter

Create `lib/pure_admin_icons/sync/adapters/{name}.ex` implementing the
`PureAdminIcons.Sync.Adapter` behaviour. Use an existing adapter as a template:

- **Multi-size set** (per-size SVG files, e.g. 16/20/24) → copy `heroicons.ex`.
- **Scalable single-source set** (one SVG per icon, renders at any size — Bootstrap,
  Simple Icons, Carbon all fit here) → copy `remix.ex`.

### Callbacks

Metadata: `icon_set_id/0`, `name/0`, `license/0`, `homepage_url/0`, `github_url/0`,
`styles/0`, `sizes/0`, `default_size/0`.

Pipeline: `download/0`, `parse/1`, `move_svgs/2`, `cleanup/1`.

### `download/0`

Fetch the GitHub ZIP with `Req` (never HTTPoison/Tesla/httpc) streaming to a temp file,
extract, and cache. Reuse the caching boilerplate verbatim from `heroicons.ex`:
`Adapter.get_cached_path/1` → `Adapter.save_to_cache/2`. In dev, `:use_icon_cache`
avoids re-downloading on every run.

### `parse/1` → icon maps

Return `{:ok, %{icons: [icon_map], synonyms: %{}, discrepancies: []}}`.

Each `icon_map`:

```elixir
%{
  icon_set: icon_set_id(),
  name: "Arrow Left",          # display name, via Naming.title_case/1
  name_lower: "arrow-left",    # the raw file base name (DB derives normalized identity)
  style: "outline",            # must be one of styles/0
  # --- scalable single-source (Bootstrap/Simple Icons/Carbon) ---
  is_scalable: true,
  sizes: [],
  filenames: %{"0" => "arrow-left.svg"},         # key "0" == scalable
  ios_identifiers: %{"0" => Naming.camel_case(name)},
  android_identifiers: %{"0" => "ic_myset_arrow_left"},
  # --- OR multi-size (Heroicons-style), instead of the three lines above ---
  # sizes: [16, 20, 24],
  # filenames: %{"24" => "arrow-left-24.svg", ...},   # keys are pixel sizes
  # ios_identifiers: %{"24" => "arrowLeft24", ...},
  # android_identifiers: %{"24" => "ic_myset_arrow_left_24_outline", ...},
  categories: ["arrows"],      # optional; [] if the source has none
  svg_hash: "<sha256 hex>"     # hash of the SVG content(s); drives change detection
}
```

- **`filenames` key `"0"`** marks a scalable icon (single source, any size). Pixel-size
  keys (`"24"`) are for sets that ship distinct files per size. This is what
  `public.get_icon_by_filename` and the download controller key off of.
- **`svg_hash`** is a sha256 of the raw SVG bytes (concatenated across sizes for
  multi-size). Import uses it to detect content changes across syncs.
- **Synonyms**: if the source ships tags/keywords (Remix has `tags.json`), collect them
  into `synonyms: %{display_name => [tag, ...]}`. Otherwise `%{}`.
- **Identity must be unique** — see the callout below.

> **⚠️ Identity uniqueness.** The DB enforces `uq_icon_identity` on
> `(icon_set_code, helpers.normalize_name(original_name), style_code)`, where
> `original_name` is the icon map's `name` and `normalize_name` = `lower(regexp_replace(name, '[-_\s]+', ''))`.
> So within one set+style, two icons whose **display names normalize to the same key**
> collide and the stage `COPY` crashes with a `23505 unique_violation`. This bites any
> source with non-unique display names:
> - **Simple Icons** has several distinct brands sharing a title (two "Spring", two
>   "Hive"). Its adapter disambiguates by falling back to the unique slug-derived name
>   (`"Backstage"` → `"Backstage Casting"`) — see `disambiguate_identity/1` in
>   `simpleicons.ex`.
> - If you don't need to keep both, just `Enum.uniq_by/2` on the normalized identity to
>   drop duplicates (Remix does this in `remix.ex`).
>
> Either way, a final `uniq_by(normalize_name(name))` is cheap insurance against a crash.

### `move_svgs/2`

Copy SVGs into `{output_dir}/{icon_set}/{style}/{filename}.svg`, where `filename`
matches the values in the `filenames` map from `parse/1`. Wipe the style dir first
(`File.rm_rf` → `File.mkdir_p!`) so removed icons don't linger.

> **⚠️ SVG theming (root `fill`).** The UI recolors icons via CSS `color` /
> `currentColor`. If a source's SVGs have **no `fill` on the root `<svg>`** (paths then
> default to black), they render invisibly on dark themes. Inject
> `fill="currentColor"` into the root tag on write instead of a plain `File.copy` — see
> `write_themed_svg/2` + `inject_current_color/1` in `material.ex`, `carbon.ex`, or
> `simpleicons.ex`. Sets that already ship `fill="currentColor"` (e.g. Bootstrap) need
> nothing — the injection is a no-op guarded by a regex check. Note the `style_color_method`
> in `const.icon_set` describes *how* to recolor (`fill`/`stroke`/`multicolor`); it does
> **not** rewrite the SVG — that's this step's job.

### `cleanup/1`

Copy verbatim from `heroicons.ex`: skip deletion when the path is a cached extraction
(`Adapter.is_cached_path?/1`), otherwise `File.rm_rf`.

### Register the adapter

Add to the `@adapters` map in `lib/pure_admin_icons/sync/adapter.ex`:

```elixir
@adapters %{
  # ...
  "myset" => PureAdminIcons.Sync.Adapters.MySet
}
```

## 2. App enum

Add the code to `@icon_sets` in `lib/pure_admin_icons/icons/icon.ex`. The adapter's
`icon_set_id/0` must be a member of this list.

## 3. DB registration

The `const.icon_set` row drives the badge color, the styles list, and the per-style
color method — **no app code** handles those; they're data. Add a new numbered migration
in `../pure-admin-icons-database/` (next number after the highest existing file — e.g.
`065_*.sql`) with:

```sql
insert into const.icon_set (code, title, license, homepage_url, github_url,
                            styles, sizes, default_size, has_single_source, is_scalable,
                            style_color_methods, native_style_names, brand_color)
values ('myset', 'My Set', 'MIT',
        'https://myset.com/',
        'https://github.com/org/myset',
        '{outline,filled}', '{}', 24, true, true,
        '{"outline":"stroke","filled":"fill"}',   -- per-style: stroke | fill | multicolor
        '{}',                                      -- native_style_names: our code -> source's name, if different
        '#8B5CF6');                                -- brand_color: the UI badge color
```

Apply it with Debee (from the database repo):

```bash
python debee.py -o updateDatabase -s 65 -n 65
```

See the database repo's `CLAUDE.md` for Debee operations. Existing set inserts live in
`058_update_main_v1-8.sql` (Phosphor/Remix/Material) — good reference for the columns.

## 4. Formatter module (optional)

Framework identifier/package generation. Documented fully in
[icon-set-formatters.md](icon-set-formatters.md): create
`lib/pure_admin_icons/icon_sets/{name}.ex` implementing the `Formatter` behaviour and
register it in `formatter.ex`. Skip it and the set falls back to `Generic` (minimal
placeholders, no crash) — worth adding once the icons import cleanly.

## 5. Run the sync

Import the icons (download → parse → stage → DB import → SVG storage):

```elixir
# iex -S mix phx.server
PureAdminIcons.Sync.Worker.sync_icon_set("myset")
```

Then verify in the browser: search for a known icon, open its detail modal, and confirm
the styles, sizes, badge color, and (if you did step 4) the framework snippets render.

## Quick verification checklist

- [ ] `PureAdminIcons.Sync.Adapter.available_icon_sets()` includes the new code
- [ ] `const.icon_set` has the row (badge color + styles show in the UI)
- [ ] `Worker.sync_icon_set/2` imports without discrepancies
- [ ] Icon detail modal shows correct package/snippets (or graceful `Generic` fallback)
- [ ] SVG serves at `/icons/{icon_set}/{style}/{filename}`
