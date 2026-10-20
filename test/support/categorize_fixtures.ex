defmodule Kirbs.Test.CategorizeFixtures do
  @moduledoc "Builds items with a real image file on disk for categorization tests."

  alias Kirbs.Resources.{Bag, Client, Image, Item}

  def seed_categories, do: {:ok, :seeded} = Kirbs.Services.Categories.SeedTree.run()

  def item_with_image(attrs \\ %{}) do
    dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
    File.mkdir_p!(dir)
    path = "test-#{System.unique_integer([:positive])}.jpg"
    File.write!(Path.join(dir, path), <<255, 216, 255, 217>>)

    client =
      Ash.create!(
        Client,
        %{name: "Test #{System.unique_integer([:positive])}", phone: "5551234", source: :direct},
        authorize?: false
      )

    bag = Bag.create!(%{client_id: client.id})
    item = Item.create!(Map.merge(%{bag_id: bag.id, status: :ai_processed}, attrs))
    Image.create!(%{path: path, order: 0, bag_id: bag.id, item_id: item.id})
    item
  end

  def llm_response(slug, overrides \\ %{}) do
    Map.merge(
      %{
        "category_slug" => slug,
        "age_group" => "baby",
        "gender" => "boy",
        "season" => "winter",
        "condition" => "good",
        "colors" => ["Sinine"],
        "materials" => ["Puuvill"],
        "brand" => "H&M",
        "size" => "74/80",
        "confidence" => 0.93
      },
      overrides
    )
  end
end
