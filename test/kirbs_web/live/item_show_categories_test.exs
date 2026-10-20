defmodule KirbsWeb.ItemShowCategoriesTest do
  use KirbsWeb.ConnCase, async: false

  import Kirbs.Test.CategorizeFixtures
  import Phoenix.LiveViewTest

  alias Kirbs.Resources.{Category, Item}

  setup %{conn: conn} do
    seed_categories()

    user =
      Ash.create!(
        Kirbs.Accounts.User,
        %{
          email: "admin@example.com",
          password: "supersecret123",
          password_confirmation: "supersecret123"
        },
        action: :register_with_password,
        authorize?: false
      )

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn, item: item_with_image()}
  end

  test "renders grouped category select and saves category + attributes", %{
    conn: conn,
    item: item
  } do
    kingad = Category.get_by_slug!("lapsed-jalatsid-tossud")
    {:ok, view, _html} = live(conn, "/items/#{item.id}")

    assert has_element?(
             view,
             "#shop-attributes #item-category-id optgroup[label='Jalatsid']"
           )

    view
    |> form("#item-form", %{
      "item" => %{
        "category_id" => kingad.id,
        "age_group" => "child",
        "gender" => "girl",
        "season" => "summer",
        "condition" => "like_new"
      }
    })
    |> render_submit()

    saved = Item.get!(item.id)
    assert saved.category_id == kingad.id
    assert saved.age_group == :child
    assert saved.gender == :girl
    assert saved.season == :summer
    assert saved.condition == :like_new
    assert saved.search_text =~ "Tossud"
  end

  test "blank option clears the category", %{conn: conn, item: item} do
    kingad = Category.get_by_slug!("lapsed-jalatsid-tossud")
    Item.apply_categorization!(item, %{category_id: kingad.id})
    {:ok, view, _html} = live(conn, "/items/#{item.id}")

    view |> form("#item-form", %{"item" => %{"category_id" => ""}}) |> render_submit()
    assert is_nil(Item.get!(item.id).category_id)
  end

  test "extra categories checkbox list and waterproof save, primary is not selectable", %{
    conn: conn,
    item: item
  } do
    joped = Category.get_by_slug!("lapsed-valisriided-joped")
    valipuksid = Category.get_by_slug!("lapsed-valisriided-valipuksid")
    Item.apply_categorization!(item, %{category_id: joped.id})
    {:ok, view, _html} = live(conn, "/items/#{item.id}")

    assert has_element?(view, "#item-extra-categories-#{valipuksid.id}")
    assert has_element?(view, "#item-extra-categories-#{joped.id}[disabled]")

    view
    |> form("#item-form", %{
      "item" => %{"extra_category_ids" => [valipuksid.id], "waterproof" => "true"}
    })
    |> render_submit()

    saved = Item.get!(item.id) |> Ash.load!(:extra_categories)
    assert Enum.map(saved.extra_categories, & &1.id) == [valipuksid.id]
    assert saved.waterproof
    assert saved.search_text =~ "Välipüksid"
    assert has_element?(view, "#item-extra-categories-#{valipuksid.id}[checked]")

    # unchecking everything clears the extras
    view |> form("#item-form", %{"item" => %{"extra_category_ids" => [""]}}) |> render_submit()
    assert Ash.load!(Item.get!(item.id), :extra_categories).extra_categories == []
  end
end
