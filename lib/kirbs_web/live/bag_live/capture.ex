defmodule KirbsWeb.BagLive.Capture do
  use KirbsWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    # If bag_id is provided, skip bag photos and start adding items to existing bag
    socket =
      case params do
        %{"bag_id" => bag_id} ->
          bag = Kirbs.Resources.Bag.get!(bag_id)

          socket
          |> assign(:phase, :item_photos)
          |> assign(:bag_step, 4)
          |> assign(:bag_photos, [])
          |> assign(:current_bag, bag)
          |> assign(:current_item, nil)
          |> assign(:current_item_photos, [])
          |> assign(:all_items, [])
          |> assign(:camera_ready, false)
          |> assign(:camera_error, nil)

        _ ->
          socket
          |> assign(:phase, :bag_photos)
          |> assign(:bag_step, 1)
          |> assign(:bag_photos, [])
          |> assign(:current_bag, nil)
          |> assign(:current_item, nil)
          |> assign(:current_item_photos, [])
          |> assign(:all_items, [])
          |> assign(:camera_ready, false)
          |> assign(:camera_error, nil)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("request_capture", _params, socket) do
    {:noreply, push_event(socket, "capture_photo", %{})}
  end

  @impl true
  def handle_event("photo_captured", %{"data" => data_url}, socket) do
    # Extract base64 data from data URL
    photo_data = extract_photo_data(data_url)

    case socket.assigns.phase do
      :bag_photos -> handle_bag_photo(socket, photo_data)
      :item_photos -> handle_item_photo(socket, photo_data)
    end
  end

  defp handle_bag_photo(socket, photo_data) do
    bag_photos = socket.assigns.bag_photos ++ [photo_data]
    bag_step = socket.assigns.bag_step + 1

    socket =
      if bag_step > 3 do
        # All 3 bag photos captured, create bag and move to item phase
        case create_bag_with_photos(bag_photos) do
          {:ok, bag} ->
            socket
            |> assign(:phase, :item_photos)
            |> assign(:current_bag, bag)
            |> assign(:bag_photos, [])
            |> create_new_item()

          {:error, _reason} ->
            socket
            |> put_flash(:error, "Failed to create bag")
        end
      else
        socket
        |> assign(:bag_photos, bag_photos)
        |> assign(:bag_step, bag_step)
      end

    {:noreply, socket}
  end

  defp handle_item_photo(socket, photo_data) do
    current_item_photos = socket.assigns.current_item_photos ++ [photo_data]

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

    # If we started with an existing bag, redirect back to it
    redirect_path =
      if socket.assigns.bag_step == 4 do
        ~p"/bags/#{socket.assigns.current_bag.id}"
      else
        ~p"/bags"
      end

    {:noreply, redirect(socket, to: redirect_path)}
  end

  @impl true
  def handle_event("camera_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, :camera_error, error)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .camera-flash {
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background-color: white;
        opacity: 0;
        pointer-events: none;
        z-index: 10;
      }
      .camera-flash.active {
        opacity: 0.2;
      }
    </style>
    <div class="h-[calc(100vh-4rem)] flex flex-col bg-gray-900 text-white overflow-hidden">
      <%= if @camera_error do %>
        <div class="bg-red-600 text-white p-4">
          <div class="container mx-auto">
            <p class="font-bold">Camera Access Error</p>
            <p class="text-sm">
              Unable to access your camera. Please make sure you've granted camera permissions to this site, and that no other application is using the camera.
            </p>
            <p class="text-xs mt-2 text-red-100">Technical details: {@camera_error}</p>
          </div>
        </div>
      <% end %>

      <%= if @phase == :bag_photos do %>
        <div class="flex-1 flex flex-col min-h-0">
          <div class="flex-1 bg-black relative min-h-0" id="bag-camera" phx-hook="Camera">
            <video class="w-full h-full object-contain" autoplay playsinline></video>
            <div class="camera-flash"></div>
            <div class="absolute top-4 left-4 text-white text-9xl font-bold">
              {@bag_step}/3
            </div>
          </div>

          <div class="p-4 space-y-4">
            <button
              phx-click="request_capture"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
            >
              Capture
            </button>
          </div>
        </div>
      <% else %>
        <div class="flex-1 flex flex-col min-h-0">
          <div class="flex-1 bg-black relative min-h-0" id="item-camera" phx-hook="Camera">
            <video class="w-full h-full object-contain" autoplay playsinline></video>
            <div class="camera-flash"></div>
            <div class="absolute top-4 left-4 text-white text-9xl font-bold">
              {length(@current_item_photos)}
            </div>
          </div>

          <div class="p-4 space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <button
                phx-click="end_bag"
                class="bg-red-600 hover:bg-red-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
              >
                End Bag
              </button>

              <button
                phx-click="next_item"
                class="bg-green-600 hover:bg-green-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
              >
                Next Item
              </button>
            </div>

            <button
              phx-click="request_capture"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
            >
              Capture
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp bag_step_title(1), do: "Take Bag Photo"
  defp bag_step_title(2), do: "Take Layout Photo"
  defp bag_step_title(3), do: "Take Info Photo"

  defp bag_step_instruction(1), do: "Bag"
  defp bag_step_instruction(2), do: "All items"
  defp bag_step_instruction(3), do: "Info paper"

  defp extract_photo_data(data_url) do
    # Extract base64 data from "data:image/jpeg;base64,..." format
    [_prefix, base64_data] = String.split(data_url, ",", parts: 2)
    Base.decode64!(base64_data)
  end

  defp create_bag_with_photos(photos) do
    Kirbs.Services.PhotoCapture.run(%{type: :bag, photos: photos})
  end

  defp create_new_item(socket) do
    socket
    |> assign(:current_item_photos, [])
  end

  defp save_current_item(socket) do
    photos = socket.assigns.current_item_photos
    bag_id = socket.assigns.current_bag.id

    Kirbs.Services.PhotoCapture.run(%{type: :item, bag_id: bag_id, photos: photos})
  end
end
