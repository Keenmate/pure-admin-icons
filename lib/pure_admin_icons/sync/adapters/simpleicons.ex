defmodule PureAdminIcons.Sync.Adapters.Simpleicons do
  @moduledoc """
  Sync adapter for Simple Icons.

  Downloads icons from https://github.com/simple-icons/simple-icons
  SVG icons for popular brands (CC0 licensed).

  Structure:
    icons/*.svg            (flat directory, scalable 24x24 viewBox)

  Single style ("filled") — brand logos are solid monochrome paths. The display
  name comes from each SVG's `<title>` element (e.g. github.svg -> "GitHub"),
  since slugs must not be naively title-cased (dotnet -> ".NET").
  """

  @behaviour PureAdminIcons.Sync.Adapter

  require Logger

  alias PureAdminIcons.Naming

  @github_zip_url "https://github.com/simple-icons/simple-icons/archive/refs/heads/master.zip"

  @zip_root "simple-icons-master"
  @icons_subdir "icons"
  @style "filled"

  # Adapter callbacks

  @impl true
  def icon_set_id, do: "simpleicons"

  @impl true
  def name, do: "Simple Icons"

  @impl true
  def license, do: "CC0-1.0"

  @impl true
  def homepage_url, do: "https://simpleicons.org/"

  @impl true
  def github_url, do: "https://github.com/simple-icons/simple-icons"

  @impl true
  def styles, do: [@style]

  @impl true
  def sizes, do: []

  @impl true
  def default_size, do: 24

  @impl true
  def download do
    alias PureAdminIcons.Sync.Adapter

    case Adapter.get_cached_path(icon_set_id()) do
      {:ok, cached_path} ->
        Logger.info("[SimpleIcons] Using cached extraction at #{cached_path}")
        {:ok, cached_path}

      :miss ->
        download_fresh()
    end
  end

  defp download_fresh do
    alias PureAdminIcons.Sync.Adapter

    temp_zip = Path.join(System.tmp_dir!(), "simple-icons-#{:os.system_time(:millisecond)}.zip")
    temp_dir = Path.join(System.tmp_dir!(), "simple-icons-extract-#{:os.system_time(:millisecond)}")

    Logger.info("[SimpleIcons] Fetching ZIP from GitHub...")

    try do
      case Req.get(@github_zip_url, receive_timeout: 300_000, into: File.stream!(temp_zip)) do
        {:ok, %{status: 200}} ->
          Logger.info("[SimpleIcons] ZIP downloaded, extracting...")
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
      Logger.info("[SimpleIcons] Parsing icons from #{icons_dir}...")

      icons =
        icons_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".svg"))
        |> Enum.map(fn filename ->
          slug = String.replace_suffix(filename, ".svg", "")
          content = read_svg(Path.join(icons_dir, filename))
          display_name = title_from_svg(content) || Naming.title_case(slug)

          %{
            icon_set: icon_set_id(),
            name: display_name,
            name_lower: slug,
            style: @style,
            is_scalable: true,
            sizes: [],
            filenames: %{"0" => "#{slug}.svg"},
            ios_identifiers: %{"0" => Naming.camel_case(slug)},
            android_identifiers: %{"0" => "ic_simpleicons_#{String.replace(slug, "-", "_")}"},
            svg_hash: hash_content(content)
          }
        end)

      Logger.info("[SimpleIcons] Parsed #{length(icons)} icons")
      {:ok, %{icons: icons, synonyms: %{}, discrepancies: []}}
    else
      Logger.warning("[SimpleIcons] Icons directory not found: #{icons_dir}")
      {:error, "Icons directory not found"}
    end
  end

  @impl true
  def move_svgs(extracted_path, output_dir) do
    icons_dir = Path.join([extracted_path, @zip_root, @icons_subdir])
    style_dir = Path.join([output_dir, icon_set_id(), @style])

    File.rm_rf(style_dir)
    File.mkdir_p!(style_dir)

    total_moved =
      icons_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".svg"))
      |> Enum.map(fn filename ->
        source = Path.join(icons_dir, filename)
        target = Path.join(style_dir, filename)

        case File.copy(source, target) do
          {:ok, _} -> 1
          {:error, _} -> 0
        end
      end)
      |> Enum.sum()

    Logger.info("[SimpleIcons] Moved #{total_moved} SVGs to #{style_dir}")
    {:ok, total_moved}
  end

  @impl true
  def cleanup(extracted_path) do
    alias PureAdminIcons.Sync.Adapter

    if Adapter.is_cached_path?(extracted_path) do
      Logger.debug("[SimpleIcons] Keeping cached extraction")
      :ok
    else
      File.rm_rf(extracted_path)
      :ok
    end
  end

  # Private helpers

  defp read_svg(path) do
    case File.read(path) do
      {:ok, data} -> data
      _ -> ""
    end
  end

  # Extract the brand's display name from the SVG's <title> element and
  # unescape the handful of XML entities Simple Icons uses (e.g. AT&amp;T).
  defp title_from_svg(content) do
    case Regex.run(~r/<title>(.*?)<\/title>/s, content) do
      [_, title] -> title |> String.trim() |> unescape_xml()
      _ -> nil
    end
  end

  defp unescape_xml(str) do
    str
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
  end

  defp hash_content(""), do: nil
  defp hash_content(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

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
