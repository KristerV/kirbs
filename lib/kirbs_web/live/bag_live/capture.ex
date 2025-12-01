defmodule KirbsWeb.BagLive.Capture do
  use KirbsWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    # If bag_id is provided, skip bag photos and start adding items to existing bag
    # If item_id is also provided, we're adding photos to an existing item
    socket =
      case params do
        %{"bag_id" => bag_id, "item_id" => item_id} ->
          bag = Kirbs.Resources.Bag.get!(bag_id, load: [:item_count])

          socket
          |> assign(:phase, :item_photos)
          |> assign(:bag_step, 4)
          |> assign(:bag_photos, [])
          |> assign(:current_bag, bag)
          |> assign(:current_item, nil)
          |> assign(:existing_item_id, item_id)
          |> assign(:current_item_photos, [])
          |> assign(:current_item_label_photos, [])
          |> assign(:all_items, [])
          |> assign(:camera_ready, false)
          |> assign(:camera_error, nil)

        %{"bag_id" => bag_id} ->
          bag = Kirbs.Resources.Bag.get!(bag_id, load: [:item_count])

          socket
          |> assign(:phase, :item_photos)
          |> assign(:bag_step, 4)
          |> assign(:bag_photos, [])
          |> assign(:current_bag, bag)
          |> assign(:current_item, nil)
          |> assign(:existing_item_id, nil)
          |> assign(:current_item_photos, [])
          |> assign(:current_item_label_photos, [])
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
          |> assign(:existing_item_id, nil)
          |> assign(:current_item_photos, [])
          |> assign(:current_item_label_photos, [])
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

  def handle_event("request_label_capture", _params, socket) do
    {:noreply, push_event(socket, "capture_photo", %{is_label: true})}
  end

  def handle_event("photo_captured", %{"data" => data_url, "is_label" => is_label}, socket) do
    # Extract base64 data from data URL
    photo_data = extract_photo_data(data_url)

    case socket.assigns.phase do
      :bag_photos -> handle_bag_photo(socket, photo_data)
      :item_photos -> handle_item_photo(socket, photo_data, is_label)
    end
  end

  def handle_event("photo_captured", %{"data" => data_url}, socket) do
    # Extract base64 data from data URL
    photo_data = extract_photo_data(data_url)

    case socket.assigns.phase do
      :bag_photos -> handle_bag_photo(socket, photo_data)
      :item_photos -> handle_item_photo(socket, photo_data, false)
    end
  end

  def handle_event("next_item", _params, socket) do
    schedule_item_processing(socket.assigns.current_item.id)

    all_items = socket.assigns.all_items ++ [socket.assigns.current_item]
    bag = Ash.load!(socket.assigns.current_bag, :item_count, reuse_values?: false)

    socket =
      socket
      |> assign(:all_items, all_items)
      |> assign(:current_bag, bag)
      |> create_new_item()

    {:noreply, socket}
  end

  def handle_event("end_bag", _params, socket) do
    if socket.assigns.current_item do
      schedule_item_processing(socket.assigns.current_item.id)
    end

    redirect_path =
      cond do
        socket.assigns.existing_item_id != nil ->
          ~p"/items/#{socket.assigns.existing_item_id}"

        socket.assigns.bag_step == 4 ->
          ~p"/bags/#{socket.assigns.current_bag.id}"

        true ->
          ~p"/bags"
      end

    {:noreply, redirect(socket, to: redirect_path)}
  end

  def handle_event("go_to_bag", _params, socket) do
    if socket.assigns.current_item do
      schedule_item_processing(socket.assigns.current_item.id)
    end

    {:noreply, redirect(socket, to: ~p"/bags/#{socket.assigns.current_bag.id}")}
  end

  def handle_event("camera_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, :camera_error, error)}
  end

  defp handle_bag_photo(socket, photo_data) do
    bag_photos = socket.assigns.bag_photos ++ [photo_data]
    bag_step = socket.assigns.bag_step + 1

    socket =
      if bag_step > 3 do
        # All 3 bag photos captured, create bag and move to item phase
        case create_bag_with_photos(bag_photos) do
          {:ok, bag} ->
            # Schedule AI processing for bag
            schedule_bag_processing(bag.id)
            bag = Ash.load!(bag, :item_count)

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

  defp handle_item_photo(socket, photo_data, is_label) do
    # Get or create item
    {socket, item} = ensure_current_item(socket)

    # Save photo immediately to database
    {:ok, _image} = Kirbs.Services.PhotoCapture.save_single_photo(item, photo_data, is_label)

    # Update photo counts for display
    socket =
      if is_label do
        update(socket, :current_item_label_photos, &(&1 ++ [photo_data]))
      else
        update(socket, :current_item_photos, &(&1 ++ [photo_data]))
      end

    {:noreply, socket}
  end

  defp ensure_current_item(socket) do
    case socket.assigns.current_item do
      nil ->
        {:ok, item} = create_item_record(socket)
        {assign(socket, :current_item, item), item}

      item ->
        {socket, item}
    end
  end

  defp create_item_record(socket) do
    if socket.assigns.existing_item_id do
      {:ok, Kirbs.Resources.Item.get!(socket.assigns.existing_item_id)}
    else
      Kirbs.Resources.Item.create(%{bag_id: socket.assigns.current_bag.id})
    end
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
    <div class="h-[calc(100dvh-4rem)] flex flex-col overflow-hidden">
      <!-- Extra navbar for capture page -->
      <%= if @current_bag do %>
        <div class="navbar bg-base-100 border-b border-base-300 min-h-0 py-2 shrink-0">
          <div class="flex-1 flex items-center gap-2">
            <button phx-click="go_to_bag" class="btn btn-primary btn-sm">Go to Bag</button>
            <span class="text-sm">{@current_bag.item_count || 0} items</span>
          </div>
          <div class="flex-none">
            <button phx-click="next_item" class="btn btn-success btn-sm">Next Item</button>
          </div>
        </div>
      <% end %>
      <div class="flex-1 flex flex-col bg-gray-900 text-white overflow-hidden min-h-0">
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

            <div class="p-4 shrink-0">
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
              <div class="absolute top-4 left-4 text-white text-4xl font-bold">
                {length(@current_item_photos)}/{length(@current_item_label_photos)}
              </div>
            </div>

            <div class="p-4 shrink-0">
              <div class="grid grid-cols-2 gap-4">
                <button
                  phx-click="request_capture"
                  class="bg-blue-600 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
                >
                  Capture
                </button>

                <button
                  phx-click="request_label_capture"
                  class="bg-yellow-600 hover:bg-yellow-700 text-white font-bold py-4 px-6 rounded-lg text-xl"
                >
                  Capture Label
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

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
    |> assign(:current_item, nil)
    |> assign(:current_item_photos, [])
    |> assign(:current_item_label_photos, [])
  end

  defp schedule_bag_processing(bag_id) do
    %{bag_id: bag_id}
    |> Kirbs.Jobs.ProcessBagJob.new()
    |> Oban.insert()
  end

  defp schedule_item_processing(item_id) do
    %{item_id: item_id}
    |> Kirbs.Jobs.ProcessItemJob.new()
    |> Oban.insert()
  end
end
