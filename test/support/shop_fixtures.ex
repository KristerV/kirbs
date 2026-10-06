defmodule Kirbs.ShopFixtures do
  @moduledoc "Helpers to create published shop items (with a real photo) in tests."

  alias Kirbs.Resources.{Bag, Category, Client, Image, Item}

  def seed_shop! do
    {:ok, :seeded} = Kirbs.Services.Categories.SeedTree.run()
    {:ok, _} = Kirbs.Services.Search.SeedSynonyms.run()
    :ok
  end

  def bag! do
    client = Client.create!(%{name: "Fixture Seller #{System.unique_integer([:positive])}"})
    Bag.create!(%{client_id: client.id})
  end

  @doc """
  Creates and publishes an item. Options: `:category` (slug, default `lapsed-poisid-pusid`),
  `:photos` (count, default 1), `:published` (default true), plus any Item attribute.
  """
  def item!(bag, attrs \\ %{}) do
    {slug, attrs} = Map.pop(attrs, :category, "lapsed-poisid-pusid")
    {photos, attrs} = Map.pop(attrs, :photos, 1)
    {published?, attrs} = Map.pop(attrs, :published, true)
    category = Category.get_by_slug!(slug)

    params =
      Map.merge(
        %{
          bag_id: bag.id,
          category_id: category.id,
          brand: "Reima",
          size: "104",
          description: "Hea seisukorras",
          listed_price: 12,
          status: :reviewed,
          condition: :good
        },
        attrs
      )

    item = Item.create!(params)
    for order <- 0..(photos - 1)//1, do: photo!(item, order)
    if published?, do: Item.publish!(item), else: item
  end

  def photo!(item, order) do
    dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
    File.mkdir_p!(dir)
    filename = "#{item.id}_fixture_#{order}.jpg"
    {:ok, img} = Vix.Vips.Operation.black(400, 500, bands: 3)
    {:ok, img} = Vix.Vips.Operation.linear(img, [1.0, 1.0, 1.0], [200.0, 120.0, 60.0])
    {:ok, img} = Vix.Vips.Operation.cast(img, :VIPS_FORMAT_UCHAR)
    :ok = Vix.Vips.Image.write_to_file(img, Path.join(dir, filename))
    Image.create!(%{path: filename, order: order, item_id: item.id})
  end
end
