defmodule KirbsWeb.ShopComponents do
  @moduledoc "Function components shared by the public storefront LiveViews."
  use KirbsWeb, :html

  alias KirbsWeb.ImageController
  alias KirbsWeb.Shop.Labels

  @doc "Customer-visible photos of an item (no label shots), cover first."
  def photos(%{images: images}) when is_list(images) do
    images |> Enum.reject(& &1.is_label) |> Enum.sort_by(& &1.order)
  end

  def photos(_item), do: []

  @doc "Space-separated `srcset` value covering all generated widths."
  def srcset(image) do
    Enum.map_join(ImageController.widths(), ", ", fn w -> "#{~p"/img/#{w}/#{image.id}"} #{w}w" end)
  end

  attr :image, :any, required: true
  attr :alt, :string, default: ""
  attr :sizes, :string, default: "(min-width: 1024px) 25vw, (min-width: 640px) 33vw, 50vw"
  attr :priority, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  def shop_image(assigns) do
    ~H"""
    <img
      src={~p"/img/640/#{@image.id}"}
      srcset={srcset(@image)}
      sizes={@sizes}
      alt={@alt}
      width="640"
      height="800"
      loading={if(@priority, do: "eager", else: "lazy")}
      fetchpriority={if(@priority, do: "high", else: "auto")}
      decoding="async"
      class={@class}
      {@rest}
    />
    """
  end

  attr :item, :map, required: true
  attr :id, :string, required: true

  def item_card(assigns) do
    assigns = assign(assigns, :cover, assigns.item |> photos() |> List.first())

    ~H"""
    <article id={@id} class="group relative">
      <.link navigate={~p"/p/#{@item.slug}"} class="block" aria-label={item_title(@item)}>
        <div class="relative aspect-[4/5] overflow-hidden rounded-2xl bg-orange-100/60 ring-1 ring-orange-900/5 transition duration-300 group-hover:-translate-y-1 group-hover:shadow-xl group-hover:shadow-orange-900/10">
          <.shop_image
            :if={@cover}
            image={@cover}
            alt={item_title(@item)}
            class="size-full object-cover transition duration-500 group-hover:scale-105"
          />
          <div :if={!@cover} class="flex size-full items-center justify-center text-orange-300">
            <.icon name="hero-photo" class="size-10" />
          </div>
          <span
            :if={@item.size}
            class="absolute left-2.5 top-2.5 rounded-full bg-white/90 px-2.5 py-1 text-xs font-bold text-stone-700 shadow-sm backdrop-blur"
          >
            {@item.size}
          </span>
          <span
            :if={@item.condition in [:new_with_tags, :like_new]}
            class="absolute right-2.5 top-2.5 rounded-full bg-emerald-500/90 px-2.5 py-1 text-xs font-bold text-white shadow-sm"
          >
            {Labels.label(:condition, @item.condition)}
          </span>
        </div>
        <div class="mt-3 flex items-start justify-between gap-3 px-0.5">
          <div class="min-w-0">
            <p class="truncate text-sm font-bold text-stone-900">
              {@item.brand || "Brändita"}
            </p>
            <p class="truncate text-sm text-stone-500">
              {(@item.category && @item.category.name_et) || @item.suggested_category}
            </p>
          </div>
          <p class="shrink-0 rounded-lg bg-orange-500 px-2 py-0.5 text-sm font-extrabold text-white">
            {Labels.price(@item.listed_price)}
          </p>
        </div>
      </.link>
    </article>
    """
  end

  @doc "Human title of an item, e.g. `Reima Talvejakid 104`."
  def item_title(item) do
    category = item.category && item.category.name_et

    [item.brand, category || item.suggested_category, item.size && "suurus #{item.size}"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  attr :crumbs, :list, required: true, doc: "list of {label, path | nil}; nil path = current page"

  def breadcrumbs(assigns) do
    ~H"""
    <nav id="breadcrumbs" aria-label="Asukoht" class="mb-5 text-sm text-stone-500">
      <ol class="flex flex-wrap items-center gap-x-1.5 gap-y-1">
        <%= for {{label, path}, index} <- Enum.with_index(@crumbs) do %>
          <li class="flex items-center gap-1.5">
            <.icon :if={index > 0} name="hero-chevron-right-micro" class="size-3.5 text-stone-300" />
            <%= if path do %>
              <.link navigate={path} class="transition-colors hover:text-orange-600">{label}</.link>
            <% else %>
              <span aria-current="page" class="font-semibold text-stone-800">{label}</span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end
end
