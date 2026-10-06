defmodule Kirbs.Services.Categories.SeedTreeTest do
  use Kirbs.DataCase, async: false

  alias Kirbs.Resources.{Category, YagaCategoryMapping}
  alias Kirbs.Services.Categories.SeedTree

  test "seeds the Lapsed tree and stub roots idempotently" do
    assert {:ok, :seeded} = SeedTree.run()
    count = length(Category.list_all!())
    assert {:ok, :seeded} = SeedTree.run()
    assert length(Category.list_all!()) == count

    roots = Category.list_roots!() |> Enum.map(& &1.slug)
    assert Enum.sort(roots) == Enum.sort(~w(lapsed naised mehed kodu mangud))

    lapsed = Category.get_by_slug!("lapsed")
    groups = Category.list_children!(lapsed.id) |> Enum.map(& &1.name_et)
    assert groups == ["Beebid", "Poisid", "Tüdrukud"]

    kingad = Category.get_by_slug!("lapsed-poisid-kingad")
    assert Category.get!(kingad.parent_id).slug == "lapsed-poisid"
  end

  test "maps leaf categories to Yaga categories" do
    {:ok, :seeded} = SeedTree.run()
    pusid = Category.get_by_slug!("lapsed-poisid-pusid")
    kingad = Category.get_by_slug!("lapsed-poisid-kingad")

    assert %{yaga_category_id: 438} = YagaCategoryMapping.get_by_category!(pusid.id)
    assert %{yaga_category_id: 370} = YagaCategoryMapping.get_by_category!(kingad.id)
  end

  test "slug is unique" do
    {:ok, :seeded} = SeedTree.run()
    assert {:error, _} = Category.create(%{slug: "lapsed", name_et: "Dup"})
  end
end
