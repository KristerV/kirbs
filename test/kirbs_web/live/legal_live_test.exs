defmodule KirbsWeb.LegalLiveTest do
  use KirbsWeb.ConnCase

  import Phoenix.LiveViewTest

  test "terms, returns and privacy pages render for anonymous visitors", %{conn: conn} do
    {:ok, terms, _} = live(conn, ~p"/tingimused")
    assert has_element?(terms, "#terms-page")
    assert has_element?(terms, "#legal-nav")

    {:ok, returns, _} = live(conn, ~p"/tagastus")
    assert has_element?(returns, "#returns-page")

    {:ok, privacy, _} = live(conn, ~p"/privaatsus")
    assert has_element?(privacy, "#privacy-page")
  end

  test "footer shows company details and legal links", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/tingimused")

    assert has_element?(view, "#company-details", "Täp OÜ")
    assert has_element?(view, "#footer-terms[href='/tingimused']")
    assert has_element?(view, "#footer-returns[href='/tagastus']")
    assert has_element?(view, "#footer-privacy[href='/privaatsus']")
  end

  test "TODO notes stay in source comments, not in rendered legal text", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/privaatsus")
    refute html =~ "TODO(lawyer)"
    refute html =~ "TODO(owner)"
  end
end
