defmodule Kirbs.Services.Shop.SeedDevItems do
  @moduledoc """
  Dev-only: creates a handful of published, available shop items with generated placeholder
  photos so the storefront can be viewed locally. Idempotent (skips if the dev client exists).
  """

  alias Kirbs.Resources.{Bag, Category, Client, Image, Item}

  @client_name "Dev Shop Seller"

  # {category slug, brand, size, colors, description, price, age_group, gender, season, condition, rgb}
  @items [
    {"lapsed-valisriided-joped", "Reima", "104", ["sinine"],
     "Soe veekindel talvejope, kapuutsiga.", 24, :child, :boy, :winter, :good, [60, 110, 180]},
    {"lapsed-kleidid-seelikud", "H&M", "92", ["roosa"], "Kerge suvekleit lillemustriga.", 8,
     :toddler, :girl, :summer, :like_new, [235, 140, 170]},
    {"lapsed-kombinesoonid", "Lindex", "68", ["hall"], "Pehme fliisist kombinesoon beebile.", 12,
     :baby, :unisex, :winter, :good, [170, 170, 175]},
    {"lapsed-puksid-luhikesed-puksid", "Zara", "122", ["must"],
     "Dressipüksid taskutega, mugav lõige.", 7, :child, :boy, :all_year, :good, [40, 40, 45]},
    {"lapsed-ulaosad-dressipluusid-kampsunid", "Name It", "110", ["kollane"],
     "Kampsun kapuutsiga, mõnus ja soe.", 10, :child, :girl, :spring_autumn, :like_new,
     [240, 200, 70]},
    {"lapsed-ulaosad-t-sargid-pluusid", "Coccodrillo", "98", ["roheline"],
     "T-särk dinosauruse printiga.", 5, :toddler, :boy, :summer, :new_with_tags, [90, 160, 100]},
    {"lapsed-oo-vabaaeg-pidzaamad", "Pippi", "74", ["valge"], "Puuvillane pidžaama tähemustriga.",
     9, :baby, :unisex, :all_year, :good, [235, 235, 240]},
    {"lapsed-jalatsid-tossud", "Superfit", "27", ["lilla"], "Kvaliteetsed sügisesaapad.", 18,
     :toddler, :girl, :spring_autumn, :fair, [150, 110, 190]},
    {"lapsed-aksessuaarid-mutsid-sallid", "Reima", "52", ["punane"],
     "Talvemüts ja sall komplektis.", 6, :child, :boy, :winter, :good, [200, 60, 60]},
    {"lapsed-valisriided-joped", "Mini A Ture", "116", ["beež"], "Kaunis kevadjope, peaaegu uus.",
     16, :child, :girl, :spring_autumn, :like_new, [210, 180, 140]}
  ]

  def run do
    with {:ok, :absent} <- check_not_seeded(),
         {:ok, client} <- Client.create(%{name: @client_name, email: "dev-shop@example.com"}),
         {:ok, bag} <- Bag.create(%{client_id: client.id}),
         {:ok, items} <- create_items(bag) do
      {:ok, items}
    else
      {:ok, :present} -> {:ok, []}
      error -> error
    end
  end

  defp check_not_seeded do
    case Client.find_by_name(@client_name) do
      {:ok, %Client{}} -> {:ok, :present}
      _ -> {:ok, :absent}
    end
  end

  defp create_items(bag) do
    items =
      Enum.map(@items, fn {slug, brand, size, colors, description, price, age, gender, season,
                           condition, rgb} ->
        category = Category.get_by_slug!(slug)

        item =
          Item.create!(%{
            bag_id: bag.id,
            category_id: category.id,
            brand: brand,
            size: size,
            colors: colors,
            description: description,
            listed_price: price,
            age_group: age,
            gender: gender,
            season: season,
            condition: condition,
            status: :reviewed
          })

        create_images!(item, rgb)
        Item.publish!(item)
      end)

    {:ok, items}
  end

  defp create_images!(item, [r, g, b]) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
    File.mkdir_p!(upload_dir)

    for {shade, order} <- Enum.with_index([0, 35]) do
      filename = "#{item.id}_seed_#{order}.jpg"

      {:ok, canvas} = Vix.Vips.Operation.black(800, 1000, bands: 3)

      {:ok, tinted} =
        Vix.Vips.Operation.linear(canvas, [1.0, 1.0, 1.0], [r + shade, g + shade, b + shade])

      {:ok, tinted} = Vix.Vips.Operation.cast(tinted, :VIPS_FORMAT_UCHAR)
      :ok = Vix.Vips.Image.write_to_file(tinted, Path.join(upload_dir, filename))

      Image.create!(%{path: filename, order: order, item_id: item.id})
    end
  end
end
