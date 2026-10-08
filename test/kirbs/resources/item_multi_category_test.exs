defmodule Kirbs.Resources.ItemMultiCategoryTest do
  use Kirbs.DataCase

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Category, Item, ItemCategory}

  setup do
    seed_shop!()
    bag = bag!()

    set =
      item!(bag, %{category: "lapsed-valisriided-joped", brand: "Reima", description: "Komplekt"})

    pants = item!(bag, %{category: "lapsed-valisriided-valipuksid", brand: "Didriks"})
    vest = item!(bag, %{category: "lapsed-valisriided-vestid", brand: "Zara"})
    other = item!(bag, %{category: "lapsed-jalatsid-saapad", brand: "Viking"})

    %{
      set: set,
      pants: pants,
      vest: vest,
      other: other,
      joped: cat("lapsed-valisriided-joped"),
      valipuksid: cat("lapsed-valisriided-valipuksid"),
      vestid: cat("lapsed-valisriided-vestid"),
      valis: cat("lapsed-valisriided")
    }
  end

  defp cat(slug), do: Category.get_by_slug!(slug)
  defp ids(params), do: params |> Item.search!() |> Enum.map(& &1.id) |> Enum.sort()

  defp extras(item),
    do: item.id |> Item.get!() |> Ash.load!(:extra_categories) |> Map.fetch!(:extra_categories)

  describe "set_extra_categories" do
    test "replaces the set and rebuilds search_text", ctx do
      {:ok, item} = Item.set_extra_categories(ctx.set, [ctx.valipuksid.id])
      assert item.search_text =~ "Välipüksid"
      assert Enum.map(extras(ctx.set), & &1.id) == [ctx.valipuksid.id]

      {:ok, item} = Item.set_extra_categories(item, [ctx.vestid.id])
      assert Enum.map(extras(ctx.set), & &1.id) == [ctx.vestid.id]
      refute item.search_text =~ "Välipüksid"

      {:ok, item} = Item.set_extra_categories(item, [])
      assert extras(ctx.set) == []
      refute item.search_text =~ "Vestid"
    end

    test "rejects non-leaf, primary and duplicate extras", ctx do
      assert {:error, _} = Item.set_extra_categories(ctx.set, [ctx.valis.id])
      assert {:error, _} = Item.set_extra_categories(ctx.set, [ctx.joped.id])
      assert {:error, _} = Item.set_extra_categories(ctx.set, [ctx.vestid.id, ctx.vestid.id])
      assert extras(ctx.set) == []
    end

    test "a family without children counts as a leaf", ctx do
      kombe = cat("lapsed-kombinesoonid")
      assert {:ok, _} = Item.set_extra_categories(ctx.set, [kombe.id])
    end

    test "the join table has a unique index per item and category", ctx do
      {:ok, _} = Item.set_extra_categories(ctx.set, [ctx.vestid.id])
      assert {:error, _} = ItemCategory.create(%{item_id: ctx.set.id, category_id: ctx.vestid.id})
    end

    test "changing the primary to a current extra drops that extra", ctx do
      {:ok, item} = Item.set_extra_categories(ctx.set, [ctx.valipuksid.id, ctx.vestid.id])
      {:ok, item} = Item.update(item, %{category_id: ctx.valipuksid.id})

      assert Enum.map(extras(item), & &1.id) == [ctx.vestid.id]
      assert item.search_text =~ "Välipüksid"
    end

    test "deleting the item removes its extras", ctx do
      bare = item!(bag!(), %{photos: 0, published: false})
      {:ok, _} = Item.set_extra_categories(bare, [ctx.vestid.id])
      assert [_] = ItemCategory.list_by_item!(bare.id)
      Item.destroy!(Item.get!(bare.id))
      assert ItemCategory.list_by_item!(bare.id) == []
    end

    test "apply_categorization stores extras, nil keeps them", ctx do
      {:ok, item} =
        Item.apply_categorization(ctx.set, %{extra_category_ids: [ctx.valipuksid.id]})

      assert Enum.map(extras(item), & &1.id) == [ctx.valipuksid.id]

      {:ok, item} = Item.apply_categorization(item, %{season: :winter})
      assert Enum.map(extras(item), & &1.id) == [ctx.valipuksid.id]
    end
  end

  describe "search and facets match primary or extras" do
    setup ctx do
      {:ok, set} = Item.set_extra_categories(ctx.set, [ctx.valipuksid.id, ctx.vestid.id])
      %{set: set}
    end

    test "category filter is subtree-aware over extras", ctx do
      assert ids(%{category: "lapsed-valisriided-valipuksid"}) ==
               Enum.sort([ctx.set.id, ctx.pants.id])

      assert ids(%{category: "lapsed-valisriided-joped"}) == [ctx.set.id]
      # in the family through three leaves, but listed once
      assert ids(%{category: "lapsed-valisriided"}) ==
               Enum.sort([ctx.set.id, ctx.pants.id, ctx.vest.id])

      assert ids(%{category: "lapsed-jalatsid"}) == [ctx.other.id]
    end

    test "text search finds the extra category names", ctx do
      assert ctx.set.id in ids(%{q: "välipüksid"})
    end

    test "category facet counts distinct items per leaf and per family", ctx do
      facets = Item.facets!(%{})
      leaf = Map.new(facets.category_id)
      rollup = Map.new(facets.category_rollup)

      assert leaf[ctx.joped.id] == 1
      assert leaf[ctx.valipuksid.id] == 2
      assert leaf[ctx.vestid.id] == 2
      # set (3 leaves of the family) + pants + vest = 3 distinct items, not 5
      assert rollup[ctx.valis.id] == 3
      assert rollup[cat("lapsed").id] == 3 + 1
    end

    test "category facet ignores the category filter but respects the others", ctx do
      facets = Item.facets!(%{category: "lapsed-valisriided-joped", brand: "Reima"})
      rollup = Map.new(facets.category_rollup)
      assert rollup[ctx.valipuksid.id] == 1
      assert rollup[ctx.vestid.id] == 1
    end
  end

  describe "waterproof" do
    test "defaults to false, filters and counts, lands in search_text", ctx do
      refute ctx.set.waterproof
      {:ok, wet} = Item.update(ctx.pants, %{waterproof: true})
      assert wet.search_text =~ "veekindel"

      assert ids(%{waterproof: true}) == [ctx.pants.id]
      assert length(ids(%{waterproof: false})) == 4
      assert ctx.pants.id in ids(%{q: "veekindel"})

      assert Map.new(Item.facets!(%{}).waterproof) == %{true => 1, false => 3}

      # the waterproof facet ignores its own filter, but respects the others
      assert Map.new(Item.facets!(%{waterproof: true}).waterproof) == %{true => 1, false => 3}
      assert Map.new(Item.facets!(%{brand: "Zara"}).waterproof) == %{false => 1}
    end
  end
end
