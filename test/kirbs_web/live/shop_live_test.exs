defmodule KirbsWeb.ShopLiveTest do
  use KirbsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Kirbs.ShopFixtures

  setup do
    seed_shop!()
    bag = bag!()

    jacket =
      item!(bag, %{
        category: "lapsed-poisid-talvejakid",
        brand: "Reima",
        size: "110",
        gender: :boy,
        listed_price: 30,
        photos: 2
      })

    pants =
      item!(bag, %{
        category: "lapsed-tudrukud-pusid",
        brand: "H&M",
        size: "98",
        gender: :girl,
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
      {:ok, view, _html} = live(conn, ~p"/?gender=girl&sort=price_asc")

      assert has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#items-#{ctx.jacket.id}")
      refute has_element?(view, "#shop-hero")
    end

    test "facet links toggle filters", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#facet-gender-boy") |> render_click()
      assert_patch(view, "/?gender=boy")
      refute has_element?(view, "#items-#{ctx.pants.id}")

      view |> element("#chip-gender") |> render_click()
      assert_patch(view, "/")
      assert has_element?(view, "#items-#{ctx.pants.id}")
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
    test "shows breadcrumbs and only items of the subtree", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/k/lapsed/poisid")

      assert has_element?(view, "#breadcrumbs")
      assert has_element?(view, ~s(#breadcrumbs a[href="/k/lapsed"]))
      assert has_element?(view, "#items-#{ctx.jacket.id}")
      refute has_element?(view, "#items-#{ctx.pants.id}")
      refute has_element?(view, "#shop-hero")
    end

    test "root category includes all children and offers subcategory navigation",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/k/lapsed")

      assert has_element?(view, "#items-#{ctx.jacket.id}")
      assert has_element?(view, "#items-#{ctx.pants.id}")
      assert has_element?(view, "#category-link-lapsed-poisid")
      assert has_element?(view, "#category-link-lapsed-tudrukud")
      refute has_element?(view, "#category-link-lapsed-beebid")
    end

    test "navigating into a subcategory patches", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/k/lapsed")

      view |> element("#category-link-lapsed-tudrukud") |> render_click()
      assert_patch(view, "/k/lapsed/tudrukud")
      refute has_element?(view, "#items-#{ctx.jacket.id}")
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

    test "reserve navigates to the checkout placeholder", %{conn: conn} = ctx do
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

  describe "checkout placeholder" do
    test "renders for a published item", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/checkout/#{ctx.jacket.slug}")
      assert has_element?(view, "#checkout-placeholder")
      assert has_element?(view, "#back-to-item")
    end
  end

  describe "sell page" do
    test "the old landing lives at /muuda", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/muuda")
      assert html =~ "Käed Vabad Kirbukas"
    end
  end
end
