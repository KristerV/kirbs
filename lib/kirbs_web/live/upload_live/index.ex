defmodule KirbsWeb.UploadLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Bag
  alias Kirbs.Resources.Item

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:selected, MapSet.new()) |> load_next_bag()}
  end

  @impl true
  def handle_event("update_price", %{"item-id" => item_id, "value" => price}, socket) do
    price_overrides = Map.put(socket.assigns.price_overrides, item_id, price)
    {:noreply, assign(socket, :price_overrides, price_overrides)}
  end

  @impl true
  def handle_event("upload_all", _params, socket) do
    has_empty =
      Enum.any?(socket.assigns.items, fn item ->
        case socket.assigns.price_overrides[item.id] do
          "" -> true
          nil -> is_nil(item.listed_price)
          _ -> false
        end
      end)

    if has_empty do
      {:noreply, put_flash(socket, :error, "All items must have a listed price.")}
    else
      bag = socket.assigns.bag

      for item <- socket.assigns.items do
        maybe_update_price(item, socket.assigns.price_overrides[item.id])

        %{item_id: item.id}
        |> Kirbs.Jobs.UploadItemJob.new()
        |> Oban.insert()
      end

      {:noreply,
       socket
       |> load_next_bag()
       |> put_flash(:info, "Bag ##{bag.number} queued for upload!")}
    end
  end

  @impl true
  def handle_event("toggle_select", %{"id" => item_id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, item_id) do
        MapSet.delete(socket.assigns.selected, item_id)
      else
        MapSet.put(socket.assigns.selected, item_id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  @impl true
  def handle_event("link_combination", _params, socket) do
    group = Ash.UUID.generate()

    for item <- socket.assigns.items,
        MapSet.member?(socket.assigns.selected, item.id) do
      Item.update(item, %{combination_group: group})
    end

    {:noreply, socket |> assign(:selected, MapSet.new()) |> reload_items()}
  end

  @impl true
  def handle_event("unlink_combination", %{"group" => group}, socket) do
    for item <- socket.assigns.items,
        item.combination_group == group do
      Item.update(item, %{combination_group: nil})
    end

    {:noreply, reload_items(socket)}
  end

  defp reload_items(socket) do
    case socket.assigns.bag do
      nil -> socket
      bag -> assign(socket, :items, Item.list_reviewed_by_bag!(bag.id))
    end
  end

  defp load_next_bag(socket) do
    case Bag.get_first_bag_ready_for_upload!() do
      [] ->
        socket
        |> assign(:bag, nil)
        |> assign(:items, [])
        |> assign(:price_overrides, %{})
        |> assign(:selected, MapSet.new())

      [bag] ->
        items = Item.list_reviewed_by_bag!(bag.id)

        socket
        |> assign(:bag, bag)
        |> assign(:items, items)
        |> assign(:price_overrides, %{})
        |> assign(:selected, MapSet.new())
    end
  end

  defp maybe_update_price(_item, nil), do: :ok

  defp maybe_update_price(item, price) do
    case Decimal.parse(price) do
      {decimal, _} ->
        if Decimal.compare(decimal, item.listed_price || Decimal.new(0)) != :eq do
          Item.update(item, %{listed_price: decimal})
        end

      :error ->
        :ok
    end
  end

  defp first_non_label_image(item) do
    Enum.find(item.images, fn img -> !img.is_label end)
  end

  defp combination_groups(items) do
    items
    |> Enum.filter(& &1.combination_group)
    |> Enum.group_by(& &1.combination_group)
  end

  @group_colors ~w(border-primary border-secondary border-accent border-info border-success border-warning)

  defp group_border_class(nil, _items), do: ""

  defp group_border_class(group, items) do
    groups =
      items
      |> Enum.map(& &1.combination_group)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    idx = Enum.find_index(groups, &(&1 == group)) || 0
    Enum.at(@group_colors, rem(idx, length(@group_colors)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Upload to Yaga</h1>
          <%= if @bag do %>
            <button class="btn btn-primary" phx-click="upload_all">
              Upload All ({length(@items)})
            </button>
          <% end %>
        </div>

        <%= if is_nil(@bag) do %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body text-center">
              <p class="text-lg">All items uploaded!</p>
              <div class="mt-4">
                <.link navigate={~p"/review"} class="btn btn-primary">
                  Review More Items
                </.link>
              </div>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body py-4">
              <h2 class="card-title">Bag #{@bag.number}</h2>
              <%= if @bag.client do %>
                <p>{@bag.client.name} — {@bag.client.phone}</p>
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-2 mb-4">
            <button
              class="btn btn-sm btn-outline"
              phx-click="link_combination"
              disabled={MapSet.size(@selected) < 2}
            >
              Link combination ({MapSet.size(@selected)})
            </button>
            <%= for {group, _items} <- combination_groups(@items) do %>
              <button
                class={"btn btn-sm btn-outline #{group_border_class(group, @items)}"}
                phx-click="unlink_combination"
                phx-value-group={group}
              >
                Unlink
              </button>
            <% end %>
          </div>

          <div class="flex flex-col gap-4 items-center">
            <%= for item <- @items do %>
              <div class={"card card-side bg-base-100 shadow-xl items-center w-fit border-2 #{group_border_class(item.combination_group, @items)}"}>
                <div class="flex items-center pl-2">
                  <input
                    type="checkbox"
                    class="checkbox"
                    checked={MapSet.member?(@selected, item.id)}
                    phx-click="toggle_select"
                    phx-value-id={item.id}
                  />
                </div>
                <.link navigate={~p"/items/#{item.id}"}>
                  <% img = first_non_label_image(item) %>
                  <%= if img do %>
                    <figure class="w-40 h-40 shrink-0">
                      <img
                        src={"/uploads/#{img.path}"}
                        alt="Item"
                        class="w-full h-full object-cover"
                      />
                    </figure>
                  <% else %>
                    <figure class="w-40 h-40 shrink-0 bg-base-200 flex items-center justify-center">
                      <span class="text-sm">No photo</span>
                    </figure>
                  <% end %>
                </.link>
                <div class="card-body py-4 justify-center gap-1">
                  <p>{item.brand || "—"}</p>
                  <p>{item.size || "—"}</p>
                  <p>{Enum.join(item.materials || [], ", ")}</p>
                  <p>
                    AI:
                    <%= if item.ai_suggested_price do %>
                      {item.ai_suggested_price}€
                    <% else %>
                      —
                    <% end %>
                  </p>
                  <div class="flex items-center gap-2">
                    <input
                      type="number"
                      step="0.01"
                      class="input input-bordered input-sm w-24"
                      value={Map.get(@price_overrides, item.id, item.listed_price)}
                      phx-blur="update_price"
                      phx-value-item-id={item.id}
                    /> €
                  </div>
                  <%= if item.combination_group do %>
                    <span class={"badge badge-sm #{group_border_class(item.combination_group, @items)}"}>
                      combo
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <div class="flex justify-end mt-6">
            <button class="btn btn-primary" phx-click="upload_all">
              Upload All ({length(@items)})
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
