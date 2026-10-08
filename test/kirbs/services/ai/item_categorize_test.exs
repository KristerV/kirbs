defmodule Kirbs.Services.Ai.ItemCategorizeTest do
  use Kirbs.DataCase, async: false

  import Kirbs.Test.CategorizeFixtures

  alias Kirbs.Resources.Category
  alias Kirbs.Services.Ai.ItemCategorize
  alias Kirbs.Test.StubCategorizeLlm

  setup do
    seed_categories()
    on_exit(&StubCategorizeLlm.reset/0)
    %{item: item_with_image()}
  end

  test "maps a valid response to category id and typed attributes", %{item: item} do
    StubCategorizeLlm.respond_with(llm_response("lapsed-valisriided-joped"))

    assert {:ok, result} = ItemCategorize.run(item)
    assert result.category_id == Category.get_by_slug!("lapsed-valisriided-joped").id
    assert result.age_group == :baby
    assert result.gender == :boy
    assert result.season == :winter
    assert result.condition == :good
    assert result.colors == ["Sinine"]
    assert result.brand == "H&M"
    assert result.confidence == 0.93
  end

  test "schema constrains category to leaf slugs and attributes to enums", %{item: item} do
    test_pid = self()

    StubCategorizeLlm.respond_with(fn images, prompt, schema ->
      send(test_pid, {:call, images, prompt, schema})
      {:ok, Jason.encode!(llm_response("lapsed-valisriided-joped"))}
    end)

    {:ok, _} = ItemCategorize.run(item)
    assert_received {:call, [_image], prompt, schema}

    slugs = schema["properties"]["category_slug"]["enum"]
    assert "lapsed-puksid-luhikesed-puksid" in slugs
    refute "lapsed" in slugs
    refute "lapsed-valisriided" in slugs
    assert "lapsed-kleidid-seelikud" in slugs
    assert "lapsed-muu" in slugs
    refute "naised" in slugs
    assert "baby" in schema["properties"]["age_group"]["enum"]
    assert prompt =~ "lapsed-puksid-luhikesed-puksid"
  end

  test "drops values outside the enums and rejects unknown categories", %{item: item} do
    StubCategorizeLlm.respond_with(
      llm_response("lapsed-jalatsid-tossud", %{
        "season" => "monsoon",
        "colors" => ["Sinine", "Tulevärv"],
        "confidence" => 7
      })
    )

    assert {:ok, result} = ItemCategorize.run(item)
    assert result.season == nil
    assert result.colors == ["Sinine"]
    assert result.confidence == 1.0

    StubCategorizeLlm.respond_with(llm_response("lapsed"))
    assert {:cancel, _} = ItemCategorize.run(item)
  end

  test "surfaces rate limiting and bad JSON", %{item: item} do
    StubCategorizeLlm.respond_with({:error, {:rate_limited, 30}})
    assert {:error, {:rate_limited, 30}} = ItemCategorize.run(item)

    StubCategorizeLlm.respond_with("not json")
    assert {:cancel, _} = ItemCategorize.run(item)
  end

  test "cancels when the item has no photos", %{item: item} do
    StubCategorizeLlm.respond_with(llm_response("lapsed-jalatsid-tossud"))
    {:ok, bare} = Kirbs.Resources.Item.create(%{bag_id: item.bag_id})
    assert {:cancel, _} = ItemCategorize.run(bare)
  end
end
