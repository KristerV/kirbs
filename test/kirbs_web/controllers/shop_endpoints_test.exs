defmodule KirbsWeb.ShopEndpointsTest do
  use KirbsWeb.ConnCase

  import Kirbs.ShopFixtures

  setup do
    seed_shop!()
    bag = bag!()
    published = item!(bag, %{brand: "Reima"})
    hidden = item!(bag, %{brand: "Secret", published: false})
    %{published: published, hidden: hidden}
  end

  describe "GET /img/:width/:id" do
    test "serves a resized jpeg for photos of published items", %{conn: conn} = ctx do
      [image] = Kirbs.Resources.Item.get!(ctx.published.id, load: [:images]).images
      conn = get(conn, ~p"/img/320/#{image.id}")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
      assert get_resp_header(conn, "cache-control") |> hd() =~ "max-age"
    end

    test "does not serve photos of unpublished items", %{conn: conn} = ctx do
      [image] = Kirbs.Resources.Item.get!(ctx.hidden.id, load: [:images]).images
      assert conn |> get(~p"/img/320/#{image.id}") |> response(404)
    end

    test "rejects widths outside the whitelist", %{conn: conn} = ctx do
      [image] = Kirbs.Resources.Item.get!(ctx.published.id, load: [:images]).images
      assert conn |> get("/img/99999/#{image.id}") |> response(404)
    end
  end

  describe "SEO endpoints" do
    test "sitemap lists static pages, categories and published items only",
         %{conn: conn} = ctx do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/xml"
      assert body =~ "/muuda</loc>"
      assert body =~ "/k/lapsed/poisid/pusid</loc>"
      assert body =~ "/p/#{ctx.published.slug}</loc>"
      assert length(String.split(body, "/p/")) == 2
    end

    test "robots.txt points to the sitemap", %{conn: conn} do
      body = conn |> get(~p"/robots.txt") |> response(200)
      assert body =~ "Sitemap: "
      assert body =~ "Disallow: /admin"
    end
  end
end
