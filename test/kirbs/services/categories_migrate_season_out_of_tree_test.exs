defmodule Kirbs.Services.Categories.MigrateSeasonOutOfTreeTest do
  use Kirbs.DataCase, async: false

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}
  alias Kirbs.Services.Categories.{MigrateSeasonOutOfTree, SeedTree}

  @old ~w(valisriided-talvejakid valisriided-uleminekujakid-vestid kombinesoonid-talvekombinesoonid
          kombinesoonid-vihmakombinesoonid jalatsid-talvesaapad)

  setup do
    {:ok, :seeded} = SeedTree.run()

    for path <- @old do
      [family | _] = String.split(path, "-", parts: 2)
      parent = Category.get_by_slug!("lapsed-#{family}")

      leaf =
        Category.upsert!(%{
          slug: "lapsed-#{path}",
          name_et: path,
          position: 9,
          parent_id: parent.id
        })

      YagaCategoryMapping.upsert!(%{category_id: leaf.id, yaga_category_id: 438})
    end

    %{bag: bag!()}
  end

  defp item_in(bag, slug, attrs \\ %{}) do
    Item.create!(
      Map.merge(
        %{
          bag_id: bag.id,
          category_id: Category.get_by_slug!(slug).id,
          brand: "Reima",
          status: :reviewed
        },
        attrs
      )
    )
  end

  defp slug_of(item), do: Category.get!(Item.get!(item.id).category_id).slug

  test "re-points by type, fills season without overriding, flags guesses", %{bag: bag} do
    winter_jacket = item_in(bag, "lapsed-valisriided-talvejakid")
    vest = item_in(bag, "lapsed-valisriided-uleminekujakid-vestid")
    kept = item_in(bag, "lapsed-jalatsid-talvesaapad", %{season: :all_year})
    rain = item_in(bag, "lapsed-kombinesoonid-vihmakombinesoonid")
    sandals = item_in(bag, "lapsed-jalatsid-sandaalid-sussid")

    proposal =
      CategorizationProposal.propose!(%{
        item_id: winter_jacket.id,
        category_id: Category.get_by_slug!("lapsed-kombinesoonid-talvekombinesoonid").id,
        confidence: 0.5
      })

    assert {:ok, summary} = MigrateSeasonOutOfTree.run()
    assert summary.items_moved == 4
    assert summary.proposals_moved == 1
    assert summary.unmapped == []
    assert length(summary.needs_review) == 2
    assert "lapsed-valisriided-talvejakid" in summary.deleted_categories

    assert slug_of(winter_jacket) == "lapsed-valisriided-joped"
    assert Item.get!(winter_jacket.id).season == :winter
    assert Item.get!(winter_jacket.id).search_text =~ "Joped"
    assert slug_of(vest) == "lapsed-valisriided-joped"
    assert Item.get!(vest.id).season == nil
    assert slug_of(kept) == "lapsed-jalatsid-saapad"
    assert Item.get!(kept.id).season == :all_year
    assert slug_of(rain) == "lapsed-kombinesoonid"
    assert Item.get!(sandals.id).season == :summer

    moved = CategorizationProposal.get!(proposal.id)
    assert Category.get!(moved.category_id).slug == "lapsed-kombinesoonid"
    assert moved.season == :winter

    for path <- @old, do: assert({:error, _} = Category.get_by_slug("lapsed-#{path}"))
  end

  test "is idempotent", %{bag: bag} do
    item_in(bag, "lapsed-valisriided-talvejakid")
    assert {:ok, %{items_moved: 1}} = MigrateSeasonOutOfTree.run()

    assert {:ok, %{items_moved: 0, season_filled: 0, deleted_categories: [], needs_review: []}} =
             MigrateSeasonOutOfTree.run()
  end
end
