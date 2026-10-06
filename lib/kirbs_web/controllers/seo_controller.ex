defmodule KirbsWeb.SeoController do
  @moduledoc "robots.txt and sitemap.xml (crawler formats, so a controller rather than a LiveView)."
  use KirbsWeb, :controller

  alias Kirbs.Resources.{Category, Item}
  alias KirbsWeb.Shop.CategoryTree

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /admin
    Disallow: /dashboard
    Disallow: /bags
    Disallow: /items
    Disallow: /review
    Disallow: /upload
    Disallow: /clients
    Disallow: /payouts
    Disallow: /warehouse-sales
    Disallow: /accounting
    Disallow: /settings
    Disallow: /checkout
    Disallow: /order
    Disallow: /orders
    Disallow: /login

    Sitemap: #{KirbsWeb.Endpoint.url()}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def sitemap(conn, _params) do
    tree = CategoryTree.build(Category.list_all!())
    items = Item.list_for_sitemap!()

    static = Enum.map([~p"/", ~p"/muuda", ~p"/uudised"], &{&1, nil})

    categories =
      Enum.map(tree.by_id |> Map.values() |> Enum.sort_by(& &1.slug), fn category ->
        {~p"/k/#{CategoryTree.segments(tree, category)}", nil}
      end)

    products = Enum.map(items, &{~p"/p/#{&1.slug}", &1.updated_at})

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, render_xml(static ++ categories ++ products))
  end

  defp render_xml(entries) do
    base = KirbsWeb.Endpoint.url()

    urls =
      Enum.map_join(entries, "\n", fn {path, updated_at} ->
        lastmod =
          if updated_at,
            do: "<lastmod>#{updated_at |> DateTime.to_date() |> Date.to_iso8601()}</lastmod>",
            else: ""

        "  <url><loc>#{escape(base <> path)}</loc>#{lastmod}</url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
