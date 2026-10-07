defmodule KirbsWeb.BackfillLiveTest do
  use KirbsWeb.ConnCase, async: false

  import Kirbs.Test.CategorizeFixtures
  import Phoenix.LiveViewTest

  alias Kirbs.Resources.{Category, CategorizationProposal, Item}
  alias Kirbs.Services.Backfill.CategorizeBatch
  alias Kirbs.Test.StubCategorizeLlm

  setup %{conn: conn} do
    seed_categories()
    on_exit(&StubCategorizeLlm.reset/0)

    user =
      Ash.create!(
        Kirbs.Accounts.User,
        %{
          email: "admin@example.com",
          password: "supersecret123",
          password_confirmation: "supersecret123"
        },
        action: :register_with_password,
        authorize?: false
      )

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)

    %{conn: conn}
  end

  defp propose(confidence, slug \\ "lapsed-valisriided-jakid") do
    item = item_with_image()
    StubCategorizeLlm.respond_with(llm_response(slug, %{"confidence" => confidence}))
    {:ok, _} = CategorizeBatch.run(limit: 1, after_id: nil)
    {item, CategorizationProposal.get_by_item!(item.id)}
  end

  test "requires login" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/backfill")
  end

  test "approve applies the proposal to the item", %{conn: conn} do
    {item, proposal} = propose(0.8)
    {:ok, view, _html} = live(conn, "/backfill")

    assert has_element?(view, "#proposals-#{proposal.id}")
    view |> element("#approve-#{proposal.id}") |> render_click()

    refute has_element?(view, "#proposals-#{proposal.id}")
    assert Item.get!(item.id).category_id == proposal.category_id
  end

  test "change category then approve uses the changed category", %{conn: conn} do
    {item, proposal} = propose(0.8)
    other = Category.get_by_slug!("lapsed-jalatsid-kummikud")
    {:ok, view, _html} = live(conn, "/backfill")

    view
    |> form("#change-#{proposal.id}", %{"category_id" => other.id})
    |> render_change()

    view |> element("#approve-#{proposal.id}") |> render_click()
    assert Item.get!(item.id).category_id == other.id
  end

  test "reject leaves the item uncategorized", %{conn: conn} do
    {item, proposal} = propose(0.8)
    {:ok, view, _html} = live(conn, "/backfill")

    view |> element("#reject-#{proposal.id}") |> render_click()
    assert is_nil(Item.get!(item.id).category_id)
    assert CategorizationProposal.get!(proposal.id).status == :rejected
  end

  test "apply all above threshold only applies confident proposals", %{conn: conn} do
    {high_item, high} = propose(0.97)
    {low_item, low} = propose(0.5)
    {:ok, view, _html} = live(conn, "/backfill")

    view |> form("#apply-above-form", %{"threshold" => "0.9"}) |> render_submit()

    assert Item.get!(high_item.id).category_id
    assert is_nil(Item.get!(low_item.id).category_id)
    refute has_element?(view, "#proposals-#{high.id}")
    assert has_element?(view, "#proposals-#{low.id}")
  end

  test "start dry run enqueues the backfill job", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/backfill")
    view |> element("#start-dry-run") |> render_click()

    assert [%{args: %{"apply" => false}}] =
             Oban.Testing.all_enqueued(repo: Kirbs.Repo, worker: Kirbs.Jobs.BackfillCategorizeJob)
  end
end
