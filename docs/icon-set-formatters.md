# Icon Set Formatter Modules

All icon-set-specific identifier generation and package metadata lives in dedicated modules under `lib/pure_admin_icons/icon_sets/`. Each module implements the `PureAdminIcons.IconSets.Formatter` behaviour.

## Structure

```
lib/pure_admin_icons/icon_sets/
├── formatter.ex      # Behaviour + dispatcher (registry)
├── generic.ex        # Fallback for unknown icon sets
├── fluentui.ex       # Microsoft FluentUI System Icons
├── fontawesome.ex    # Font Awesome Free
├── heroicons.ex      # Tailwind Heroicons
├── lucide.ex         # Lucide Icons
├── material.ex       # Material Symbols
├── tabler.ex         # Tabler Icons
├── bootstrap.ex      # Bootstrap Icons
├── simpleicons.ex    # Simple Icons (brand logos)
└── carbon.ex         # Carbon Icons (IBM)
```

Sets without a module here (e.g. Phosphor, Remix) fall back to `Generic`.
A formatter only needs to implement the frameworks a set actually ships a package
for — return `{nil, nil}` from the `*_package` callback for the rest and that
framework's section is simply hidden in the modal.

## Behaviour

```elixir
@callback react_identifier(icon, size :: integer()) :: String.t() | nil
@callback vue_identifier(icon, size :: integer()) :: String.t() | nil
@callback svelte_identifier(icon, size :: integer()) :: String.t() | nil
@callback cssclass_identifier(icon, size :: integer()) :: String.t() | nil

@callback react_package(icon) :: package
@callback vue_package(icon) :: package
@callback svelte_package(icon) :: package
@callback cssclass_package(icon) :: package

@callback react_identifier_sizes(icon) :: [integer()]
@callback vue_identifier_sizes(icon) :: [integer()]
@callback svelte_identifier_sizes(icon) :: [integer()]
```

Where `package` is `{name :: String.t() | nil, npm_url :: String.t() | nil}`.

The `*_identifier_sizes` callbacks return which sizes the modal's per-size loop should iterate. Most icon sets return a single size (the identifier doesn't change with size), but Heroicons React/Vue and FluentUI return all sizes since their import paths or identifiers vary by size.

## Dispatcher

`PureAdminIcons.IconSets.Formatter` provides:

- `for_icon(icon)` / `for_set(code)` — returns the formatter module for a given icon or icon set code
- Top-level helper functions for each callback that route to the right module — e.g., `Formatter.react_identifier(icon, size)` calls `for_icon(icon).react_identifier(icon, size)`

The LiveView calls only the dispatcher, never individual modules.

## Registry

```elixir
@formatters %{
  "fluentui" => PureAdminIcons.IconSets.Fluentui,
  "fontawesome" => PureAdminIcons.IconSets.Fontawesome,
  "heroicons" => PureAdminIcons.IconSets.Heroicons,
  "lucide" => PureAdminIcons.IconSets.Lucide,
  "material" => PureAdminIcons.IconSets.Material,
  "tabler" => PureAdminIcons.IconSets.Tabler,
  "bootstrap" => PureAdminIcons.IconSets.Bootstrap,
  "simpleicons" => PureAdminIcons.IconSets.Simpleicons,
  "carbon" => PureAdminIcons.IconSets.Carbon
}
```

Unknown icon set codes fall back to `PureAdminIcons.IconSets.Generic`, which returns minimal placeholder values so the UI degrades gracefully instead of crashing.

## Adding a new icon set

1. **Create the module** at `lib/pure_admin_icons/icon_sets/{name}.ex`:
   ```elixir
   defmodule PureAdminIcons.IconSets.MySet do
     @behaviour PureAdminIcons.IconSets.Formatter

     @impl true
     def react_identifier(icon, _size) do
       name = icon.name |> String.replace(" ", "")
       "import { #{name} } from 'my-icons-react'\n<#{name} />"
     end
     # ... implement all required callbacks
   end
   ```

2. **Register it** in `formatter.ex`:
   ```elixir
   @formatters %{
     # ...
     "myset" => PureAdminIcons.IconSets.MySet
   }
   ```

3. **No changes needed** in the LiveView, JS, or templates. The dispatcher handles routing.

## What's NOT in formatter modules

- **Sync logic** (download, parse, SVG file movement) — that's in `lib/pure_admin_icons/sync/adapters/`. The two systems are intentionally separate so they can evolve independently.
- **Color method** (`fill`/`stroke`/`multicolor`) — that's a DB-stored property per (icon set + style), accessed via `icon.style_color_method`.
- **Icon set badge colors** — still in `icon_search_live.ex` as `icon_set_color/1` since they're UI-specific.

## Testing a new module

The fastest way to verify a new formatter module is to check the icon detail modal in the browser. Open any icon from your set and confirm:

- React/Vue/Svelte sections show the correct package and component code
- CSS Class section appears (or doesn't, based on whether you implemented it)
- Hover-to-copy buttons in grid/list view also work
