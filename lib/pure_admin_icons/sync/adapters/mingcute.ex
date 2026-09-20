defmodule PureAdminIcons.Sync.Adapters.Mingcute do
  @moduledoc """
  Sync adapter for MingCute Icons (Apache-2.0).

  Downloads icons from https://github.com/mingcute-design/mingcute-icons
  (the old `Richard9394/MingCute` repo moved here; the old URL redirects).

  Structure:
    assets/svg/core/<style>/<category>/<name>.svg   (nested by style then category)

  Two native styles, distinguished only by directory (no filename suffix):
    regular -> "outline"
    filled  -> "filled"

  Filenames are snake_case (`align_arrow_down.svg`); we slugify to kebab for
  identity and on-disk storage. MingCute SVGs hardcode their color (`#10161F`)
  on fill/stroke, so we rewrite every fill/stroke to `currentColor` on copy for
  theme support.
  """

  @behaviour PureAdminIcons.Sync.Adapter

  require Logger

  alias PureAdminIcons.Naming

  @github_zip_url "https://github.com/mingcute-design/mingcute-icons/archive/refs/heads/main.zip"

  # GitHub names the archive's top folder after the canonical repo name.
  @zip_root "mingcute-icons-main"
  @svg_subdir "assets/svg/core"

  # Canonical style code -> native folder name under assets/svg/core/
  @style_dirs %{
    "outline" => "regular",
    "filled" => "filled"
  }

  # Adapter callbacks

  @impl true
  def icon_set_id, do: "mingcute"

  @impl true
  def name, do: "MingCute Icons"

  @impl true
  def license, do: "Apache-2.0"

  @impl true
  def homepage_url, do: "https://www.mingcute.com/"

  @impl true
  def github_url, do: "https://github.com/mingcute-design/mingcute-icons"

  @impl true
  def styles, do: ["outline", "filled"]

  @impl true
  def sizes, do: []

  @impl true
  def default_size, do: 24

  @impl true
  def download do
    alias PureAdminIcons.Sync.Adapter

    case Adapter.get_cached_path(icon_set_id()) do
      {:ok, cached_path} ->
        Logger.info("[MingCute] Using cached extraction at #{cached_path}")
        {:ok, cached_path}

      :miss ->
        download_fresh()
    end
  end

  defp download_fresh do
    alias PureAdminIcons.Sync.Adapter

    temp_zip = Path.join(System.tmp_dir!(), "mingcute-icons-#{:os.system_time(:millisecond)}.zip")
    temp_dir = Path.join(System.tmp_dir!(), "mingcute-extract-#{:os.system_time(:millisecond)}")

    Logger.info("[MingCute] Fetching ZIP from GitHub...")

    try do
      case Req.get(@github_zip_url, receive_timeout: 300_000, into: File.stream!(temp_zip)) do
        {:ok, %{status: 200}} ->
          Logger.info("[MingCute] ZIP downloaded, extracting...")
          File.mkdir_p!(temp_dir)

          case extract_zip(temp_zip, temp_dir) do
            :ok ->
              File.rm(temp_zip)
              Adapter.save_to_cache(icon_set_id(), temp_dir)

            {:error, reason} ->
              File.rm(temp_zip)
              File.rm_rf(temp_dir)
              {:error, reason}
          end

        {:ok, %{status: status}} ->
          File.rm(temp_zip)
          {:error, "Failed to download ZIP: HTTP #{status}"}

        {:error, reason} ->
          File.rm(temp_zip)
          {:error, "Failed to download ZIP: #{inspect(reason)}"}
      end
    rescue
      e ->
        File.rm(temp_zip)
        {:error, "Download failed: #{inspect(e)}"}
    end
  end

  @impl true
  def parse(extracted_path) do
    svg_base = Path.join([extracted_path, @zip_root, @svg_subdir])

    if File.dir?(svg_base) do
      Logger.info("[MingCute] Parsing icons from #{svg_base}...")

      icons =
        Enum.flat_map(@style_dirs, fn {style, native_dir} ->
          style_dir = Path.join(svg_base, native_dir)

          style_dir
          |> svg_files_recursive()
          |> Enum.map(fn full_path ->
            slug = slug_of(full_path)

            %{
              icon_set: icon_set_id(),
              name: display_name(full_path),
              name_lower: slug,
              style: style,
              is_scalable: true,
              sizes: [],
              filenames: %{"0" => "#{slug}.svg"},
              ios_identifiers: %{"0" => Naming.camel_case(slug)},
              android_identifiers: %{"0" => "ic_mingcute_#{String.replace(slug, "-", "_")}"},
              svg_hash: hash_file(full_path)
            }
          end)
          # Categories can repeat an icon name; keep the first per style.
          |> Enum.uniq_by(& &1.name_lower)
        end)

      Logger.info("[MingCute] Parsed #{length(icons)} icons")
      {:ok, %{icons: icons, synonyms: %{}, discrepancies: []}}
    else
      Logger.warning("[MingCute] SVG directory not found: #{svg_base}")
      {:error, "SVG directory not found"}
    end
  end

  @impl true
  def move_svgs(extracted_path, output_dir) do
    svg_base = Path.join([extracted_path, @zip_root, @svg_subdir])
    icon_set_dir = Path.join(output_dir, icon_set_id())

    total_moved =
      Enum.map(@style_dirs, fn {style, native_dir} ->
        style_dir = Path.join(svg_base, native_dir)
        target_dir = Path.join(icon_set_dir, style)

        File.rm_rf(target_dir)
        File.mkdir_p!(target_dir)

        style_dir
        |> svg_files_recursive()
        |> Enum.uniq_by(&slug_of/1)
        |> Enum.map(fn source ->
          target = Path.join(target_dir, "#{slug_of(source)}.svg")

          case write_themed_svg(source, target) do
            :ok -> 1
            :error -> 0
          end
        end)
        |> Enum.sum()
      end)
      |> Enum.sum()

    Logger.info("[MingCute] Moved #{total_moved} SVGs to #{icon_set_dir}")
    {:ok, total_moved}
  end

  @impl true
  def cleanup(extracted_path) do
    alias PureAdminIcons.Sync.Adapter

    if Adapter.is_cached_path?(extracted_path) do
      Logger.debug("[MingCute] Keeping cached extraction")
      :ok
    else
      File.rm_rf(extracted_path)
      :ok
    end
  end

  # Private helpers

  # MingCute names are snake_case (`align_arrow_down`); title-case for display and
  # kebab for identity/storage (matching the Iconify slug: `align-arrow-down`).
  defp base_name(full_path), do: Path.basename(full_path, ".svg")
  defp display_name(full_path), do: full_path |> base_name() |> Naming.title_case()
  defp slug_of(full_path), do: full_path |> base_name() |> Naming.kebab_case()

  # Recursively collect every .svg under a directory (MingCute nests by category).
  defp svg_files_recursive(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.flat_map(fn entry ->
        full = Path.join(dir, entry)

        cond do
          File.dir?(full) -> svg_files_recursive(full)
          String.ends_with?(entry, ".svg") -> [full]
          true -> []
        end
      end)
    else
      []
    end
  end

  # MingCute SVGs hardcode `#10161F` on fill/stroke, so paths don't respond to CSS
  # color theming. Rewrite every non-`none` fill/stroke to `currentColor` so the
  # icons inherit text color (visible on any theme) and the preview color filter
  # can recolor them.
  defp write_themed_svg(source, target) do
    with {:ok, content} <- File.read(source),
         :ok <- File.write(target, current_color(content)) do
      :ok
    else
      _ -> :error
    end
  end

  defp current_color(svg) do
    String.replace(svg, ~r/\b(fill|stroke)="(?!none")[^"]*"/, ~S(\1="currentColor"))
  end

  defp hash_file(path) do
    case File.read(path) do
      {:ok, data} -> :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end

  defp extract_zip(zip_path, temp_dir) do
    case find_7zip() do
      {:ok, exe} ->
        extract_with_7zip(exe, zip_path, temp_dir)

      :not_found ->
        case System.find_executable("unzip") do
          nil -> extract_with_erlang(zip_path, temp_dir)
          _unzip -> extract_with_unzip(zip_path, temp_dir)
        end
    end
  end

  defp find_7zip do
    cond do
      exe = System.find_executable("7z") ->
        {:ok, exe}

      File.exists?("C:/Program Files/7-Zip/7z.exe") ->
        {:ok, "C:/Program Files/7-Zip/7z.exe"}

      File.exists?("C:/Program Files (x86)/7-Zip/7z.exe") ->
        {:ok, "C:/Program Files (x86)/7-Zip/7z.exe"}

      true ->
        :not_found
    end
  end

  # Extract the whole archive (no path filter): the SVGs are nested under
  # category subdirs, and `unzip`/`7z` glob patterns like `dir/*` match only the
  # directory entry, not its nested contents — so filtering would extract nothing.
  defp extract_with_7zip(exe, zip_path, temp_dir) do
    {output, exit_code} =
      System.cmd(exe, ["x", zip_path, "-o#{temp_dir}", "-y"], stderr_to_stdout: true)

    if exit_code == 0, do: :ok, else: {:error, "7zip failed: #{output}"}
  end

  defp extract_with_unzip(zip_path, temp_dir) do
    {output, exit_code} =
      System.cmd("unzip", ["-q", "-o", zip_path, "-d", temp_dir], stderr_to_stdout: true)

    if exit_code == 0, do: :ok, else: {:error, "unzip failed: #{output}"}
  end

  defp extract_with_erlang(zip_path, temp_dir) do
    case :zip.unzip(String.to_charlist(zip_path), [{:cwd, String.to_charlist(temp_dir)}]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Erlang unzip failed: #{inspect(reason)}"}
    end
  end
end
