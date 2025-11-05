defmodule KirbsWeb.ItemLive.Split do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Item, Image}
  alias Kirbs.Services.ItemSplit

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item = Item.get!(id) |> Ash.load!([:bag])
    images = Image.list!() |> Enum.filter(&(&1.item_id == item.id)) |> Enum.sort_by(& &1.order)

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:images, images)
     |> assign(:selected_image_ids, MapSet.new())
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("toggle_image", %{"image_id" => image_id}, socket) do
    selected = socket.assigns.selected_image_ids

    new_selected =
      if MapSet.member?(selected, image_id) do
        MapSet.delete(selected, image_id)
      else
        MapSet.put(selected, image_id)
      end

    {:noreply, assign(socket, :selected_image_ids, new_selected) |> assign(:error, nil)}
  end

  @impl true
  def handle_event("split_item", _params, socket) do
    selected_count = MapSet.size(socket.assigns.selected_image_ids)
    total_count = length(socket.assigns.images)
    remaining_count = total_count - selected_count

    cond do
      selected_count == 0 ->
        {:noreply, assign(socket, :error, "Must select at least one image to move")}

      remaining_count == 0 ->
        {:noreply, assign(socket, :error, "Must leave at least one image in the original item")}

      true ->
        image_ids_to_move = MapSet.to_list(socket.assigns.selected_image_ids)

        case ItemSplit.run(socket.assigns.item.id, image_ids_to_move) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Item split successfully! AI processing has been scheduled for both items."
             )
             |> push_navigate(to: ~p"/bags/#{socket.assigns.item.bag_id}")}

          {:error, reason} ->
            {:noreply, assign(socket, :error, "Failed to split item: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/items/#{socket.assigns.item.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Split Item Images</h1>
          <.link navigate={~p"/items/#{@item.id}"} class="btn btn-ghost">
            Cancel
          </.link>
        </div>

        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Instructions</h2>
            <p class="text-base-content">
              Select the images you want to move to a new item. The selected images will be moved to a new item in the same bag.
              Both items will have their AI data cleared and AI processing will be scheduled automatically.
            </p>
            <div class="divider"></div>
            <div class="stats shadow stats-vertical sm:stats-horizontal">
              <div class="stat">
                <div class="stat-title">Total Images</div>
                <div class="stat-value text-2xl">{length(@images)}</div>
              </div>
              <div class="stat">
                <div class="stat-title">Selected to Move</div>
                <div class="stat-value text-2xl text-primary">{MapSet.size(@selected_image_ids)}</div>
              </div>
              <div class="stat">
                <div class="stat-title">Remaining in Original</div>
                <div class="stat-value text-2xl text-secondary">
                  {length(@images) - MapSet.size(@selected_image_ids)}
                </div>
              </div>
            </div>
            <%= if @error do %>
              <div class="alert alert-error mt-4">
                <span>{@error}</span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Select Images to Move</h2>
            <%= if @images == [] do %>
              <div class="alert alert-warning">
                <span>No photos for this item</span>
              </div>
            <% else %>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <%= for image <- @images do %>
                  <div class="relative group">
                    <label class="cursor-pointer">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-primary absolute top-2 left-2 z-10"
                        checked={MapSet.member?(@selected_image_ids, image.id)}
                        phx-click="toggle_image"
                        phx-value-image_id={image.id}
                      />
                      <div class={[
                        "aspect-square bg-base-200 rounded-lg overflow-hidden border-4 transition-all",
                        if(MapSet.member?(@selected_image_ids, image.id),
                          do: "border-primary",
                          else: "border-transparent"
                        )
                      ]}>
                        <img
                          src={"/uploads/#{image.path}"}
                          alt="Item photo"
                          class="w-full h-full object-cover"
                        />
                      </div>
                      <%= if image.is_label do %>
                        <div class="badge badge-primary badge-sm absolute top-2 right-2">
                          Label
                        </div>
                      <% end %>
                    </label>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <button class="btn btn-ghost" phx-click="cancel">
            Cancel
          </button>
          <button
            class="btn btn-primary"
            phx-click="split_item"
            disabled={
              MapSet.size(@selected_image_ids) == 0 or
                MapSet.size(@selected_image_ids) == length(@images)
            }
          >
            Split Item
          </button>
        </div>
      </div>
    </div>
    """
  end
end
