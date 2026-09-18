defmodule PureAdminIcons.Sync.Adapters.Carbon do
  @moduledoc """
  Sync adapter for Carbon Icons (IBM Carbon Design System).

  Downloads the `@carbon/icons` npm package (the full Carbon monorepo is huge;
  the published package ships just the SVGs). No GitHub ZIP is used.

  Structure (inside npm tarball):
    package/svg/16/*.svg
    package/svg/20/*.svg
    package/svg/24/*.svg
    package/svg/32/*.svg   (~2600 icons — the complete set)

  Only the 32px directory is the complete set; the smaller sizes hold a handful
  of optically-adjusted variants. Carbon icons are vector/scalable, so we treat
  the 32px SVGs as the single scalable source.

  Styles are split by a trailing `--filled` filename suffix:
    add.svg              -> "outline"
    accessibility--color--filled.svg -> "filled" (name "accessibility--color")

  Nested category subdirectories under svg/32 (e.g. `watson-health/`) are skipped
  in this pass to avoid flattened name collisions.
  """

  @behaviour PureAdminIcons.Sync.Adapter

  require Logger

  alias PureAdminIcons.Naming

  @npm_registry_url "https://registry.npmjs.org/@carbon/icons"

  # The complete set lives at 32px inside the tarball.
  @svg_subdir "package/svg/32"
  @filled_suffix "--filled"

  # Adapter callbacks

  @impl true
  def icon_set_id, do: "carbon"

  @impl true
  def name, do: "Carbon Icons"

  @impl true
  def license, do: "Apache-2.0"

  @impl true
  def homepage_url, do: "https://carbondesignsystem.com/elements/icons/library/"

  @impl true
  def github_url, do: "https://github.com/carbon-design-system/carbon"

  @impl true
  def styles, do: ["outline", "filled"]

  @impl true
  def sizes, do: []

  @impl true
  def default_size, do: 32

  @impl true
  def download do
    alias PureAdminIcons.Sync.Adapter

    case Adapter.get_cached_path(icon_set_id()) do
      {:ok, cached_path} ->
        Logger.info("[Carbon] Using cached extraction at #{cached_path}")
        {:ok, cached_path}

      :miss ->
        download_fresh()
    end
  end

  defp download_fresh do
    alias PureAdminIcons.Sync.Adapter

    Logger.info("[Carbon] Fetching latest version from npm registry...")

    with {:ok, tarball_url} <- get_latest_tarball_url(),
         {:ok, extracted_path} <- download_and_extract(tarball_url) do
      Adapter.save_to_cache(icon_set_id(), extracted_path)
    end
  end

  defp get_latest_tarball_url do
    case Req.get(@npm_registry_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        latest_version = body["dist-tags"]["latest"]
        tarball_url = body["versions"][latest_version]["dist"]["tarball"]
        Logger.info("[Carbon] Latest version: #{latest_version}, tarball: #{tarball_url}")
        {:ok, tarball_url}

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch npm registry: HTTP #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch npm registry: #{inspect(reason)}"}
    end
  end

  defp download_and_extract(tarball_url) do
    temp_tgz = Path.join(System.tmp_dir!(), "carbon-icons-#{:os.system_time(:millisecond)}.tgz")
    temp_dir = Path.join(System.tmp_dir!(), "carbon-extract-#{:os.system_time(:millisecond)}")

    Logger.info("[Carbon] Downloading tarball...")

    try do
      case Req.get(tarball_url, receive_timeout: 300_000, into: File.stream!(temp_tgz)) do
        {:ok, %{status: 200}} ->
          Logger.info("[Carbon] Tarball downloaded, extracting...")
          File.mkdir_p!(temp_dir)

          case extract_tgz(temp_tgz, temp_dir) do
            :ok ->
              File.rm(temp_tgz)
              {:ok, temp_dir}

            {:error, reason} ->
              File.rm(temp_tgz)
              File.rm_rf(temp_dir)
              {:error, reason}
          end

        {:ok, %{status: status}} ->
          File.rm(temp_tgz)
          {:error, "Failed to download tarball: HTTP #{status}"}

        {:error, reason} ->
          File.rm(temp_tgz)
          {:error, "Failed to download tarball: #{inspect(reason)}"}
      end
    rescue
      e ->
        File.rm(temp_tgz)
        {:error, "Download failed: #{inspect(e)}"}
    end
  end

  @impl true
  def parse(extracted_path) do
    svg_dir = Path.join(extracted_path, @svg_subdir)

    if File.dir?(svg_dir) do
      log_skipped_subdirs(svg_dir)
      Logger.info("[Carbon] Parsing icons from #{svg_dir}...")

      icons =
        svg_dir
        |> flat_svg_files()
        |> Enum.map(fn filename ->
          full_path = Path.join(svg_dir, filename)
          base = String.replace_suffix(filename, ".svg", "")
          {slug, style} = split_style(base)
          display_name = Naming.title_case(String.replace(slug, "--", "-"))

          %{
            icon_set: icon_set_id(),
            name: display_name,
            name_lower: slug,
            style: style,
            is_scalable: true,
            sizes: [],
            filenames: %{"0" => "#{slug}.svg"},
            ios_identifiers: %{"0" => Naming.camel_case(String.replace(slug, "--", "-"))},
            android_identifiers: %{"0" => "ic_carbon_#{slug |> String.replace("--", "_") |> String.replace("-", "_")}"},
            svg_hash: hash_file(full_path)
          }
        end)

      Logger.info("[Carbon] Parsed #{length(icons)} icons")
      {:ok, %{icons: icons, synonyms: %{}, discrepancies: []}}
    else
      Logger.warning("[Carbon] SVG directory not found: #{svg_dir}")
      {:error, "SVG directory not found"}
    end
  end

  @impl true
  def move_svgs(extracted_path, output_dir) do
    svg_dir = Path.join(extracted_path, @svg_subdir)
    icon_set_dir = Path.join(output_dir, icon_set_id())

    Enum.each(styles(), fn style ->
      style_dir = Path.join(icon_set_dir, style)
      File.rm_rf(style_dir)
      File.mkdir_p!(style_dir)
    end)

    total_moved =
      svg_dir
      |> flat_svg_files()
      |> Enum.map(fn filename ->
        base = String.replace_suffix(filename, ".svg", "")
        {slug, style} = split_style(base)
        source = Path.join(svg_dir, filename)
        target = Path.join([icon_set_dir, style, "#{slug}.svg"])

        case File.copy(source, target) do
          {:ok, _} -> 1
          {:error, _} -> 0
        end
      end)
      |> Enum.sum()

    Logger.info("[Carbon] Moved #{total_moved} SVGs to #{icon_set_dir}")
    {:ok, total_moved}
  end

  @impl true
  def cleanup(extracted_path) do
    alias PureAdminIcons.Sync.Adapter

    if Adapter.is_cached_path?(extracted_path) do
      Logger.debug("[Carbon] Keeping cached extraction")
      :ok
    else
      File.rm_rf(extracted_path)
      :ok
    end
  end

  # Private helpers

  # Only top-level .svg files; nested category subdirs (Q/, watson-health/) skipped.
  defp flat_svg_files(svg_dir) do
    svg_dir
    |> File.ls!()
    |> Enum.filter(fn entry ->
      String.ends_with?(entry, ".svg") and File.regular?(Path.join(svg_dir, entry))
    end)
  end

  defp log_skipped_subdirs(svg_dir) do
    subdirs =
      svg_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(svg_dir, &1)))

    if subdirs != [] do
      Logger.info("[Carbon] Skipping #{length(subdirs)} nested category dir(s): #{Enum.join(subdirs, ", ")}")
    end
  end

  # Carbon encodes the filled style as a trailing `--filled` suffix; everything
  # else is the default outline style.
  defp split_style(base) do
    if String.ends_with?(base, @filled_suffix) do
      {String.replace_suffix(base, @filled_suffix, ""), "filled"}
    else
      {base, "outline"}
    end
  end

  defp hash_file(path) do
    case File.read(path) do
      {:ok, data} -> :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end

  defp extract_tgz(tgz_path, temp_dir) do
    cond do
      System.find_executable("tar") != nil -> extract_with_tar(tgz_path, temp_dir)
      match?({:ok, _}, find_7zip()) -> extract_with_7zip(tgz_path, temp_dir)
      true -> extract_with_erlang_tgz(tgz_path, temp_dir)
    end
  end

  defp find_7zip do
    cond do
      exe = System.find_executable("7z") -> {:ok, exe}
      File.exists?("C:/Program Files/7-Zip/7z.exe") -> {:ok, "C:/Program Files/7-Zip/7z.exe"}
      File.exists?("C:/Program Files (x86)/7-Zip/7z.exe") -> {:ok, "C:/Program Files (x86)/7-Zip/7z.exe"}
      true -> :not_found
    end
  end

  defp extract_with_tar(tgz_path, temp_dir) do
    {output, exit_code} =
      System.cmd("tar", ["xzf", tgz_path, "-C", temp_dir], stderr_to_stdout: true)

    if exit_code == 0, do: :ok, else: {:error, "tar failed: #{output}"}
  end

  defp extract_with_7zip(tgz_path, temp_dir) do
    {:ok, exe} = find_7zip()
    intermediate_tar = String.replace_suffix(tgz_path, ".tgz", ".tar")

    {output1, exit1} =
      System.cmd(exe, ["x", tgz_path, "-o#{Path.dirname(tgz_path)}", "-y"], stderr_to_stdout: true)

    if exit1 != 0 do
      {:error, "7zip decompress failed: #{output1}"}
    else
      {output2, exit2} =
        System.cmd(exe, ["x", intermediate_tar, "-o#{temp_dir}", "-y"], stderr_to_stdout: true)

      File.rm(intermediate_tar)
      if exit2 == 0, do: :ok, else: {:error, "7zip extract failed: #{output2}"}
    end
  end

  defp extract_with_erlang_tgz(tgz_path, temp_dir) do
    case :erl_tar.extract(String.to_charlist(tgz_path), [
           :compressed,
           {:cwd, String.to_charlist(temp_dir)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, "Erlang tgz extract failed: #{inspect(reason)}"}
    end
  end
end
