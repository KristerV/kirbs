defmodule KirbsWeb.BagLive.Capture do
  use KirbsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:phase, :bag_photos)
     |> assign(:bag_step, 1)
     |> assign(:bag_photos, [])
     |> assign(:current_bag, nil)
     |> assign(:current_item, nil)
     |> assign(:current_item_photos, [])
     |> assign(:all_items, [])}
  end

  @impl true
  def handle_event("capture_bag_photo", %{"photo" => photo}, socket) do
    bag_photos = socket.assigns.bag_photos ++ [photo]
    bag_step = socket.assigns.bag_step + 1

    socket =
      if bag_step > 3 do
        # All 3 bag photos captured, create bag and move to item phase
        {:ok, bag} = create_bag_with_photos(bag_photos)

        socket
        |> assign(:phase, :item_photos)
        |> assign(:current_bag, bag)
        |> create_new_item()
      else
        socket
        |> assign(:bag_photos, bag_photos)
        |> assign(:bag_step, bag_step)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("capture_item_photo", %{"photo" => photo}, socket) do
    current_item_photos = socket.assigns.current_item_photos ++ [photo]

    {:noreply, assign(socket, :current_item_photos, current_item_photos)}
  end

  @impl true
  def handle_event("next_item", _params, socket) do
    socket =
      with true <- length(socket.assigns.current_item_photos) > 0,
           {:ok, item} <- save_current_item(socket) do
        all_items = socket.assigns.all_items ++ [item]

        socket
        |> assign(:all_items, all_items)
        |> create_new_item()
      else
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("end_bag", _params, socket) do
    socket =
      if length(socket.assigns.current_item_photos) > 0 do
        {:ok, item} = save_current_item(socket)
        assign(socket, :all_items, socket.assigns.all_items ++ [item])
      else
        socket
      end

    # TODO: Trigger AI processing jobs here

    {:noreply, redirect(socket, to: ~p"/bags")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white">
      <%= if @phase == :bag_photos do %>
        <div class="container mx-auto p-4">
          <h1 class="text-2xl font-bold mb-4">
            <%= bag_step_title(@bag_step) %>
          </h1>

          <div class="mb-4">
            <p class="text-lg">Step {@bag_step} of 3</p>
          </div>

          <div class="space-y-4">
            <div class="bg-gray-800 p-8 rounded-lg">
              <p class="text-center text-gray-400">Camera view would go here</p>
              <p class="text-center text-sm text-gray-500 mt-2">
                (Will implement camera capture component)
              </p>
            </div>

            <button
              phx-click="capture_bag_photo"
              phx-value-photo="dummy_photo_data"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
            >
              Capture
            </button>
          </div>

          <%= if length(@bag_photos) > 0 do %>
            <div class="mt-4 grid grid-cols-3 gap-2">
              <%= for {_photo, idx} <- Enum.with_index(@bag_photos) do %>
                <div class="bg-gray-700 p-2 rounded">
                  <p class="text-xs text-center">Photo {idx + 1}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="container mx-auto p-4">
          <h1 class="text-2xl font-bold mb-4">
            Item <%= length(@all_items) + 1 %> - Take Photos
          </h1>

          <div class="mb-4">
            <p class="text-sm text-gray-400">
              Current item: <%= length(@current_item_photos) %> photo(s)
            </p>
            <p class="text-sm text-gray-400">Total items: <%= length(@all_items) %></p>
          </div>

          <div class="space-y-4">
            <div class="bg-gray-800 p-8 rounded-lg">
              <p class="text-center text-gray-400">Camera view would go here</p>
              <p class="text-center text-sm text-gray-500 mt-2">
                (Will implement camera capture component)
              </p>
            </div>

            <button
              phx-click="capture_item_photo"
              phx-value-photo="dummy_photo_data"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
            >
              Capture
            </button>

            <div class="grid grid-cols-2 gap-4">
              <button
                phx-click="next_item"
                class="bg-green-600 hover:bg-green-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
              >
                Next Item
              </button>

              <button
                phx-click="end_bag"
                class="bg-red-600 hover:bg-red-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
              >
                End Bag
              </button>
            </div>
          </div>

          <%= if length(@current_item_photos) > 0 do %>
            <div class="mt-4">
              <p class="text-sm mb-2">Current item photos:</p>
              <div class="grid grid-cols-4 gap-2">
                <%= for {_photo, idx} <- Enum.with_index(@current_item_photos) do %>
                  <div class="bg-gray-700 p-2 rounded">
                    <p class="text-xs text-center">Photo {idx + 1}</p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp bag_step_title(1), do: "Take Bag Photo"
  defp bag_step_title(2), do: "Take Layout Photo"
  defp bag_step_title(3), do: "Take Info Photo"

  defp create_bag_with_photos(photos) do
    # TODO: Use PhotoCapture service
    # For now, just create a bag
    Kirbs.Resources.Bag.create(%{})
  end

  defp create_new_item(socket) do
    socket
    |> assign(:current_item_photos, [])
  end

  defp save_current_item(socket) do
    # TODO: Use PhotoCapture service
    # For now, just create an item
    Kirbs.Resources.Item.create(%{bag_id: socket.assigns.current_bag.id})
  end
end
