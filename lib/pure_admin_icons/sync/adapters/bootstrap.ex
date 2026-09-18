defmodule PureAdminIcons.Sync.Adapters.Bootstrap do
  @moduledoc """
  Sync adapter for Bootstrap Icons.

  Downloads icons from https://github.com/twbs/icons
  Official open source SVG icon library for Bootstrap.

  Structure:
    icons/*.svg            (flat directory, scalable 16x16 viewBox)

  Styles are distinguished by the `-fill` filename suffix:
    heart.svg       -> "outline"
    heart-fill.svg  -> "filled"
  """

  @behaviour PureAdminIcons.Sync.Adapter

  require Logger

  alias PureAdminIcons.Naming

  @github_zip_url "https://github.com/twbs/icons/archive/refs/heads/main.zip"

  # Top-level folder inside the GitHub zip (repo-branch), and the icons subdir.
  @zip_root "icons-main"
  @icons_subdir "icons"

  # Adapter callbacks

  @impl true
  def icon_set_id, do: "bootstrap"

  @impl true
  def name, do: "Bootstrap Icons"

  @impl true
  def license, do: "MIT"

  @impl true
  def homepage_url, do: "https://icons.getbootstrap.com/"

  @impl true
  def github_url, do: "https://github.com/twbs/icons"

  @impl true
  def styles, do: ["outline", "filled"]

  @impl true
  def sizes, do: []

  @impl true
  def default_size, do: 16

  @impl true
  def download do
    alias PureAdminIcons.Sync.Adapter

    case Adapter.get_cached_path(icon_set_id()) do
      {:ok, cached_path} ->
        Logger.info("[Bootstrap] Using cached extraction at #{cached_path}")
        {:ok, cached_path}

      :miss ->
        download_fresh()
    end
  end

  defp download_fresh do
    alias PureAdminIcons.Sync.Adapter

    temp_zip = Path.join(System.tmp_dir!(), "bootstrap-icons-#{:os.system_time(:millisecond)}.zip")
    temp_dir = Path.join(System.tmp_dir!(), "bootstrap-extract-#{:os.system_time(:millisecond)}")

    Logger.info("[Bootstrap] Fetching ZIP from GitHub...")

    try do
      case Req.get(@github_zip_url, receive_timeout: 300_000, into: File.stream!(temp_zip)) do
        {:ok, %{status: 200}} ->
          Logger.info("[Bootstrap] ZIP downloaded, extracting...")
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
    icons_dir = Path.join([extracted_path, @zip_root, @icons_subdir])

    if File.dir?(icons_dir) do
      Logger.info("[Bootstrap] Parsing icons from #{icons_dir}...")

      icons =
        icons_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".svg"))
        |> Enum.map(fn filename ->
          base = String.replace_suffix(filename, ".svg", "")
          {name, style} = split_style(base)
          display_name = Naming.title_case(name)

          %{
            icon_set: icon_set_id(),
            name: display_name,
            name_lower: name,
            style: style,
            is_scalable: true,
            sizes: [],
            filenames: %{"0" => "#{name}.svg"},
            ios_identifiers: %{"0" => Naming.camel_case(name)},
            android_identifiers: %{"0" => "ic_bootstrap_#{String.replace(name, "-", "_")}"},
            svg_hash: hash_file(Path.join(icons_dir, filename))
          }
        end)

      Logger.info("[Bootstrap] Parsed #{length(icons)} icons")
      {:ok, %{icons: icons, synonyms: %{}, discrepancies: []}}
    else
      Logger.warning("[Bootstrap] Icons directory not found: #{icons_dir}")
      {:error, "Icons directory not found"}
    end
  end

  @impl true
  def move_svgs(extracted_path, output_dir) do
    icons_dir = Path.join([extracted_path, @zip_root, @icons_subdir])
    icon_set_dir = Path.join(output_dir, icon_set_id())

    # Prepare fresh style directories
    Enum.each(styles(), fn style ->
      style_dir = Path.join(icon_set_dir, style)
      File.rm_rf(style_dir)
      File.mkdir_p!(style_dir)
    end)

    total_moved =
      icons_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".svg"))
      |> Enum.map(fn filename ->
        base = String.replace_suffix(filename, ".svg", "")
        {name, style} = split_style(base)
        source = Path.join(icons_dir, filename)
        # Store under the style dir with the style suffix stripped: heart-fill.svg -> filled/heart.svg
        target = Path.join([icon_set_dir, style, "#{name}.svg"])

        case File.copy(source, target) do
          {:ok, _} -> 1
          {:error, _} -> 0
        end
      end)
      |> Enum.sum()

    Logger.info("[Bootstrap] Moved #{total_moved} SVGs to #{icon_set_dir}")
    {:ok, total_moved}
  end

  @impl true
  def cleanup(extracted_path) do
    alias PureAdminIcons.Sync.Adapter

    if Adapter.is_cached_path?(extracted_path) do
      Logger.debug("[Bootstrap] Keeping cached extraction")
      :ok
    else
      File.rm_rf(extracted_path)
      :ok
    end
  end

  # Private helpers

  # Bootstrap encodes the filled style as a `-fill` filename suffix; everything
  # else is the default outline style.
  defp split_style(base) do
    case String.replace_suffix(base, "-fill", "") do
      ^base -> {base, "outline"}
      stripped -> {stripped, "filled"}
    end
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
      exe = System.find_executable("7z") -> {:ok, exe}
      File.exists?("C:/Program Files/7-Zip/7z.exe") -> {:ok, "C:/Program Files/7-Zip/7z.exe"}
      File.exists?("C:/Program Files (x86)/7-Zip/7z.exe") -> {:ok, "C:/Program Files (x86)/7-Zip/7z.exe"}
      true -> :not_found
    end
  end

  defp extract_with_7zip(exe, zip_path, temp_dir) do
    {output, exit_code} =
      System.cmd(
        exe,
        ["x", zip_path, "-o#{temp_dir}", "#{@zip_root}/#{@icons_subdir}/*", "-y"],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: :ok, else: {:error, "7zip failed: #{output}"}
  end

  defp extract_with_unzip(zip_path, temp_dir) do
    {output, exit_code} =
      System.cmd(
        "unzip",
        ["-q", "-o", zip_path, "#{@zip_root}/#{@icons_subdir}/*", "-d", temp_dir],
        stderr_to_stdout: true
      )

    if exit_code == 0, do: :ok, else: {:error, "unzip failed: #{output}"}
  end

  defp extract_with_erlang(zip_path, temp_dir) do
    case :zip.unzip(String.to_charlist(zip_path), [{:cwd, String.to_charlist(temp_dir)}]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Erlang unzip failed: #{inspect(reason)}"}
    end
  end
end
