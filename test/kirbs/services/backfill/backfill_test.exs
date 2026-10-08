defmodule Kirbs.Services.Backfill.BackfillTest do
  use Kirbs.DataCase, async: false

  import Kirbs.Test.CategorizeFixtures

  alias Kirbs.Jobs.BackfillCategorizeJob
  alias Kirbs.Resources.{CategorizationProposal, Item}
  alias Kirbs.Services.Backfill.{ApplyProposal, ApplyProposalsAbove, CategorizeBatch}
  alias Kirbs.Test.StubCategorizeLlm

  setup do
    seed_categories()
    on_exit(&StubCategorizeLlm.reset/0)
    :ok
  end

  test "dry run stores proposals and leaves items untouched; rerun is idempotent" do
    item = item_with_image()
    StubCategorizeLlm.respond_with(llm_response("lapsed-valisriided-joped"))

    assert {:ok, %{proposed: 1, applied: 0, fetched: 1}} = CategorizeBatch.run()
    assert is_nil(Item.get!(item.id).category_id)
    assert %{status: :pending, confidence: 0.93} = CategorizationProposal.get_by_item!(item.id)

    assert {:ok, %{fetched: 0}} = CategorizeBatch.run()
    assert [_] = CategorizationProposal.list_pending!()
  end

  test "pending items are skipped" do
    _pending = item_with_image(%{status: :pending})
    StubCategorizeLlm.respond_with(llm_response("lapsed-valisriided-joped"))
    assert {:ok, %{fetched: 0}} = CategorizeBatch.run()
  end

  test "approving applies category, attributes and rebuilds search text" do
    item = item_with_image(%{brand: "Reima"})
    StubCategorizeLlm.respond_with(llm_response("lapsed-valisriided-joped"))
    {:ok, _} = CategorizeBatch.run()

    proposal = CategorizationProposal.get_by_item!(item.id)
    assert {:ok, updated} = ApplyProposal.run(proposal)

    assert updated.category_id == proposal.category_id
    assert updated.age_group == :baby
    # existing extraction wins, blanks are filled
    assert updated.brand == "Reima"
    assert updated.size == "74/80"
    assert updated.search_text =~ "Joped"
    assert CategorizationProposal.get!(proposal.id).status == :applied
  end

  test "apply: true only applies at or above the confidence threshold" do
    high = item_with_image()

    StubCategorizeLlm.respond_with(
      llm_response("lapsed-valisriided-joped", %{"confidence" => 0.95})
    )

    assert {:ok, %{applied: 1}} = CategorizeBatch.run(apply: true, min_confidence: 0.9)
    assert Item.get!(high.id).category_id

    low = item_with_image()

    StubCategorizeLlm.respond_with(
      llm_response("lapsed-valisriided-joped", %{"confidence" => 0.5})
    )

    assert {:ok, %{applied: 0, proposed: 1}} =
             CategorizeBatch.run(apply: true, min_confidence: 0.9)

    assert is_nil(Item.get!(low.id).category_id)
  end

  test "apply-all-above applies only confident pending proposals" do
    a = item_with_image()
    b = item_with_image()

    StubCategorizeLlm.respond_with(fn _, _, _ ->
      conf = if Process.get(:n, 0) == 0, do: 0.95, else: 0.4
      Process.put(:n, 1)
      {:ok, Jason.encode!(llm_response("lapsed-jalatsid-tossud", %{"confidence" => conf}))}
    end)

    {:ok, %{proposed: 2}} = CategorizeBatch.run()
    assert {:ok, %{applied: 1, failed: 0}} = ApplyProposalsAbove.run(0.9)

    assert Enum.count([a, b], &Item.get!(&1.id).category_id) == 1
    assert [%{confidence: low}] = CategorizationProposal.list_pending!()
    assert low < 0.9
  end

  test "failures are counted and rate limits halt the batch" do
    item_with_image()
    StubCategorizeLlm.respond_with("garbage")
    assert {:ok, %{failed: 1, proposed: 0}} = CategorizeBatch.run()

    StubCategorizeLlm.respond_with({:error, {:rate_limited, 10}})
    assert {:ok, %{rate_limited: 10}} = CategorizeBatch.run()
  end

  test "job chains the next batch until drained and snoozes on rate limit" do
    for _ <- 1..3, do: item_with_image()
    StubCategorizeLlm.respond_with(llm_response("lapsed-valisriided-joped"))

    assert :ok = perform_job(BackfillCategorizeJob, %{"limit" => 2})
    assert [%{args: %{"after_id" => after_id}}] = all_enqueued(BackfillCategorizeJob)

    assert :ok = perform_job(BackfillCategorizeJob, %{"limit" => 2, "after_id" => after_id})
    assert length(CategorizationProposal.list_pending!()) == 3

    StubCategorizeLlm.respond_with({:error, {:rate_limited, 5}})
    item_with_image()
    assert {:snooze, 65} = perform_job(BackfillCategorizeJob, %{})
  end

  defp perform_job(worker, args), do: Oban.Testing.perform_job(worker, args, repo: Kirbs.Repo)
  defp all_enqueued(worker), do: Oban.Testing.all_enqueued(repo: Kirbs.Repo, worker: worker)

  test "proposal stores extras and waterproof; approving writes them to the item" do
    item = item_with_image()

    StubCategorizeLlm.respond_with(
      llm_response("lapsed-valisriided-joped", %{
        "extra_category_slugs" => ["lapsed-valisriided-valipuksid"],
        "waterproof" => true
      })
    )

    {:ok, _} = CategorizeBatch.run()
    proposal = CategorizationProposal.get_by_item!(item.id)
    valipuksid = Kirbs.Resources.Category.get_by_slug!("lapsed-valisriided-valipuksid")
    assert proposal.extra_category_ids == [valipuksid.id]
    assert proposal.waterproof
    assert is_nil(Item.get!(item.id).category_id)

    assert {:ok, updated} = ApplyProposal.run(proposal)
    assert updated.waterproof
    assert updated.search_text =~ "Välipüksid"
    assert updated.search_text =~ "veekindel"

    assert [%{id: id}] = Ash.load!(updated, :extra_categories).extra_categories
    assert id == valipuksid.id
  end
end
