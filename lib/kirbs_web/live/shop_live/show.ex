defmodule KirbsWeb.ShopLive.Show do
  @moduledoc """
  Public item page `/p/:slug`: photo gallery, attributes, breadcrumbs and a "Broneeri"
  (reserve) button that leads to the checkout (`/checkout/:slug`).

  Funnel tracking: `item_viewed` in `mount/3`.
  """
  use KirbsWeb, :live_view

  import KirbsWeb.ShopComponents

  alias Kirbs.Resources.{Category, Item}
  alias KirbsWeb.Shop.{CategoryTree, Labels}

  def mount(%{"slug" => slug}, _session, socket) do
    case Item.get_published_by_slug(slug, not_found_error?: false) do
      {:ok, %Item{} = item} ->
        {:ok,
         socket
         |> assign(:item, item)
         |> assign(:current, 0)
         |> assign_page(item)
         |> track_view(item)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Seda toodet ei leitud")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("select_photo", %{"index" => index}, socket) do
    max = length(socket.assigns.photos) - 1

    case Integer.parse(index) do
      {i, ""} when i >= 0 and i <= max -> {:noreply, assign(socket, :current, i)}
      _ -> {:noreply, socket}
    end
  end

  defp track_view(socket, item) do
    KirbsWeb.Track.event(socket, :item_viewed, %{
      item_id: item.id,
      content_ids: [item.id],
      content_name: item_title(item),
      value: item.listed_price && Decimal.to_float(item.listed_price),
      currency: "EUR"
    })
  end

  defp assign_page(socket, item) do
    photos = photos(item)
    tree = CategoryTree.build(Category.list_all!())
    title = item_title(item)

    socket
    |> assign(:photos, photos)
    |> assign(:crumbs, crumbs(tree, item))
    |> assign(:attributes, attributes(item))
    |> assign(:available?, item.kirbs_status == :available)
    |> assign(:page_title, "#{title} | Kirbs")
    |> assign(:meta, %{
      description: description(item, title),
      path: ~p"/p/#{item.slug}",
      image: photos |> List.first() |> then(&(&1 && ~p"/img/1280/#{&1.id}")),
      type: "product",
      jsonld: jsonld(item, title, photos)
    })
  end

  defp crumbs(tree, item) do
    trail =
      case item.category && CategoryTree.get(tree, item.category.id) do
        nil ->
          []

        category ->
          for node <- CategoryTree.trail(tree, category) do
            {node.name_et, ~p"/k/#{CategoryTree.segments(tree, node)}"}
          end
      end

    last = Enum.join(Enum.reject([item.brand, item.size], &(&1 in [nil, ""])), " ")
    [{"Pood", ~p"/"}] ++ trail ++ [{if(last == "", do: "Toode", else: last), nil}]
  end

  defp attributes(item) do
    [
      {"Bränd", item.brand},
      {"Suurus", item.size},
      {"Vanus", Labels.label(:age_group, item.age_group)},
      {"Sugu", Labels.label(:gender, item.gender)},
      {"Hooaeg", Labels.label(:season, item.season)},
      {"Värv", item.colors && Enum.join(item.colors, ", ")},
      {"Materjal", item.materials && Enum.join(item.materials, ", ")}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  defp description(item, title) do
    [title, item.description, Labels.price(item.listed_price)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
    |> String.slice(0, 200)
  end

  defp jsonld(item, title, photos) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => title,
      "description" => item.description || title,
      "brand" => item.brand && %{"@type" => "Brand", "name" => item.brand},
      "image" => Enum.map(photos, &KirbsWeb.SeoComponents.absolute(~p"/img/1280/#{&1.id}")),
      "itemCondition" => "https://schema.org/UsedCondition",
      "offers" => %{
        "@type" => "Offer",
        "url" => KirbsWeb.SeoComponents.absolute(~p"/p/#{item.slug}"),
        "priceCurrency" => "EUR",
        "price" => item.listed_price && Decimal.to_string(item.listed_price, :normal),
        "availability" =>
          if(item.kirbs_status == :available,
            do: "https://schema.org/InStock",
            else: "https://schema.org/SoldOut"
          )
      }
    }
  end
end
