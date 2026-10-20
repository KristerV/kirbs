defmodule Kirbs.Services.Categories.MigrateVihmariidedToValipuksidTest do
  use Kirbs.DataCase, async: false

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}
  alias Kirbs.Services.Categories.{MigrateVihmariidedToValipuksid, SeedTree}

  @old "lapsed-valisriided-vihmariided"

  setup do
    {:ok, :seeded} = SeedTree.run()
    parent = Category.get_by_slug!("lapsed-valisriided")

    old =
      Category.upsert!(%{slug: @old, name_et: "Vihmariided", position: 9, parent_id: parent.id})

    YagaCategoryMapping.upsert!(%{category_id: old.id, yaga_category_id: 438})
    %{old: old, bag: bag!()}
  end

  test "seeded tree has Valipuksid after Vestid and a Yaga mapping", _ctx do
    valis = Category.get_by_slug!("lapsed-valisriided")
    kids = valis.id |> Category.list_children!() |> Enum.reject(&(&1.slug == @old))

    assert Enum.map(kids, & &1.slug) ==
             ~w(lapsed-valisriided-joped lapsed-valisriided-vestid lapsed-valisriided-valipuksid)

    valipuksid = Category.get_by_slug!("lapsed-valisriided-valipuksid")
    assert YagaCategoryMapping.get_by_category!(valipuksid.id).yaga_category_id == 438
  end

  test "moves items and proposals to joped, sets waterproof, flags all for review", ctx do
    item =
      Item.create!(%{
        bag_id: ctx.bag.id,
        category_id: ctx.old.id,
        brand: "Reima",
        status: :reviewed
      })

    proposal =
      CategorizationProposal.propose!(%{
        item_id: item.id,
        category_id: ctx.old.id,
        confidence: 0.5
      })

    assert {:ok, summary} = MigrateVihmariidedToValipuksid.run()
    assert summary.items_moved == 1
    assert summary.proposals_moved == 1
    assert summary.deleted_categories == [@old]
    assert [%{items: [id], proposals: 1}] = summary.needs_review
    assert id == item.id

    moved = Item.get!(item.id)
    assert Category.get!(moved.category_id).slug == "lapsed-valisriided-joped"
    assert moved.waterproof
    assert moved.search_text =~ "Joped"
    assert moved.search_text =~ "veekindel"

    moved_proposal = CategorizationProposal.get!(proposal.id)
    assert Category.get!(moved_proposal.category_id).slug == "lapsed-valisriided-joped"
    assert moved_proposal.waterproof

    assert {:error, _} = Category.get_by_slug(@old)
    assert {:ok, nil} = YagaCategoryMapping.get_by_category(ctx.old.id, not_found_error?: false)
  end

  test "is idempotent" do
    assert {:ok, _} = MigrateVihmariidedToValipuksid.run()

    assert {:ok, %{items_moved: 0, needs_review: [], deleted_categories: []}} =
             MigrateVihmariidedToValipuksid.run()
  end
end
