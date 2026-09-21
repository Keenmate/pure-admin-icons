defmodule PureAdminIcons.RasterizerTest do
  use ExUnit.Case, async: true

  alias PureAdminIcons.Rasterizer

  describe "render_png/2 size guard" do
    test "rejects a size not in the allowlist before invoking resvg" do
      assert {:error, :invalid_size} = Rasterizer.render_png("nope.svg", 999)
    end

    test "rejects a non-integer size (e.g. a string that could smuggle a flag)" do
      assert {:error, :invalid_size} = Rasterizer.render_png("nope.svg", "24")
      assert {:error, :invalid_size} = Rasterizer.render_png("nope.svg", "--dpi=9000")
    end

    test "rejects zero / negative sizes" do
      assert {:error, :invalid_size} = Rasterizer.render_png("nope.svg", 0)
      assert {:error, :invalid_size} = Rasterizer.render_png("nope.svg", -24)
    end
  end

  describe "allowed_sizes/0" do
    test "are all positive integers and include the common defaults" do
      sizes = Rasterizer.allowed_sizes()
      assert Enum.all?(sizes, &(is_integer(&1) and &1 > 0))
      assert 24 in sizes
      assert 48 in sizes
    end
  end
end
