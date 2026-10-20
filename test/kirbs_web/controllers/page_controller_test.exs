defmodule KirbsWeb.PageControllerTest do
  use KirbsWeb.ConnCase

  test "GET /muuda", %{conn: conn} do
    conn = get(conn, ~p"/muuda")
    assert html_response(conn, 200) =~ "Käed Vabad Kirbukas"
  end
end
