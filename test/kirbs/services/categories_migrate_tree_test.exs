defmodule Kirbs.Services.Categories.MigrateTreeTest do
  use Kirbs.DataCase, async: false

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}
  alias Kirbs.Services.Categories.{MigrateTree, SeedTree}

  setup do
    {:ok, :seeded} = SeedTree.run()
    lapsed = Category.get_by_slug!("lapsed")

    for {group, name} <- [{"poisid", "Poisid"}, {"tudrukud", "Tüdrukud"}, {"beebid", "Beebid"}] do
      g =
        Category.upsert!(%{
          slug: "lapsed-#{group}",
          name_et: name,
          position: 9,
          parent_id: lapsed.id
        })

      for type <- ~w(pusid kingad kombinesoonid) do
        leaf =
          Category.upsert!(%{
            slug: "lapsed-#{group}-#{type}",
            name_et: type,
            position: 0,
            parent_id: g.id
          })

        YagaCategoryMapping.upsert!(%{category_id: leaf.id, yaga_category_id: 438})
      end
    end

    %{bag: bag!()}
  end

  defp old_item(bag, slug, attrs \\ %{}) do
    category = Category.get_by_slug!(slug)

    Item.create!(
      Map.merge(
        %{bag_id: bag.id, category_id: category.id, brand: "Reima", status: :reviewed},
        attrs
      )
    )
  end

  test "re-points items by type, fills gender/age, deletes obsolete categories", %{bag: bag} do
    boy = old_item(bag, "lapsed-poisid-pusid")
    girl = old_item(bag, "lapsed-tudrukud-kingad", %{gender: :unisex})
    baby = old_item(bag, "lapsed-beebid-kombinesoonid")

    proposal =
      CategorizationProposal.propose!(%{
        item_id: baby.id,
        category_id: Category.get_by_slug!("lapsed-beebid-kombinesoonid").id,
        confidence: 0.5
      })

    assert {:ok, summary} = MigrateTree.run()
    assert summary.items_moved == 3
    assert summary.proposals_moved == 1
    assert summary.unmapped == []
    assert length(summary.needs_review) == 2
    assert "lapsed-poisid-pusid" in summary.deleted_categories

    boy = Item.get!(boy.id)
    assert Category.get!(boy.category_id).slug == "lapsed-puksid-luhikesed-puksid"
    assert boy.gender == :boy
    assert boy.search_text =~ "Püksid"

    girl = Item.get!(girl.id)
    assert Category.get!(girl.category_id).slug == "lapsed-jalatsid-tossud"
    assert girl.gender == :unisex

    baby = Item.get!(baby.id)
    assert Category.get!(baby.category_id).slug == "lapsed-kombinesoonid-talvekombinesoonid"
    assert baby.age_group == :baby

    assert Category.get!(CategorizationProposal.get!(proposal.id).category_id).slug ==
             "lapsed-kombinesoonid-talvekombinesoonid"

    for slug <- ~w(lapsed-poisid lapsed-tudrukud lapsed-beebid lapsed-beebid-kingad) do
      assert {:error, _} = Category.get_by_slug(slug)
    end
  end

  test "is idempotent", %{bag: bag} do
    old_item(bag, "lapsed-poisid-pusid")
    assert {:ok, %{items_moved: 1}} = MigrateTree.run()
    assert {:ok, %{items_moved: 0, deleted_categories: []}} = MigrateTree.run()
  end

  test "keeps and reports old leaves with an unknown type", %{bag: bag} do
    group = Category.get_by_slug!("lapsed-poisid")

    odd =
      Category.upsert!(%{
        slug: "lapsed-poisid-weird",
        name_et: "Weird",
        position: 5,
        parent_id: group.id
      })

    item = old_item(bag, "lapsed-poisid-weird")

    assert {:ok, summary} = MigrateTree.run()
    assert summary.unmapped == ["lapsed-poisid-weird"]
    assert Item.get!(item.id).category_id == odd.id
    assert {:ok, _} = Category.get_by_slug("lapsed-poisid")
  end
end
