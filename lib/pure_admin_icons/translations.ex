defmodule PureAdminIcons.Translations do
  @moduledoc """
  Translation system for PureAdminIcons UI strings.

  Ships with English defaults that work out of the box. Applications can
  override translations at runtime by providing a callback function via config:

      # config/config.exs
      config :pure_admin_icons,
        translate: &PureAdminIcons.Translations.DbProvider.translate/2

  The callback receives a translation key and a params map:

      defmodule PureAdminIcons.Translations.DbProvider do
        def translate(key, params) do
          # Load from DB, Gettext, ETS, etc.
          translation = PureAdminIcons.Translations.Loader.lookup(key, current_locale())
          # Use the interpolation helper to replace %{param} placeholders
          PureAdminIcons.Translations.interpolate(translation, params)
        end
      end

  If the callback returns `nil` or `""`, the English default is used as fallback.

  ## Translation Keys

  Keys follow a flat three-segment convention:

      [domain].[specifier].[identifier]

  - `domain` — the page or feature, or `common` for shared strings.
    Examples: `iconSearch`, `iconSets`, `iconDetail`, `apiDocs`, `common`
  - `specifier` — the kind of string. One of
    `labels`, `headers`, `tableHeaders`, `placeholders`, `buttons`,
    `tooltips`, `messages`, `empty`.
  - `identifier` — the specific thing being named, in camelCase.
    Examples: `iconSet`, `iconName`, `sizes`, `search`, `noResults`.

  ### Examples

      iconSearch.placeholders.search
      iconSearch.labels.iconSet
      iconSearch.tableHeaders.iconName
      iconSets.headers.styles
      iconSets.empty.notes
      iconDetail.buttons.copy
      common.labels.loading

  ## Interpolation

  Use `%{param}` placeholders in translation strings:

      t("iconSearch.messages.results", %{count: 30, total: 392})
      # => "Showing 30 of 392 icons"
  """

  @defaults %{
    # ─────────────────────────── Common ───────────────────────────
    "common.labels.by" => "by",
    "common.labels.scalable" => "∞ Scalable",
    "common.buttons.previous" => "Previous",
    "common.buttons.next" => "Next",
    "common.buttons.cancel" => "Cancel",
    "common.buttons.close" => "Close",
    "common.buttons.delete" => "Delete",
    "common.buttons.copy" => "Copy",
    "common.buttons.homepage" => "Homepage",
    "common.buttons.github" => "GitHub",
    "common.tableHeaders.icon" => "Icon",
    "common.tableHeaders.set" => "Set",
    "common.tableHeaders.style" => "Style",
    "common.pagination.pageOf" => "Page %{page} of %{total}",
    "common.time.justNow" => "just now",
    "common.time.minutesAgo" => "%{count} minutes ago",
    "common.time.hoursAgo" => "%{count} hours ago",
    "common.time.daysAgo" => "%{count} days ago",

    # ─────────────────────────── Navigation ───────────────────────
    "nav.buttons.docs" => "Docs",
    "nav.buttons.iconSets" => "Icon Sets",
    "nav.buttons.api" => "API",
    "nav.buttons.stats" => "Stats",
    "nav.buttons.themes" => "Themes",
    "nav.buttons.keenmate" => "Keenmate",
    "nav.tooltips.language" => "Change language",

    # ─────────────────────────── Docs index — /docs ───────────────
    "docsIndex.headers.pageTitle" => "Documentation",
    "docsIndex.messages.intro" =>
      "Guides for searching icons, using the API, and integrating with AI tools.",
    "docsIndex.cards.apiTitle" => "API Reference",
    "docsIndex.cards.apiDescription" =>
      "REST endpoints for searching icons. Response formats, filtering, pagination, and usage examples.",
    "docsIndex.cards.iconSetsTitle" => "Icon Sets",
    "docsIndex.cards.iconSetsDescription" =>
      "Every aggregated icon set: styles, sizes, counts, license, source links, and integration notes.",
    "docsIndex.cards.mcpTitle" => "MCP Server",
    "docsIndex.cards.mcpDescription" =>
      "Use the MCP server to search icons directly from Claude Desktop or Claude Code. Install, configure, and use.",
    "docsIndex.cards.llmsTitle" => "LLM Integration",
    "docsIndex.cards.llmsDescription" =>
      "Token-efficient text format, llms.txt, ai-plugin.json. Best practices for AI-powered icon search.",

    # ─────────────────────────── Icon Sets — /docs/icon-sets ──────
    "iconSets.headers.pageTitle" => "Icon Sets",
    "iconSets.headers.styles" => "Styles",
    "iconSets.headers.notes" => "Notes",
    "iconSets.labels.iconsSuffix" => "icons",
    "iconSets.labels.license" => "License",
    "iconSets.labels.defaultSize" => "Default size",
    "iconSets.labels.sizes" => "Sizes",
    "iconSets.labels.vectorRaster" => "Vector / raster",
    "iconSets.labels.lastSynced" => "Last synced",
    "iconSets.labels.normalizedSvg" => "Normalized SVG",
    "iconSets.buttons.browseIcons" => "Browse icons",
    "iconSets.messages.summary" => "%{count} icon sets aggregated from open-source libraries.",
    "iconSets.messages.helpText" =>
      "Click a card's links to visit the upstream homepage or GitHub repo. \"Native names\" shown on style chips indicate how that style is called in the source library.",
    "iconSets.messages.vector" => "Vector (SVG)",
    "iconSets.messages.raster" => "Raster",
    "iconSets.tooltips.nativeName" => "Native: %{native}",
    "iconSets.tooltips.colorMethod" => "Color method: %{method}",
    "iconSets.tooltips.normalizedSvg" =>
      "The served SVGs are normalized for theming — hardcoded colors are rewritten to currentColor, so they are not byte-identical to the upstream files. Grab originals from the source repo.",

    # ─────────────────────────── Icon search — / ──────────────────
    "iconSearch.headers.heroTitlePrefix" => "Search",
    "iconSearch.headers.heroTitleMiddle" => "icons from",
    "iconSearch.headers.heroTitleSuffix" => "icon sets",
    "iconSearch.headers.sets" => "Sets",
    "iconSearch.headers.styles" => "Styles",
    "iconSearch.headers.sizes" => "Sizes",
    "iconSearch.headers.resources" => "Resources",
    "iconSearch.headers.iconSets" => "Icon Sets",
    "iconSearch.placeholders.search" => "Search icons (e.g., 'pen', 'calendar', 'add')...",
    "iconSearch.labels.activeFilters" => "Active filters:",
    "iconSearch.buttons.filters" => "Filters",
    "iconSearch.buttons.grid" => "Grid",
    "iconSearch.buttons.list" => "List",
    "iconSearch.buttons.clearAll" => "Clear all",
    "iconSearch.buttons.downloadSvgZip" => "Download SVGs (.zip)",
    "iconSearch.buttons.downloadPngZip" => "Download PNGs (.zip)",
    "iconSearch.buttons.copyAllIds" => "Copy all identifiers",
    "iconSearch.buttons.clearBasket" => "Clear",
    "iconSearch.buttons.designer" => "Designer settings",
    "iconSearch.messages.designerHint" =>
      "These settings apply to all basket downloads (SVG & PNG).",
    "iconSearch.headers.basket" => "Basket",
    "iconSearch.messages.basketCount" => "%{count} icons",
    "iconSearch.empty.basket" => "Your basket is empty",
    "iconSearch.empty.basketHint" =>
      "Add icons with the + button to download or compare them together.",
    "iconSearch.tooltips.openBasket" => "Open basket",
    "iconSearch.tooltips.addToBasket" => "Add to basket",
    "iconSearch.tooltips.removeFromBasket" => "Remove from basket",
    "iconSearch.links.apiDocs" => "API Documentation",
    "iconSearch.links.mcpServer" => "MCP Server",
    "iconSearch.links.llmIntegration" => "LLM Integration",
    "iconSearch.links.healthCheck" => "Health Check",
    "iconSearch.messages.mcpPromptPrefix" => "Using Claude? Try our",
    "iconSearch.messages.mcpPromptLink" => "MCP server",
    "iconSearch.messages.mcpPromptSuffix" =>
      "to search icons directly from Claude Desktop or Claude Code.",
    "iconSearch.messages.resultsRange" => "Showing %{from}-%{to} of %{total} icons",
    "iconSearch.messages.footerTagline" =>
      "Search %{count} open-source SVG icons from %{sets} icon sets.",
    "iconSearch.messages.madeByPrefix" => "Made by",
    "iconSearch.messages.licenseNotice" => "Icon SVGs retain their original licenses.",
    "iconSearch.messages.lastSynced" => "Last synced: %{when}",
    "iconSearch.messages.discrepancies" => "(%{count} discrepancies)",
    "iconSearch.empty.noResults" => "No icons found for \"%{query}\"",
    "iconSearch.empty.noResultsHint" => "Try a different search term or adjust your filters",
    "iconSearch.tableHeaders.name" => "Name",
    "iconSearch.tooltips.iconSetCount" => "%{count} icons",
    "iconSearch.tooltips.scalable" => "Icons that scale to any size",
    "iconSearch.tooltips.scalableRenders" => "Scalable — renders at any size",
    "iconSearch.tooltips.downloadPngZip" => "Download PNG ZIP with designer settings",
    "iconSearch.tooltips.copyPlatformIdentifier" => "Copy %{platform} identifier",
    "iconSearch.tooltips.copyPlatformIdentifierSized" =>
      "Copy %{platform} identifier for size %{size}",
    "iconSearch.tooltips.exactMatch" => "Exact name match",
    "iconSearch.tooltips.exactMatchSynonym" => "Exact match via synonym",

    # ─────────────────────────── Icon detail modal ────────────────
    "iconDetail.headers.preview" => "Preview",
    "iconDetail.headers.availableSizes" => "Available Sizes",
    "iconDetail.headers.downloadDesigner" => "Download Designer",
    "iconDetail.headers.platformIdentifiers" => "Platform Identifiers",
    "iconDetail.headers.filenameLocalCopy" => "Filename (local copy)",
    "iconDetail.labels.copies" => "copies",
    "iconDetail.labels.downloads" => "downloads",
    "iconDetail.labels.total" => "total",
    "iconDetail.labels.preview" => "Preview:",
    "iconDetail.labels.colors" => "Colors:",
    "iconDetail.labels.pasteCss" => "Paste CSS from another project:",
    "iconDetail.labels.iconColor" => "Icon",
    "iconDetail.labels.bgColor" => "Bg",
    "iconDetail.labels.filename" => "Filename:",
    "iconDetail.labels.filenameOriginal" => "Original",
    "iconDetail.labels.sizes" => "Sizes:",
    "iconDetail.labels.includeColors" => "Include colors",
    "iconDetail.labels.padding" => "Padding",
    "iconDetail.labels.corners" => "Corners",
    "iconDetail.labels.placeholders" => "Placeholders:",
    "iconDetail.placeholders.presetName" => "Name your preset...",
    "iconDetail.placeholders.customSize" => "Custom size",
    "iconDetail.buttons.new" => "New",
    "iconDetail.buttons.copyCss" => "Copy CSS",
    "iconDetail.buttons.importCss" => "Import CSS",
    "iconDetail.buttons.importAsPreset" => "Import as preset",
    "iconDetail.buttons.saveAsPreset" => "Save as preset",
    "iconDetail.buttons.downloadPngZip" => "Download PNG ZIP",
    "iconDetail.buttons.downloadSvg" => "Download SVG",
    "iconDetail.buttons.importSettings" => "Import Settings",
    "iconDetail.messages.multicolorNotRecolorable" => "Multicolor icon — not recolorable",
    "iconDetail.messages.previewScalableSuffix" => "— Scalable, renders at any size",
    "iconDetail.tooltips.newPreset" => "Create a new custom color preset",
    "iconDetail.tooltips.copyCss" => "Copy CSS to use these colors in your project",
    "iconDetail.tooltips.importCss" => "Import a preset from CSS pasted from another project",
    "iconDetail.tooltips.transparentBg" => "Transparent (checker)",
    "iconDetail.tooltips.includeColors" =>
      "Apply current preview colors (icon color + background)",
    "iconDetail.tooltips.downloadSvg" => "Download SVG",
    "iconDetail.tooltips.importSettings" =>
      "Import settings from a manifest.json (from a previous Download Designer ZIP)",
    "iconDetail.platforms.filename" => "Filename",
    "iconDetail.platforms.cssClass" => "CSS Class",
    "iconDetail.platforms.htmlTag" => "HTML Tag",

    # ─────────────────────────── API docs — /docs/api ─────────────
    "apiDocs.headers.pageTitle" => "API",
    "apiDocs.headers.icons" => "Icons",
    "apiDocs.headers.iconSets" => "Icon Sets",
    "apiDocs.headers.responseFormats" => "Response Formats",
    "apiDocs.headers.responseFields" => "Response Fields",
    "apiDocs.headers.otherEndpoints" => "Other Endpoints",
    "apiDocs.headers.aiIntegration" => "AI / LLM Integration",
    "apiDocs.headers.usageExamples" => "Usage Examples",
    "apiDocs.headers.mcpServer" => "MCP Server (Claude Desktop / Claude Code)",
    "apiDocs.headers.llmEndpoint" => "LLM-friendly endpoint",
    "apiDocs.headers.machineDocs" => "Machine-readable docs",
    "apiDocs.messages.intro" =>
      "Search icons programmatically. All endpoints return JSON. No authentication required.",
    "apiDocs.messages.formatsIntro" =>
      "The format parameter on /api/icons/search controls the response shape:",
    "apiDocs.messages.aiIntro" =>
      "For AI assistants and LLMs, use the text format for maximum token efficiency. We also provide an MCP server for direct integration with Claude Desktop and Claude Code.",
    "apiDocs.descriptions.search" =>
      "Search icons by name across all icon sets. Supports full-text search, trigram similarity, and synonym matching.",
    "apiDocs.descriptions.iconDetail" =>
      "Get a single icon by ID. Returns full metadata including filenames, platform identifiers, categories, phrases, and SVG URLs for all sizes.",
    "apiDocs.descriptions.iconSets" =>
      "List all available icon sets with metadata: styles, sizes, license, color methods, icon count, plus each set's description and notes (e.g. whether its served SVGs are normalized from upstream).",
    "apiDocs.descriptions.health" => "Health check. Returns icon count and status.",
    "apiDocs.descriptions.serve" => "Serve an icon SVG file. Cached for 1 year with immutable header.",
    "apiDocs.descriptions.maintenance" =>
      "Trigger a maintenance task. Requires X-API-Key header. Rate limited to 5 requests per 5 minutes.",
    "apiDocs.notes.maintenance" =>
      "Use POST /api/maintenance/sync/:icon_set to sync a specific set (e.g., fontawesome, fluentui).",
    "apiDocs.params.q" => "Search query (required)",
    "apiDocs.params.set" =>
      "Filter by icon set code, e.g. fluentui, material, phosphor, tabler, lucide, solar (repeatable) — see /api/icon-sets for all codes",
    "apiDocs.params.size" => "Filter by size, e.g. 16, 20, 24, 28, 32, 48 (most sets are scalable)",
    "apiDocs.params.style" =>
      "Filter by style: outline, filled, thin, light, regular, bold, rounded, sharp, duotone, line-duotone, broken, color, brands (varies by set)",
    "apiDocs.params.limit" => "Max results (default: 50, max: 100)",
    "apiDocs.params.format" => "Response format: json (default), compact, text",
    "apiDocs.params.maintenanceTask" => "Task to run: sync, clean, cube",
    "apiDocs.params.maintenanceKey" => "API key (header, required)",
    "apiDocs.formats.json" =>
      "Full response: id, icon_set, name, style, style_color_method, sizes, ios/android identifiers, svg_url",
    "apiDocs.formats.compact" => "Minimal JSON: icon_set, name, style, url",
    "apiDocs.formats.text" => "Plain text, one icon per line (most token-efficient for AI)",
    "apiDocs.fields.intro" => "Key fields in the JSON response:",
    "apiDocs.fields.styleColorMethod" =>
      "How to set icon color via CSS: \"fill\", \"stroke\", or \"multicolor\" (not recolorable)",
    "apiDocs.fields.svgUrl" =>
      "Relative URL to the SVG file (e.g., /icons/fluentui/regular/ic_fluent_calendar_24_regular.svg)",
    "apiDocs.fields.ios" => "iOS/Swift identifier per size (e.g., {\"24\": \"calendar24Solid\"})",
    "apiDocs.fields.android" =>
      "Android/Kotlin identifier per size (e.g., {\"24\": \"ic_heroicons_calendar_24_solid\"})",
    "apiDocs.examples.search" => "Search icons",
    "apiDocs.examples.multiSet" => "Filter by multiple icon sets",
    "apiDocs.examples.iconDetail" => "Get icon detail",
    "apiDocs.examples.listSets" => "List icon sets",
    "apiDocs.examples.javascript" => "JavaScript",
    "apiDocs.examples.sync" => "Trigger sync (authenticated)",
    "apiDocs.labels.parameters" => "Parameters",
    "apiDocs.labels.try" => "Try:",
    "apiDocs.labels.response" => "Response:",

    # ─────────────────────────── MCP docs — /docs/mcp ─────────────
    "mcpDocs.headers.pageTitle" => "MCP Server",
    "mcpDocs.headers.installation" => "Installation",
    "mcpDocs.headers.availableTools" => "Available Tools",
    "mcpDocs.headers.usageExample" => "Usage Example",
    "mcpDocs.messages.intro" =>
      "Search icons directly from Claude Desktop or Claude Code using the MCP (Model Context Protocol) server.",
    "mcpDocs.messages.installation" =>
      "The MCP server is published as an npm package. No local installation needed — npx runs it on demand.",
    "mcpDocs.messages.claudeDesktop" => "Add this to your Claude Desktop configuration file:",
    "mcpDocs.messages.claudeCode" => "Add the MCP server to your Claude Code settings:",
    "mcpDocs.messages.usageExample" => "Once configured, ask Claude:",
    "mcpDocs.tools.searchIcons" =>
      "Search icons by name. Filter by style and size. Returns icon names, styles, sizes, and SVG URLs.",
    "mcpDocs.tools.getIconSvg" =>
      "Fetch the raw SVG content of a specific icon. Useful for embedding icons directly.",
    "mcpDocs.examples.calendar" => "\"Find me a calendar icon in regular style, 24px\"",
    "mcpDocs.examples.arrow" => "\"Search for arrow icons available in the filled style\"",
    "mcpDocs.examples.addSvg" => "\"Get the SVG for the Add icon\"",

    # ─────────────────────────── LLM docs — /docs/llms ────────────
    "llmsDocs.headers.pageTitle" => "LLM Integration",
    "llmsDocs.headers.textFormat" => "Text Format",
    "llmsDocs.headers.machineDocs" => "Machine-Readable Docs",
    "llmsDocs.headers.mcpServer" => "MCP Server",
    "llmsDocs.headers.tips" => "Tips",
    "llmsDocs.messages.intro" =>
      "Best practices for using icons.pureadmin.io with AI assistants and large language models.",
    "llmsDocs.messages.textFormat" =>
      "Use format=text for the most token-efficient response. Returns one icon per line, plain text.",
    "llmsDocs.messages.mcpServer" =>
      "For Claude Desktop and Claude Code, use the MCP server for the best integration experience — it provides structured tool calls instead of raw HTTP.",
    "llmsDocs.links.mcpDocs" => "Read the MCP server guide →",
    "llmsDocs.links.llmsTxt" =>
      "Plain text documentation for LLMs. Describes the API, search syntax, and available icon sets.",
    "llmsDocs.links.aiPlugin" =>
      "OpenAI plugin manifest. Allows ChatGPT and compatible tools to discover the API.",
    "llmsDocs.tips.textFormat" => "Use format=text to minimize token usage",
    "llmsDocs.tips.limit" => "Use limit=5 to keep responses small",
    "llmsDocs.tips.set" => "Filter by set if you only need icons from one library",
    "llmsDocs.tips.compact" => "The compact format gives structured JSON with minimal fields",

    # ─────────────────────────── Stats — /stats ───────────────────
    "stats.headers.pageTitle" => "Stats",
    "stats.headers.popularIcons" => "Popular Icons",
    "stats.headers.bySurface" => "By Surface",
    "stats.headers.byFormat" => "By Format",
    "stats.tableHeaders.period" => "Period",
    "stats.tableHeaders.copies" => "Copies",
    "stats.tableHeaders.downloads" => "Downloads",
    "stats.tableHeaders.searches" => "Searches",
    "stats.tableHeaders.count" => "Count",
    "stats.filters.allSources" => "All",
    "stats.filters.web" => "Web",
    "stats.filters.api" => "API",
    "stats.filters.byCopy" => "By copies",
    "stats.filters.byDownload" => "By downloads",
    "stats.tooltips.copyUnavailableForApi" => "API consumers don't generate copy events",
    "stats.periods.today" => "Today",
    "stats.periods.7d" => "7 days",
    "stats.periods.30d" => "30 days",
    "stats.periods.allTime" => "All time",
    "stats.empty.noData" => "No data yet for this period.",
    "stats.messages.refreshNote" => "Auto-refreshes every 30s · Cube refreshes every 3 min",

    # ─────────────────────────── Sync discrepancies — /sync/discrepancies
    "syncDiscrepancies.headers.pageTitle" => "Sync Discrepancy Report",
    "syncDiscrepancies.headers.summaryByStyle" => "Summary by Style",
    "syncDiscrepancies.tableHeaders.missingFiles" => "Missing Files",
    "syncDiscrepancies.labels.lastSync" => "Last sync: %{when}",
    "syncDiscrepancies.labels.discrepancyCount" => "%{count} discrepancies",
    "syncDiscrepancies.labels.missingCount" => "%{count} missing",
    "syncDiscrepancies.messages.whatAreDiscrepancies" => "What are discrepancies?",
    "syncDiscrepancies.messages.explanation" =>
      "These are cases where an icon set's metadata claims certain sizes/styles exist, but the actual SVG files are missing from the repository. This is an upstream data quality issue.",
    "syncDiscrepancies.empty.noDiscrepancies" =>
      "No discrepancies found! All metadata matches actual SVG files.",
    "syncDiscrepancies.empty.noSync" => "No sync has been completed yet."
  }

  @doc """
  Translates a key with optional parameter interpolation.

  Calls the app-configured callback if set, falls back to English defaults.

  ## Examples

      t("common.labels.loading")
      # => "Loading..."

      t("iconSearch.messages.results", %{count: 30, total: 392})
      # => "Showing 30 of 392 icons"
  """
  @spec t(String.t(), map()) :: String.t()
  def t(key, params \\ %{})

  def t(key, params) do
    case Application.get_env(:pure_admin_icons, :translate) do
      nil ->
        default(key, params)

      fun when is_function(fun, 2) ->
        case fun.(key, params) do
          nil -> default(key, params)
          "" -> default(key, params)
          result -> result
        end
    end
  end

  @doc """
  Returns the default English translation for a key with interpolation.

  Returns the key itself if no default exists.
  """
  @spec default(String.t(), map()) :: String.t()
  def default(key, params \\ %{}) do
    case Map.get(@defaults, key) do
      nil -> key
      text -> interpolate(text, params)
    end
  end

  @doc """
  Interpolates `%{param}` placeholders in a string with values from the params map.

  Exported for use by app translation callbacks.

  ## Examples

      interpolate("Found %{count} results", %{count: 3})
      # => "Found 3 results"

      interpolate("Page %{page} of %{total}", %{page: 2, total: 5})
      # => "Page 2 of 5"
  """
  @spec interpolate(String.t(), map()) :: String.t()
  def interpolate(string, params) when is_binary(string) and map_size(params) == 0, do: string

  def interpolate(string, params) when is_binary(string) do
    Enum.reduce(params, string, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  @doc """
  Returns the full map of default English translations.

  Useful for apps that want to see all available keys.
  """
  @spec defaults() :: map()
  def defaults, do: @defaults
end
