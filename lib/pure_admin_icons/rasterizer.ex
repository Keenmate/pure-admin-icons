defmodule PureAdminIcons.Rasterizer do
  @moduledoc """
  Server-side SVG → PNG rasterization via the `resvg` CLI.

  resvg is a single self-contained binary (installed in the Docker runtime and
  expected on PATH in dev). It is invoked exactly the way the sync pipeline shells
  out to 7z/unzip. The source SVG is read from disk; only the PNG output is a
  temp file, removed immediately after it is read back.

  Set `RESVG_BIN` to override the binary path/name (e.g. in dev).
  """
  require Logger

  # Output PNG sizes callers may request. This both bounds the work and, because
  # every size is validated against this list before it reaches the CLI, means an
  # attacker can never inject an arbitrary `--flag`-looking argument via `size`.
  @allowed_sizes [16, 20, 24, 32, 48, 64, 96, 128, 256, 512]

  @doc "The set of PNG output sizes callers may request."
  def allowed_sizes, do: @allowed_sizes

  # Resolved at runtime so it can be set per-environment without recompiling:
  # `RESVG_BIN` env var wins, then `config :pure_admin_icons, :resvg_bin` (handy in
  # dev.local.exs), else `resvg` on PATH (production).
  defp resvg_bin do
    System.get_env("RESVG_BIN") ||
      Application.get_env(:pure_admin_icons, :resvg_bin) ||
      "resvg"
  end

  @doc """
  Rasterize the SVG at `svg_path` to a square `size`×`size` px PNG.

  `size` must be a member of `allowed_sizes/0`; anything else returns
  `{:error, :invalid_size}` without ever invoking resvg.

  Returns `{:ok, png_binary}` | `{:error, reason}`.
  """
  def render_png(svg_path, size)
      when is_binary(svg_path) and is_integer(size) and size in @allowed_sizes do
    out = Path.join(System.tmp_dir!(), "px-#{:erlang.unique_integer([:positive])}.png")

    # Options first, then `--`, then the positional paths — so a path that happens
    # to start with `-` can never be parsed by resvg as a flag. System.cmd/3 uses
    # execvp (no shell), so there is no shell-metacharacter injection surface.
    args = ["--width", Integer.to_string(size), "--height", Integer.to_string(size),
            "--", svg_path, out]

    try do
      case System.cmd(resvg_bin(), args, stderr_to_stdout: true) do
        {_, 0} ->
          File.read(out)

        {output, code} ->
          Logger.warning("[rasterizer] resvg exit #{code} for #{svg_path}: #{String.trim(output)}")
          {:error, :render_failed}
      end
    rescue
      e in ErlangError ->
        # :enoent etc. — most likely the resvg binary is not on PATH.
        Logger.error("[rasterizer] resvg invocation failed: #{inspect(e)}")
        {:error, :resvg_unavailable}
    after
      File.rm(out)
    end
  end

  def render_png(_svg_path, _size), do: {:error, :invalid_size}
end
