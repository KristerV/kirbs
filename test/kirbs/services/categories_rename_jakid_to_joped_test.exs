defmodule Kirbs.Services.Categories.RenameJakidToJopedTest do
  use Kirbs.DataCase, async: false

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Category, Item, YagaCategoryMapping}
  alias Kirbs.Services.Categories.{RenameJakidToJoped, SeedTree}

  setup do
    {:ok, :seeded} = SeedTree.run()
    parent = Category.get_by_slug!("lapsed-valisriided")

    old =
      Category.upsert!(%{
        slug: "lapsed-valisriided-jakid",
        name_et: "Jakid",
        position: 9,
        parent_id: parent.id
      })

    YagaCategoryMapping.upsert!(%{category_id: old.id, yaga_category_id: 438})
    %{old: old, bag: bag!()}
  end

  test "re-points items, rebuilds search_text, deletes the old category and mapping", ctx do
    item =
      Item.create!(%{
        bag_id: ctx.bag.id,
        category_id: ctx.old.id,
        brand: "Reima",
        status: :reviewed
      })

    assert {:ok, summary} = RenameJakidToJoped.run()
    assert summary.items_moved == 1
    assert summary.deleted_categories == ["lapsed-valisriided-jakid"]

    moved = Item.get!(item.id)
    assert Category.get!(moved.category_id).slug == "lapsed-valisriided-joped"
    assert moved.search_text =~ "Joped"
    assert {:error, _} = Category.get_by_slug("lapsed-valisriided-jakid")
  end

  test "is idempotent" do
    assert {:ok, _} = RenameJakidToJoped.run()
    assert {:ok, %{items_moved: 0, deleted_categories: []}} = RenameJakidToJoped.run()
  end
end
