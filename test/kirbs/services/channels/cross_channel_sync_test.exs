defmodule Kirbs.Services.Channels.CrossChannelSyncTest do
  use Kirbs.DataCase, async: false
  use Oban.Testing, repo: Kirbs.Repo

  alias Kirbs.Jobs.DelistFromYagaJob
  alias Kirbs.Resources.{Bag, Client, Item, YagaListing}
  alias Kirbs.Services.Channels.{MarkSoldOnKirbs, PublishReviewedToShop, RepairKirbsStatus}

  setup do
    client = Client.create!(%{name: "Sync Seller", phone: "5551234", source: :direct})
    bag = Bag.create!(%{client_id: client.id})
    item = Item.create!(%{bag_id: bag.id, status: :reviewed, listed_price: 12})
    {:ok, _} = YagaListing.mark_listed(%{item_id: item.id, yaga_id: 7, yaga_slug: "abc"})
    %{bag: bag, item: Item.get!(item.id)}
  end

  describe "Item.mark_sold / mark_unsold keep kirbs_status in sync" do
    test "a Yaga sale hides the item from the shop", %{item: item} do
      {:ok, sold} =
        Item.mark_sold(item, %{sold_price: Decimal.new("10"), sold_at: DateTime.utc_now()})

      assert sold.status == :sold
      assert sold.kirbs_status == :sold
      assert sold.sales_channel == :yaga
      assert YagaListing.get_by_item!(item.id).status == :sold
    end

    test "mark_unsold makes it available again", %{item: item} do
      {:ok, sold} = Item.mark_sold(item, %{sold_price: Decimal.new("10")})
      {:ok, unsold} = Item.mark_unsold(sold)

      assert unsold.kirbs_status == :available
      assert unsold.sales_channel == :yaga
      assert unsold.status == :reviewed
    end
  end

  describe "MarkSoldOnKirbs" do
    test "marks sold on the kirbs channel and queues the Yaga delisting", %{item: item} do
      assert {:ok, sold} = MarkSoldOnKirbs.run(%{item_id: item.id, sold_price: Decimal.new("12")})

      assert sold.status == :sold
      assert sold.kirbs_status == :sold
      assert sold.sales_channel == :kirbs
      assert_enqueued(worker: DelistFromYagaJob, args: %{item_id: item.id})

      # the Yaga listing stays live until delisted by hand
      assert YagaListing.get_by_item!(item.id).status == :listed
    end

    test "the job puts the listing in the manual delisting queue until marked delisted", %{
      item: item
    } do
      {:ok, _} = MarkSoldOnKirbs.run(%{item_id: item.id, sold_price: Decimal.new("12")})
      assert [] = YagaListing.list_needing_delist!()

      assert :ok = perform_job(DelistFromYagaJob, %{item_id: item.id})
      assert [%{item_id: id} = listing] = YagaListing.list_needing_delist!()
      assert id == item.id

      {:ok, _} = YagaListing.mark_delisted(listing)
      assert [] = YagaListing.list_needing_delist!()
    end

    test "refuses an already sold item", %{item: item} do
      {:ok, _} = MarkSoldOnKirbs.run(%{item_id: item.id, sold_price: Decimal.new("12")})

      assert {:error, :already_sold} =
               MarkSoldOnKirbs.run(%{item_id: item.id, sold_price: Decimal.new("12")})
    end

    test "an item without a Yaga listing needs no delisting", %{bag: bag} do
      other = Item.create!(%{bag_id: bag.id, status: :reviewed})
      {:ok, _} = MarkSoldOnKirbs.run(%{item_id: other.id, sold_price: Decimal.new("5")})
      assert :ok = perform_job(DelistFromYagaJob, %{item_id: other.id})
      assert [] = YagaListing.list_needing_delist!()
    end

    test "refunding (mark_unsold) takes it out of the queue and back into the shop", %{item: item} do
      {:ok, sold} = MarkSoldOnKirbs.run(%{item_id: item.id, sold_price: Decimal.new("12")})
      :ok = perform_job(DelistFromYagaJob, %{item_id: item.id})
      {:ok, _} = Item.mark_unsold(sold)

      assert [] = YagaListing.list_needing_delist!()
      assert Item.get!(item.id).kirbs_status == :available
    end
  end

  describe "RepairKirbsStatus" do
    test "aligns kirbs_status with status in both directions", %{bag: bag, item: item} do
      stale_sold = Item.create!(%{bag_id: bag.id, status: :sold, sold_price: 5})
      stale_available = Item.create!(%{bag_id: bag.id, status: :reviewed, kirbs_status: :sold})
      assert stale_sold.kirbs_status == :available

      assert {:ok, %{marked_sold: 1, marked_available: 1}} = RepairKirbsStatus.run()
      assert Item.get!(stale_sold.id).kirbs_status == :sold
      assert Item.get!(stale_available.id).kirbs_status == :available
      assert Item.get!(item.id).kirbs_status == :available

      assert {:ok, %{marked_sold: 0, marked_available: 0}} = RepairKirbsStatus.run()
    end
  end

  describe "PublishReviewedToShop" do
    test "publishes reviewed items with category and price, skips the rest", %{bag: bag} do
      Kirbs.ShopFixtures.seed_shop!()
      category = Kirbs.Resources.Category.get_by_slug!("lapsed-puksid-luhikesed-puksid")

      ok =
        Item.create!(%{
          bag_id: bag.id,
          status: :reviewed,
          listed_price: 9,
          category_id: category.id
        })

      no_category = Item.create!(%{bag_id: bag.id, status: :reviewed, listed_price: 9})

      assert {:ok, %{published: 1, skipped: 2}} = PublishReviewedToShop.run(bag.id)
      assert Item.get!(ok.id).published_at
      assert Item.get!(ok.id).slug
      assert is_nil(Item.get!(no_category.id).published_at)

      assert {:ok, %{published: 0, skipped: 2}} = PublishReviewedToShop.run(bag.id)
    end
  end
end
