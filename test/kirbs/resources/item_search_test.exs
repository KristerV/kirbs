defmodule Kirbs.Resources.ItemSearchTest do
  use Kirbs.DataCase

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.Item

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
        description: "Soe talvejope"
      })

    pants =
      item!(bag, %{
        category: "lapsed-puksid-luhikesed-puksid",
        brand: "H&M",
        size: "98",
        gender: :girl,
        listed_price: 6,
        description: "Dressipüksid"
      })

    hidden = item!(bag, %{brand: "Reima", published: false})
    sold = item!(bag, %{brand: "Reima"}) |> Item.update!(%{kirbs_status: :sold})

    %{jacket: jacket, pants: pants, hidden: hidden, sold: sold}
  end

  defp ids(params), do: params |> Item.search!() |> Enum.map(& &1.id)

  test "only published, available items are listed", ctx do
    result = ids(%{})
    assert Enum.sort(result) == Enum.sort([ctx.jacket.id, ctx.pants.id])
    refute ctx.hidden.id in result
    refute ctx.sold.id in result
  end

  test "text search matches ignoring accents and prefixes", ctx do
    assert ids(%{q: "puksid"}) == [ctx.pants.id]
    assert ids(%{q: "reim"}) == [ctx.jacket.id]
  end

  test "synonyms expand the query", ctx do
    # "jakk" is a synonym of "jope" (jacket description says "talvejope" via category too)
    assert ctx.jacket.id in ids(%{q: "jakid"})
    refute ctx.pants.id in ids(%{q: "jakid"})
  end

  test "typos are tolerated via trigram similarity", ctx do
    assert ctx.pants.id in ids(%{q: "dressipuksid"})
    assert ctx.pants.id in ids(%{q: "dresipüksid"})
  end

  test "all words must match", ctx do
    assert ids(%{q: "reima talvejope"}) == [ctx.jacket.id]
    assert ids(%{q: "reima dressipüksid"}) == []
  end

  test "facet filters", ctx do
    assert ids(%{gender: :girl}) == [ctx.pants.id]
    assert ids(%{season: [:winter]}) == [ctx.jacket.id]
    assert ids(%{brand: "H&M"}) == [ctx.pants.id]
    assert ids(%{size: "110"}) == [ctx.jacket.id]
    assert ids(%{condition: :fair}) == []
  end

  test "season accepts a list and all_year items match every season", ctx do
    all_year = item!(bag!(), %{season: :all_year, category: "lapsed-jalatsid-saapad"})

    assert Enum.sort(ids(%{season: [:winter]})) == Enum.sort([ctx.jacket.id, all_year.id])
    assert ids(%{season: [:summer]}) == [all_year.id]

    assert Enum.sort(ids(%{season: [:summer, :winter]})) ==
             Enum.sort([ctx.jacket.id, all_year.id])
  end

  test "price range and sorting", ctx do
    assert ids(%{max_price: 10}) == [ctx.pants.id]
    assert ids(%{min_price: 10}) == [ctx.jacket.id]
    assert ids(%{sort: :price_asc}) == [ctx.pants.id, ctx.jacket.id]
    assert ids(%{sort: :price_desc}) == [ctx.jacket.id, ctx.pants.id]
  end

  test "category filter includes the whole subtree", ctx do
    assert ids(%{category: "lapsed"}) |> Enum.sort() == Enum.sort([ctx.jacket.id, ctx.pants.id])
    assert ids(%{category: "lapsed-valisriided"}) == [ctx.jacket.id]
    assert ids(%{category: "lapsed-puksid-luhikesed-puksid"}) == [ctx.pants.id]
    assert ids(%{category: "mehed"}) == []
  end

  test "facets count values with their own filter removed", ctx do
    facets = Item.facets!(%{brand: "H&M"})
    assert Enum.sort(facets.brand) == [{"H&M", 1}, {"Reima", 1}]
    refute Map.has_key?(facets, :gender)
    assert facets.size == [{"98", 1}]
    assert [{category_id, 1}] = facets.category_id
    assert category_id == ctx.pants.category_id
  end
end
