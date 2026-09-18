defmodule PureAdminIcons.Sync.Adapter do
  @moduledoc """
  Behaviour for icon set sync adapters.

  Each icon set (FluentUI, Lucide, Tabler, etc.) implements this behaviour
  to handle downloading and parsing icons from their respective sources.
  """

  @doc """
  Returns the unique identifier for this icon set.
  Must match one of the values in Icon.icon_sets/0.
  """
  @callback icon_set_id() :: String.t()

  @doc """
  Returns human-readable name for this icon set.
  """
  @callback name() :: String.t()

  @doc """
  Returns the license identifier for this icon set.
  """
  @callback license() :: String.t()

  @doc """
  Returns the homepage URL for this icon set.
  """
  @callback homepage_url() :: String.t()

  @doc """
  Returns the GitHub repository URL for this icon set.
  """
  @callback github_url() :: String.t()

  @doc """
  Returns the list of available styles for this icon set.
  For example: ["regular", "filled"] or ["outline", "solid"]
  """
  @callback styles() :: [String.t()]

  @doc """
  Returns the list of available sizes for this icon set.
  For example: [16, 20, 24, 28, 32, 48] or [24]
  """
  @callback sizes() :: [integer()]

  @doc """
  Returns the default size for this icon set.
  """
  @callback default_size() :: integer()

  @doc """
  Downloads the icon set from its source (e.g., GitHub ZIP).
  Returns the path to the extracted directory.
  """
  @callback download() :: {:ok, String.t()} | {:error, term()}

  @doc """
  Parses icons from the extracted directory.

  Returns a tuple with:
  - List of icon maps ready for database insertion
  - Map of synonyms (icon_name => [synonyms])
  - List of discrepancies found during parsing
  """
  @callback parse(extracted_path :: String.t()) ::
              {:ok, %{icons: [map()], synonyms: map(), discrepancies: [map()]}}
              | {:error, term()}

  @doc """
  Moves SVG files from the extracted directory to the output directory.

  The output structure should be: {output_dir}/{icon_set}/{style}/{filename}.svg
  """
  @callback move_svgs(extracted_path :: String.t(), output_dir :: String.t()) ::
              {:ok, integer()} | {:error, term()}

  @doc """
  Cleans up temporary files after sync.
  """
  @callback cleanup(extracted_path :: String.t()) :: :ok

  # Helper to get all registered adapters
  @adapters %{
    "fluentui" => PureAdminIcons.Sync.Adapters.Fluentui,
    "lucide" => PureAdminIcons.Sync.Adapters.Lucide,
    "tabler" => PureAdminIcons.Sync.Adapters.Tabler,
    "heroicons" => PureAdminIcons.Sync.Adapters.Heroicons,
    "fontawesome" => PureAdminIcons.Sync.Adapters.Fontawesome,
    "phosphor" => PureAdminIcons.Sync.Adapters.Phosphor,
    "remix" => PureAdminIcons.Sync.Adapters.Remix,
    "material" => PureAdminIcons.Sync.Adapters.Material,
    "bootstrap" => PureAdminIcons.Sync.Adapters.Bootstrap,
    "simpleicons" => PureAdminIcons.Sync.Adapters.Simpleicons,
    "carbon" => PureAdminIcons.Sync.Adapters.Carbon
  }

  @doc """
  Get all registered adapters.
  """
  def all_adapters, do: @adapters

  @doc """
  Get adapter module for an icon set.
  """
  def get_adapter(icon_set) do
    Map.get(@adapters, icon_set)
  end

  @doc """
  List all available icon set IDs.
  """
  def available_icon_sets do
    Map.keys(@adapters)
  end

  @doc """
  Get metadata for all icon sets.
  """
  def icon_sets_metadata do
    Enum.map(@adapters, fn {id, module} ->
      %{
        id: id,
        name: module.name(),
        license: module.license(),
        homepage_url: module.homepage_url(),
        github_url: module.github_url(),
        styles: module.styles(),
        sizes: module.sizes(),
        default_size: module.default_size()
      }
    end)
  end

  # ---- Development Caching Helpers ----
  # These functions help cache extracted icon repos during development
  # to avoid re-downloading/extracting on every sync.

  @cache_base_dir ".cache/icons"

  @doc """
  Returns the cache directory for an icon set.
  """
  def cache_dir(icon_set), do: Path.join([@cache_base_dir, icon_set])

  @doc """
  Check if caching is enabled (dev only by default).
  """
  def cache_enabled? do
    Application.get_env(:pure_admin_icons, :use_icon_cache, false)
  end

  @doc """
  Check if a valid cache exists for an icon set.
  """
  def cache_valid?(icon_set) do
    cache_path = cache_dir(icon_set)
    File.dir?(cache_path) and File.exists?(Path.join(cache_path, ".cache_info"))
  end

  @doc """
  Get cached extraction path if available.
  Returns {:ok, path} if cache exists, :miss otherwise.
  """
  def get_cached_path(icon_set) do
    if cache_enabled?() and cache_valid?(icon_set) do
      {:ok, cache_dir(icon_set)}
    else
      :miss
    end
  end

  @doc """
  Save an extracted directory to the cache.
  Moves the extracted_path to the cache location.
  """
  def save_to_cache(icon_set, extracted_path) do
    if cache_enabled?() do
      target = cache_dir(icon_set)

      # Remove old cache if exists
      File.rm_rf(target)
      File.mkdir_p!(Path.dirname(target))

      # Copy instead of move (extracted_path might be on different filesystem)
      case File.cp_r(extracted_path, target) do
        {:ok, _} ->
          # Write cache metadata
          cache_info = %{
            downloaded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            cached: true
          }
          File.write!(Path.join(target, ".cache_info"), Jason.encode!(cache_info))

          # Remove original temp dir
          File.rm_rf(extracted_path)

          {:ok, target}

        {:error, reason, _file} ->
          # If copy fails, just return original path
          require Logger
          Logger.warning("Failed to cache extraction: #{inspect(reason)}")
          {:ok, extracted_path}
      end
    else
      {:ok, extracted_path}
    end
  end

  @doc """
  Check if a path is a cached path (should not be deleted on cleanup).
  """
  def is_cached_path?(path) do
    String.contains?(path, @cache_base_dir)
  end

  @doc """
  Clear cache for a specific icon set or all icon sets.
  """
  def clear_cache(icon_set \\ nil) do
    if icon_set do
      File.rm_rf(cache_dir(icon_set))
    else
      File.rm_rf(@cache_base_dir)
    end
    :ok
  end
end
