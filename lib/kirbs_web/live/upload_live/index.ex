defmodule KirbsWeb.UploadLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Item

  @impl true
  def mount(_params, _session, socket) do
    items = Item.list_reviewed!()

    {:ok,
     socket
     |> assign(:items, items)
     |> assign(:price_overrides, %{})}
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
      for item <- socket.assigns.items do
        maybe_update_price(item, socket.assigns.price_overrides[item.id])

        %{item_id: item.id}
        |> Kirbs.Jobs.UploadItemJob.new()
        |> Oban.insert()
      end

      items = Item.list_reviewed!()

      {:noreply,
       socket
       |> assign(:items, items)
       |> assign(:price_overrides, %{})
       |> put_flash(:info, "All items queued for upload!")}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Upload to Yaga</h1>
          <%= if @items != [] do %>
            <button class="btn btn-primary" phx-click="upload_all">
              Upload All ({length(@items)})
            </button>
          <% end %>
        </div>

        <%= if @items == [] do %>
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
          <div class="flex flex-col gap-4 items-center">
            <%= for item <- @items do %>
              <div class="card card-side bg-base-100 shadow-xl items-center w-fit">
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
