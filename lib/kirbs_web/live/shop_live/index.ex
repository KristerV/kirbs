defmodule KirbsWeb.ShopLive.Index do
  @moduledoc """
  Public storefront: grid of available items with search, facet filters and category pages.
  Serves both `/` (:index) and `/k/*path` (:category). All state lives in the URL
  (`q`, facet params, `sort`), changed through `push_patch`.

  Funnel tracking: `shop_viewed` is fired by the `shop_visit` event (ShopVisit hook, once per
  browser session).
  """
  use KirbsWeb, :live_view

  import KirbsWeb.ShopComponents

  alias Kirbs.Resources.{Category, Item}
  alias KirbsWeb.Shop.{CategoryTree, Labels}

  @page_size 24
  @text_filters [:q, :brand, :size]
  @enum_filters [:condition]
  @season_pills [:winter, :spring_autumn, :summer]
  @sorts ~w(relevance newest price_asc price_desc)

  def mount(_params, _session, socket) do
    tree = CategoryTree.build(Category.list_all!())

    {:ok,
     socket
     |> assign(:tree, tree)
     |> assign(:category, nil)
     |> assign(:filters, %{})
     |> assign(:facets, empty_facets())
     |> assign(:category_counts, %{})
     |> assign(:total, 0)
     |> assign(:loaded, 0)
     |> assign(:more?, false)
     |> stream(:items, [])}
  end

  def handle_params(params, _uri, socket) do
    case resolve_category(socket.assigns.tree, params) do
      {:ok, category} ->
        filters = parse_filters(params)

        {:noreply,
         socket
         |> assign(:category, category)
         |> assign(:filters, filters)
         |> assign_forms()
         |> assign_facets()
         |> assign_meta()
         |> load_page(reset: true)}

      {:redirect, category} ->
        {:noreply,
         push_navigate(socket,
           to: shop_path(socket.assigns.tree, category, parse_filters(params))
         )}

      :not_found ->
        {:noreply,
         socket
         |> put_flash(:error, "Sellist kategooriat ei leitud")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Sent once per browser session by the ShopVisit hook (the funnel entry). The MetaPixel hook
  # already sends PageView on mount, so no second pixel event is pushed.
  def handle_event("shop_visit", _params, socket) do
    {:noreply, KirbsWeb.Track.event(socket, :shop_viewed, %{}, pixel: false)}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, patch_filters(socket, &put_or_drop(&1, :q, String.trim(q)))}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    {:noreply, patch_filters(socket, &put_or_drop(&1, :sort, valid_sort(sort)))}
  end

  def handle_event("price", %{"min_price" => min, "max_price" => max}, socket) do
    {:noreply,
     patch_filters(socket, fn filters ->
       filters
       |> put_or_drop(:min_price, valid_price(min))
       |> put_or_drop(:max_price, valid_price(max))
     end)}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_page(socket, reset: false)}
  end

  # --- data ---------------------------------------------------------------

  defp load_page(socket, reset: reset?) do
    %{filters: filters, category: category, loaded: loaded} = socket.assigns
    offset = if reset?, do: 0, else: loaded

    page =
      Item.search!(search_params(filters, category),
        page: [limit: @page_size, offset: offset, count: true],
        load: [:images, :category]
      )

    socket
    |> stream(:items, page.results, reset: reset?)
    |> assign(:total, page.count)
    |> assign(:loaded, offset + length(page.results))
    |> assign(:more?, page.more? == true)
  end

  defp assign_facets(socket) do
    %{filters: filters, category: category, tree: tree} = socket.assigns
    facets = Item.facets!(search_params(filters, category))

    socket
    |> assign(:facets, facets)
    |> assign(:category_counts, CategoryTree.rollup(tree, facets.category_id))
  end

  defp search_params(filters, category) do
    filters
    |> Map.new(fn {key, value} -> {key, value} end)
    |> then(&if(category, do: Map.put(&1, :category, category.slug), else: &1))
  end

  defp empty_facets do
    Map.new([:brand, :size, :season, :condition, :category_id], &{&1, []})
  end

  # --- params -------------------------------------------------------------

  defp resolve_category(tree, %{"path" => path}) when is_list(path) and path != [] do
    case CategoryTree.get_by_segments(tree, path) do
      nil -> resolve_legacy(tree, path)
      category -> canonical(tree, category, path)
    end
  end

  defp resolve_category(_tree, _params), do: {:ok, nil}

  # The default audience root is not a page of its own, and non-canonical spellings
  # (`/k/lapsed/valisriided`) redirect to the canonical URL.
  defp canonical(tree, category, path) do
    cond do
      category.slug == CategoryTree.default_root() -> {:redirect, nil}
      CategoryTree.segments(tree, category) == path -> {:ok, category}
      true -> {:redirect, category}
    end
  end

  defp resolve_legacy(tree, path) do
    case CategoryTree.legacy_category(tree, path) do
      {:ok, category} -> {:redirect, category}
      :error -> :not_found
    end
  end

  defp parse_filters(params) do
    text =
      for key <- @text_filters,
          value = blank_to_nil(params[Atom.to_string(key)]),
          into: %{},
          do: {key, String.slice(value, 0, 100)}

    enums =
      for key <- @enum_filters,
          atom = Labels.parse(key, params[Atom.to_string(key)]),
          into: %{},
          do: {key, atom}

    seasons =
      case parse_seasons(params["season"]) do
        [] -> %{}
        list -> %{season: list}
      end

    prices =
      for key <- [:min_price, :max_price],
          value = valid_price(params[Atom.to_string(key)]),
          into: %{},
          do: {key, value}

    sort =
      if params["sort"] in @sorts, do: %{sort: String.to_existing_atom(params["sort"])}, else: %{}

    text |> Map.merge(enums) |> Map.merge(seasons) |> Map.merge(prices) |> Map.merge(sort)
  end

  # `season=winter,summer` -> `[:winter, :summer]` (unknown values dropped, pill order).
  defp parse_seasons(value) when is_binary(value) do
    parsed = value |> String.split(",") |> Enum.map(&Labels.parse(:season, String.trim(&1)))
    Enum.filter([:winter, :spring_autumn, :summer, :all_year], &(&1 in parsed))
  end

  defp parse_seasons(_), do: []

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(_), do: nil

  defp valid_sort(sort) when sort in @sorts, do: String.to_existing_atom(sort)
  defp valid_sort(_), do: nil

  defp valid_price(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {%Decimal{} = price, ""} ->
        if Decimal.compare(price, 0) != :lt, do: Decimal.to_string(price, :normal), else: nil

      _ ->
        nil
    end
  end

  defp valid_price(_), do: nil

  defp put_or_drop(filters, key, nil), do: Map.delete(filters, key)
  defp put_or_drop(filters, key, ""), do: Map.delete(filters, key)
  defp put_or_drop(filters, key, value), do: Map.put(filters, key, value)

  defp patch_filters(socket, fun) do
    %{filters: filters, category: category, tree: tree} = socket.assigns
    push_patch(socket, to: shop_path(tree, category, fun.(filters)))
  end

  # --- view helpers -------------------------------------------------------

  defp assign_forms(socket) do
    filters = socket.assigns.filters
    default_sort = if filters[:q], do: :relevance, else: :newest

    socket
    |> assign(:search_form, to_form(%{"q" => filters[:q] || ""}, id: "shop-search"))
    |> assign(
      :sort_form,
      to_form(%{"sort" => to_string(filters[:sort] || default_sort)}, id: "shop-sort")
    )
    |> assign(
      :price_form,
      to_form(
        %{
          "min_price" => to_string(filters[:min_price] || ""),
          "max_price" => to_string(filters[:max_price] || "")
        },
        id: "shop-price"
      )
    )
  end

  defp assign_meta(socket) do
    %{category: category, filters: filters, tree: tree} = socket.assigns

    {title, description} =
      case category do
        nil ->
          {"Kirbs – kvaliteetsed kasutatud lasteriided",
           "Kvaliteetsed kasutatud lasteriided ja jalanõud soodsa hinnaga: jakid, püksid, kleidid, kombinesoonid ja palju muud. Ostes aitad riietel uue elu anda."}

        category ->
          {"#{category.name_et} – kasutatud lasteriided | Kirbs",
           "#{category.name_et}: kvaliteetsed kasutatud lasteriided soodsa hinnaga Kirbsi e-poes."}
      end

    path = shop_path(tree, category, %{})

    socket
    |> assign(:page_title, title)
    |> assign(:meta, %{
      description: description,
      path: path,
      robots: if(map_size(filters) > 0, do: "noindex,follow")
    })
  end

  @doc false
  def shop_path(tree, category, filters) do
    base =
      case category && CategoryTree.segments(tree, category) do
        segments when segments in [nil, []] -> ~p"/"
        segments -> ~p"/k/#{segments}"
      end

    query =
      filters
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), param_value(value)} end)
      |> Enum.sort()

    if query == [], do: base, else: base <> "?" <> URI.encode_query(query)
  end

  defp param_value(values) when is_list(values), do: Enum.map_join(values, ",", &to_string/1)
  defp param_value(value), do: to_string(value)

  # Season pills: each pill toggles its season, the rest of the selection stays.
  defp toggle_season(filters, season) do
    current = filters[:season] || []

    case if(season in current, do: List.delete(current, season), else: current ++ [season]) do
      [] -> Map.delete(filters, :season)
      list -> Map.put(filters, :season, list)
    end
  end

  # `[{season, label, count}]`; `all_year` items count towards every season.
  defp season_pills(facets) do
    counts = Map.new(facets.season)
    all_year = Map.get(counts, :all_year, 0)

    for season <- @season_pills do
      {season, Labels.label(:season, season), Map.get(counts, season, 0) + all_year}
    end
  end

  defp season_total(facets), do: facets.season |> Enum.map(&elem(&1, 1)) |> Enum.sum()

  defp toggle_filter(filters, key, value) do
    if to_string(filters[key]) == to_string(value),
      do: Map.delete(filters, key),
      else: Map.put(filters, key, value)
  end

  defp facet_links(facets, key, filters) do
    facets
    |> Map.fetch!(key)
    |> Enum.map(fn {value, count} -> {value, facet_label(key, value), count} end)
    |> ensure_active(key, filters)
  end

  defp ensure_active(links, key, filters) do
    case filters[key] do
      nil ->
        links

      active ->
        if Enum.any?(links, fn {value, _, _} -> to_string(value) == to_string(active) end),
          do: links,
          else: links ++ [{active, facet_label(key, active), 0}]
    end
  end

  defp facet_label(key, value) when key in @enum_filters, do: Labels.label(key, value)
  defp facet_label(_key, value), do: to_string(value)

  defp sorted_sizes(links) do
    Enum.sort_by(links, fn {_value, label, _count} ->
      case Integer.parse(label) do
        {int, _} -> {0, int, label}
        :error -> {1, 0, label}
      end
    end)
  end

  # Category navigation: families of the current audience (only those with items), the
  # children of the active family expanded. Returns `[{family, [child]}]`.
  defp category_nav(tree, category, counts) do
    audience = CategoryTree.audience(tree, category)
    active = category && active_family(tree, category)

    for family <- audience_children(tree, audience), visible?(family, category, counts) do
      children =
        if active && active.id == family.id,
          do: Enum.filter(CategoryTree.children(tree, family), &visible?(&1, category, counts)),
          else: []

      {family, children}
    end
  end

  defp audience_children(_tree, nil), do: []
  defp audience_children(tree, audience), do: CategoryTree.children(tree, audience)

  defp visible?(node, category, counts),
    do: Map.get(counts, node.id, 0) > 0 or (category != nil and node.id == category.id)

  # The family (level directly below the audience root) of a category.
  defp active_family(tree, category) do
    case CategoryTree.ancestors(tree, category) do
      [_root, family | _] -> family
      _ -> nil
    end
  end

  defp breadcrumb_trail(tree, category, filters) do
    chain = CategoryTree.trail(tree, category)
    last = length(chain) - 1

    crumbs =
      chain
      |> Enum.with_index()
      |> Enum.map(fn {node, index} ->
        {node.name_et,
         if(index == last, do: nil, else: shop_path(tree, node, Map.take(filters, [:season])))}
      end)

    [{"Pood", shop_path(tree, nil, Map.take(filters, [:season]))} | crumbs]
  end

  defp audience_path(tree, audience, filters) do
    case CategoryTree.default_root() == audience.slug do
      true -> shop_path(tree, nil, Map.take(filters, [:season]))
      false -> shop_path(tree, audience, Map.take(filters, [:season]))
    end
  end

  defp active_chips(filters) do
    for {key, value} <- Enum.sort(filters),
        key not in [:sort, :season],
        do: {key, chip_label(key, value)}
  end

  defp chip_label(:q, value), do: "„#{value}“"
  defp chip_label(:min_price, value), do: "alates #{value} €"
  defp chip_label(:max_price, value), do: "kuni #{value} €"
  defp chip_label(:brand, value), do: value
  defp chip_label(:size, value), do: "suurus #{value}"
  defp chip_label(key, value), do: Labels.label(key, value)

  defp sort_options(filters) do
    base = [
      {"Uuemad enne", "newest"},
      {"Odavamad enne", "price_asc"},
      {"Kallimad enne", "price_desc"}
    ]

    if filters[:q], do: [{"Sobivaim enne", "relevance"} | base], else: base
  end
end
