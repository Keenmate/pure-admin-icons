defmodule PureAdminIconsWeb.API.IconExportControllerTest do
  @moduledoc """
  Covers the guardrail / validation responses, which all return before any DB
  call — so these run without a database (the test env has no Ecto sandbox).
  The happy-path (real resolve + render + zip) is exercised via `mix run` against
  db-01 with the resvg shim; see docs/png-zip-export-plan.md.
  """
  use PureAdminIconsWeb.ConnCase, async: false

  defp from_ip(conn, ip), do: put_req_header(conn, "x-forwarded-for", ip)

  defp valid_icon, do: %{"set" => "lucide", "name" => "house", "style" => "outline"}

  describe "POST /api/icons/png-zip" do
    test "400 when icons/sizes are missing", %{conn: conn} do
      conn = conn |> from_ip("203.0.113.1") |> post(~p"/api/icons/png-zip", %{})
      assert json_response(conn, 400)["error"] =~ "icons"
    end

    test "422 when a size is not in the allowlist", %{conn: conn} do
      body = %{"icons" => [valid_icon()], "sizes" => [7]}
      conn = conn |> from_ip("203.0.113.2") |> post(~p"/api/icons/png-zip", body)
      assert json_response(conn, 422)["error"] =~ "allowed sizes"
    end

    test "422 when render units (icons × sizes) exceed the cap", %{conn: conn} do
      icons = for i <- 1..201, do: %{"set" => "lucide", "name" => "icon-#{i}", "style" => "outline"}
      body = %{"icons" => icons, "sizes" => [24]}
      conn = conn |> from_ip("203.0.113.3") |> post(~p"/api/icons/png-zip", body)
      resp = json_response(conn, 422)
      assert resp["error"] == "Batch too large"
      assert resp["requested_units"] == 201
    end

    test "422 when an icon triple is malformed", %{conn: conn} do
      body = %{"icons" => [%{"set" => "lucide", "name" => "house"}], "sizes" => [24]}
      conn = conn |> from_ip("203.0.113.4") |> post(~p"/api/icons/png-zip", body)
      assert json_response(conn, 422)["error"] =~ "set"
    end
  end

  describe "POST /api/icons/svg-zip" do
    test "400 when icons are missing", %{conn: conn} do
      conn = conn |> from_ip("203.0.113.5") |> post(~p"/api/icons/svg-zip", %{})
      assert json_response(conn, 400)["error"] =~ "icons"
    end

    test "422 when icon count exceeds the cap", %{conn: conn} do
      icons = for i <- 1..501, do: %{"set" => "lucide", "name" => "icon-#{i}", "style" => "outline"}
      conn = conn |> from_ip("203.0.113.6") |> post(~p"/api/icons/svg-zip", %{"icons" => icons})
      assert json_response(conn, 422)["max_icons"] == 500
    end
  end

  describe "rate limiting" do
    test "429 after the per-IP budget is exceeded", %{conn: _conn} do
      ip = "203.0.113.99"
      # Budget is 10/min. Use a bad size so each request consumes the budget
      # (rate is checked first) then returns 422 before any DB call.
      body = %{"icons" => [valid_icon()], "sizes" => [7]}

      for _ <- 1..10 do
        c = build_conn() |> put_req_header("x-forwarded-for", ip) |> post(~p"/api/icons/png-zip", body)
        assert c.status == 422
      end

      c = build_conn() |> put_req_header("x-forwarded-for", ip) |> post(~p"/api/icons/png-zip", body)
      resp = json_response(c, 429)
      assert resp["error"] == "Too many export requests"
      assert is_integer(resp["retry_after_seconds"])
    end
  end
end
