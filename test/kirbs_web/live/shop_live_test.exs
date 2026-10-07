defmodule KirbsWeb.ShopLiveTest do
  use KirbsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Kirbs.ShopFixtures

  setup do
    seed_shop!()
    bag = bag!()

    jacket =
      item!(bag, %{
        category: "lapsed-valisriided-jakid",
        brand: "Reima",
        size: "110",
        gender: :boy,
        season: :winter,
        listed_price: 30,
        photos: 2
      })

    pants =
      item!(bag, %{
        category: "lapsed-puksid-luhikesed-puksid",
        brand: "H&M",
        size: "98",
        gender: :girl,
        season: :summer,
        listed_price: 6
      })

    hidden = item!(bag, %{brand: "Hiddenbrand", published: false})
    %{jacket: jacket, pants: pants, hidden: hidden}
  end

  describe "shop index (/)" do
    test "lists published available items only", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#shop-items article", "Reima")
      assert has_element?(view, "#items-#{ctx.jacket.id}")
      assert has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#items-#{ctx.hidden.id}")
      assert has_element?(view, "#shop-count", "2 eset")
      assert has_element?(view, "#shop-hero")
    end

    test "item cards link to the item page and use responsive images", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(#items-#{ctx.jacket.id} a[href="/p/#{ctx.jacket.slug}"]))
      assert has_element?(view, ~s(#items-#{ctx.jacket.id} img[loading="lazy"][srcset]))
    end

    test "search patches the URL and filters the grid", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#shop-search-form", %{"q" => "h&m"}) |> render_change()
      assert_patch(view, "/?q=h%26m")

      refute has_element?(view, "#items-#{ctx.jacket.id}")
      assert has_element?(view, "#items-#{ctx.pants.id}")
      assert has_element?(view, "#chip-q")
    end

    test "search params in the URL are applied on first load", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?season=summer&sort=price_asc")

      assert has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#items-#{ctx.jacket.id}")
      refute has_element?(view, "#shop-hero")
    end

    test "facet links toggle filters", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#season-winter") |> render_click()
      assert_patch(view, "/?season=winter")
      refute has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#facet-season")

      view |> element("#season-all") |> render_click()
      assert_patch(view, "/")
      assert has_element?(view, "#items-#{ctx.pants.id}")
    end

    test "season pills combine and persist when navigating categories", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?season=winter")

      view |> element("#season-summer") |> render_click()
      assert_patch(view, "/?season=winter%2Csummer")
      assert has_element?(view, "#items-#{ctx.pants.id}")
      assert has_element?(view, "#items-#{ctx.jacket.id}")

      view |> element("#category-link-lapsed-valisriided") |> render_click()
      assert_patch(view, "/k/valisriided?season=winter%2Csummer")
      assert has_element?(view, ~s(#breadcrumbs a[href="/?season=winter%2Csummer"]))
    end

    test "all_year items match every season", %{conn: conn} do
      all_year =
        item!(bag!(), %{season: :all_year, brand: "Zara", category: "lapsed-valisriided-jakid"})

      {:ok, view, _html} = live(conn, ~p"/?season=winter")
      assert has_element?(view, "#items-#{all_year.id}")
    end

    test "price filter and sort", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#shop-price-form", %{"max_price" => "10"}) |> render_submit()
      assert_patch(view, "/?max_price=10")
      refute has_element?(view, "#items-#{ctx.jacket.id}")

      view |> form("#shop-sort-form", %{"sort" => "price_desc"}) |> render_change()
      assert_patch(view, "/?max_price=10&sort=price_desc")
    end

    test "empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?q=nonexistentthing")
      assert has_element?(view, "#shop-empty")
    end

    test "invalid filter params are ignored", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/?gender=banana&sort=evil&min_price=abc")
      assert has_element?(view, "#items-#{ctx.jacket.id}")
    end

    test "sets SEO meta in the document head", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(property="og:title")
      assert html =~ ~s(<meta name="description")
      assert html =~ ~s(rel="canonical")
    end
  end

  describe "category pages (/k/*path)" do
    test "shows breadcrumbs without the audience and only items of the subtree",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/k/valisriided/jakid")

      assert has_element?(view, "#breadcrumbs")
      assert has_element?(view, ~s(#breadcrumbs a[href="/k/valisriided"]), "Välisriided")
      refute has_element?(view, "#breadcrumbs", "Lapsed")
      assert has_element?(view, "#items-#{ctx.jacket.id}")
      refute has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#shop-hero")
    end

    test "family page includes its types and expands them in the sidebar", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/k/valisriided")

      assert has_element?(view, "#items-#{ctx.jacket.id}")
      refute has_element?(view, "#items-#{ctx.pants.id}")
      assert has_element?(view, "#category-link-lapsed-valisriided-jakid")
      refute has_element?(view, "#category-link-lapsed-valisriided-vihmariided")
    end

    test "sidebar lists only families with items, flat on the front page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#category-link-lapsed-valisriided")
      assert has_element?(view, "#category-link-lapsed-puksid-luhikesed")
      refute has_element?(view, "#category-link-lapsed-valisriided-jakid")
      refute has_element?(view, "#category-link-lapsed-jalatsid")
      refute has_element?(view, "#audience-switcher")
    end

    test "no gender or age facets in the sidebar", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      refute has_element?(view, "#facet-gender")
      refute has_element?(view, "#facet-age_group")
      refute html =~ "Sugu"
      refute html =~ "Vanus"
    end

    test "navigating into a family patches", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#category-link-lapsed-puksid-luhikesed") |> render_click()
      assert_patch(view, "/k/puksid-luhikesed")
      refute has_element?(view, "#items-#{ctx.jacket.id}")
    end

    test "legacy URLs redirect to the new tree", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/k/valisriided/jakid"}}} =
               live(conn, ~p"/k/lapsed/poisid/talvejakid")

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/k/lapsed/poisid")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/k/lapsed")

      assert {:error, {:live_redirect, %{to: "/k/valisriided"}}} =
               live(conn, ~p"/k/lapsed/valisriided")
    end

    test "removed season leaves redirect to the type leaf and keep the query", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/k/valisriided/jakid?season=winter"}}} =
               live(conn, ~p"/k/valisriided/talvejakid?season=winter")

      assert {:error, {:live_redirect, %{to: "/k/kombinesoonid"}}} =
               live(conn, ~p"/k/kombinesoonid/vihmakombinesoonid")

      assert {:error, {:live_redirect, %{to: "/k/jalatsid/saapad"}}} =
               live(conn, ~p"/k/jalatsid/talvesaapad")
    end

    test "unknown category redirects to the shop", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/k/does/not/exist")
    end
  end

  describe "item page (/p/:slug)" do
    test "shows gallery, attributes, breadcrumbs and reserve button", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/p/#{ctx.jacket.slug}")

      assert has_element?(view, "#gallery-main")
      assert has_element?(view, "#gallery-thumbs #thumb-1")
      assert has_element?(view, "#item-attributes", "Reima")
      assert has_element?(view, "#item-price")
      assert has_element?(view, "#breadcrumbs")
      assert has_element?(view, ~s(#reserve-button[href="/checkout/#{ctx.jacket.slug}"]))
    end

    test "gallery thumbnails switch the main photo", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/p/#{ctx.jacket.slug}")
      before = view |> element("#gallery-main") |> render()

      view |> element("#thumb-1") |> render_click()
      refute view |> element("#gallery-main") |> render() == before
    end

    test "reserve navigates to the checkout", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/p/#{ctx.jacket.slug}")

      {:ok, _view, _html} =
        view |> element("#reserve-button") |> render_click() |> follow_redirect(conn)
    end

    test "sold items show no reserve button", %{conn: conn} = ctx do
      Kirbs.Resources.Item.update!(ctx.jacket, %{kirbs_status: :sold})
      {:ok, view, _html} = live(conn, ~p"/p/#{ctx.jacket.slug}")

      refute has_element?(view, "#reserve-button")
      assert has_element?(view, "#unavailable-notice")
    end

    test "unpublished and unknown slugs redirect to the shop", %{conn: conn} = ctx do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/p/#{ctx.hidden.slug || "x"}")
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/p/nope")
    end

    test "renders product SEO tags", %{conn: conn} = ctx do
      html = conn |> get(~p"/p/#{ctx.jacket.slug}") |> html_response(200)
      assert html =~ ~s(property="og:type" content="product")
      assert html =~ "application/ld+json"
      assert html =~ ~s(property="og:image")
    end
  end

  describe "sell page" do
    test "the old landing lives at /muuda", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/muuda")
      assert html =~ "Käed Vabad Kirbukas"
    end
  end
end
