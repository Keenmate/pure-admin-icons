defmodule PureAdminIconsWeb.ErrorHTMLTest do
  use PureAdminIconsWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(PureAdminIconsWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Page Not Found"
    assert html =~ "404"
  end

  test "renders 500.html" do
    html = render_to_string(PureAdminIconsWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Something Went Wrong"
    assert html =~ "500"
  end
end
