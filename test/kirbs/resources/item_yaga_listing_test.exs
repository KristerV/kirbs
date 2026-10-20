defmodule Kirbs.Resources.ItemYagaListingTest do
  use Kirbs.DataCase, async: false

  alias Kirbs.Resources.{Bag, Client, Item, YagaListing}

  setup do
    client =
      Ash.create!(Client, %{name: "Test", phone: "5551234", source: :direct}, authorize?: false)

    bag = Bag.create!(%{client_id: client.id})
    item = Item.create!(%{bag_id: bag.id, status: :reviewed})
    %{bag: bag, item: item}
  end

  test "new item has kirbs_status :available and no yaga listing", %{item: item} do
    assert item.kirbs_status == :available
    assert is_nil(item.yaga_listing_status)
    assert is_nil(item.yaga_slug)
  end

  test "reviewed item without listing is in upload queue; listed one is not", %{
    bag: bag,
    item: item
  } do
    assert [%{id: id}] = Item.list_reviewed_by_bag!(bag.id)
    assert id == item.id

    {:ok, _} = YagaListing.mark_listed(%{item_id: item.id, yaga_id: 1, yaga_slug: "abc"})
    assert [] = Item.list_reviewed_by_bag!(bag.id)

    item = Item.get!(item.id)
    assert item.yaga_listing_status == :listed
    assert item.yaga_slug == "abc"
    assert item.yaga_id == 1
    assert %DateTime{} = item.uploaded_at
  end

  test "mark_failed then mark_listed upserts a single listing", %{item: item} do
    {:ok, failed} = YagaListing.mark_failed(%{item_id: item.id, upload_error: "boom"})
    assert failed.status == :failed

    {:ok, listed} = YagaListing.mark_listed(%{item_id: item.id, yaga_id: 5, yaga_slug: "s"})
    assert listed.id == failed.id
    assert listed.status == :listed
    assert is_nil(listed.upload_error)
  end

  test "mark_sold and mark_unsold sync the listing status", %{item: item} do
    {:ok, _} = YagaListing.mark_listed(%{item_id: item.id, yaga_id: 1, yaga_slug: "abc"})

    {:ok, sold} =
      Item.mark_sold(item, %{sold_price: Decimal.new("5.00"), sold_at: DateTime.utc_now()})

    assert sold.status == :sold
    assert sold.yaga_listing_status == :sold

    {:ok, unsold} = Item.mark_unsold(sold)
    assert unsold.status == :reviewed
    assert unsold.yaga_listing_status == :listed
    assert is_nil(unsold.sold_at)
  end

  test "listed or sold items cannot be demoted via update", %{item: item} do
    {:ok, _} = YagaListing.mark_listed(%{item_id: item.id, yaga_id: 1, yaga_slug: "abc"})
    {:ok, updated} = Item.update(Item.get!(item.id), %{status: :pending})
    assert updated.status == :reviewed

    {:ok, sold} = Item.mark_sold(updated, %{sold_price: Decimal.new("1")})
    {:ok, still_sold} = Item.update(sold, %{status: :pending})
    assert still_sold.status == :sold
  end

  test "editing an item with a failed listing re-queues it", %{bag: bag, item: item} do
    {:ok, _} = YagaListing.mark_failed(%{item_id: item.id, upload_error: "boom"})
    assert [] = Item.list_reviewed_by_bag!(bag.id)

    {:ok, _} = Item.update(Item.get!(item.id), %{status: :reviewed, brand: "H&M"})
    assert [_] = Item.list_reviewed_by_bag!(bag.id)
  end

  test "typed attributes, search_text and publish", %{item: item} do
    {:ok, item} =
      Item.update(item, %{
        brand: "H&M",
        size: "74/80",
        age_group: :baby,
        gender: :unisex,
        season: :winter,
        condition: :good,
        parcel_size: :s,
        weight_grams: 300,
        colors: ["Sinine"]
      })

    assert item.search_text =~ "H&M"
    assert item.search_text =~ "Sinine"

    {:ok, published} = Item.publish(item)
    assert %DateTime{} = published.published_at
    assert published.slug =~ ~r/^h-m-74-80-[0-9a-f]{8}$/

    {:ok, again} = Item.publish(published)
    assert again.slug == published.slug
  end

  test "rejects invalid enum values", %{item: item} do
    assert {:error, _} = Item.update(item, %{season: :monsoon})
    assert {:error, _} = Item.update(item, %{parcel_size: :xl})
  end
end
