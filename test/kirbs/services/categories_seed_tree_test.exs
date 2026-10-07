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
    families = Category.list_children!(lapsed.id) |> Enum.map(& &1.slug)

    assert families ==
             ~w(lapsed-valisriided lapsed-kombinesoonid lapsed-puksid-luhikesed lapsed-ulaosad
                lapsed-kleidid-seelikud lapsed-oo-vabaaeg lapsed-jalatsid lapsed-aksessuaarid lapsed-muu)

    tossud = Category.get_by_slug!("lapsed-jalatsid-tossud")
    assert Category.get!(tossud.parent_id).slug == "lapsed-jalatsid"

    # families without types are leaves themselves
    assert Category.list_children!(Category.get_by_slug!("lapsed-kleidid-seelikud").id) == []
    assert Category.list_children!(Category.get_by_slug!("lapsed-muu").id) == []
  end

  test "maps leaf categories to Yaga categories" do
    {:ok, :seeded} = SeedTree.run()

    mapped = fn slug ->
      YagaCategoryMapping.get_by_category!(Category.get_by_slug!(slug).id).yaga_category_id
    end

    assert mapped.("lapsed-puksid-luhikesed-puksid") == 438
    assert mapped.("lapsed-kleidid-seelikud") == 438
    assert mapped.("lapsed-jalatsid-kummikud") == 370
    assert mapped.("lapsed-jalatsid-saapad") == 370
    assert mapped.("lapsed-jalatsid-kingad") == 370
    assert mapped.("lapsed-valisriided-jakid") == 438
    assert mapped.("lapsed-kombinesoonid") == 438
    assert mapped.("lapsed-aksessuaarid-muu") == 47
    assert mapped.("lapsed-muu") == 47
  end

  test "slug is unique" do
    {:ok, :seeded} = SeedTree.run()
    assert {:error, _} = Category.create(%{slug: "lapsed", name_et: "Dup"})
  end
end
