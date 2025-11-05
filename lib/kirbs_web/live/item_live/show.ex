defmodule KirbsWeb.ItemLive.Show do
  use KirbsWeb, :live_view
  import LiveSelect

  alias Kirbs.Resources.{Item, Image}
  alias Kirbs.YagaTaxonomy

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Subscribe to item updates
    Phoenix.PubSub.subscribe(Kirbs.PubSub, "item:#{id}")

    item = Item.get!(id) |> Ash.load!([:bag])
    images = Image.list!() |> Enum.filter(&(&1.item_id == item.id)) |> Enum.sort_by(& &1.order)

    # Load Yaga taxonomy from static data
    brands = YagaTaxonomy.all_brands() |> Enum.sort_by(& &1.name)
    categories = YagaTaxonomy.all_categories()
    colors = YagaTaxonomy.all_colors() |> Enum.sort_by(& &1.name)
    materials = YagaTaxonomy.all_materials() |> Enum.sort_by(& &1.name)
    conditions = YagaTaxonomy.all_conditions() |> Enum.sort_by(& &1.name)
    sizes = YagaTaxonomy.all_sizes()

    # Prepare form changeset
    form = AshPhoenix.Form.for_update(item, :update, as: "item")

    # Build category lookup map
    category_map = Map.new(categories, &{&1.yaga_id, &1})

    # Prepare options for live_select with full paths (name -> name for string values)
    category_options =
      categories
      |> Enum.map(fn cat ->
        path = build_category_path(cat, category_map)
        {path, cat.name}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    brand_options = Enum.map(brands, &{&1.name, &1.name})
    condition_options = Enum.map(conditions, &{&1.name, &1.name})
    color_options = Enum.map(colors, &{&1.name, &1.name})
    material_options = Enum.map(materials, &{&1.name, &1.name})
    size_options = Enum.map(sizes, &{&1.name, &1.name})

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:images, images)
     |> assign(:brands, brands)
     |> assign(:categories, categories)
     |> assign(:colors, colors)
     |> assign(:materials, materials)
     |> assign(:conditions, conditions)
     |> assign(:sizes, sizes)
     |> assign(:form, to_form(form))
     |> assign(:category_options, category_options)
     |> assign(:category_map, category_map)
     |> assign(:brand_options, brand_options)
     |> assign(:condition_options, condition_options)
     |> assign(:color_options, color_options)
     |> assign(:material_options, material_options)
     |> assign(:size_options, size_options)
     |> assign(:delete_confirmation, false)}
  end

  @impl true
  def handle_event("save_item", %{"item" => item_params, "action" => "save_and_upload"}, socket) do
    # Redirect to save_and_upload handler
    handle_event("save_and_upload", %{"item" => item_params}, socket)
  end

  @impl true
  def handle_event("save_item", %{"item" => item_params}, socket) do
    # Parse array fields (colors and materials are submitted as arrays from live_select tags mode)
    colors = parse_live_select_array(item_params["colors"])
    materials = parse_live_select_array(item_params["materials"])

    # Check if item is complete (all required fields filled + has images)
    has_images = socket.assigns.images != []
    category_filled = item_params["suggested_category"] not in [nil, ""]
    quality_filled = item_params["quality"] not in [nil, ""]
    listed_price_filled = item_params["listed_price"] not in [nil, ""]

    is_complete =
      has_images && category_filled && quality_filled && listed_price_filled

    new_status = if is_complete, do: "reviewed", else: "pending"

    update_params =
      item_params
      |> Map.take([
        "brand",
        "size",
        "description",
        "quality",
        "suggested_category",
        "listed_price"
      ])
      |> Map.put("colors", colors)
      |> Map.put("materials", materials)
      |> Map.put("status", new_status)
      |> convert_to_atoms()
      |> convert_decimal()

    case Item.update(socket.assigns.item, update_params) do
      {:ok, item} ->
        {:noreply, push_navigate(socket, to: ~p"/bags/#{item.bag_id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to save item: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("form_change", _params, socket) do
    # Reset delete confirmation if user starts editing
    {:noreply, assign(socket, :delete_confirmation, false)}
  end

  @impl true
  def handle_event("save_and_upload", %{"item" => item_params}, socket) do
    # Parse array fields
    colors = parse_live_select_array(item_params["colors"])
    materials = parse_live_select_array(item_params["materials"])

    update_params =
      item_params
      |> Map.take([
        "brand",
        "size",
        "description",
        "quality",
        "suggested_category",
        "listed_price"
      ])
      |> Map.put("colors", colors)
      |> Map.put("materials", materials)
      |> Map.put("status", "reviewed")
      |> convert_to_atoms()
      |> convert_decimal()

    case Item.update(socket.assigns.item, update_params) do
      {:ok, item} ->
        # Queue upload job
        %{item_id: item.id}
        |> Kirbs.Jobs.UploadItemJob.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> put_flash(:info, "Item saved and upload started! Check back in a moment.")
         |> push_navigate(to: ~p"/bags/#{item.bag_id}")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to save item: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("live_select_change", %{"text" => text, "id" => live_select_id}, socket) do
    search_text = String.downcase(text)

    options =
      cond do
        String.contains?(live_select_id, "brand") ->
          socket.assigns.brands
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.name})
          |> Enum.sort_by(&elem(&1, 0))

        String.contains?(live_select_id, "size") ->
          socket.assigns.sizes
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.name})

        String.contains?(live_select_id, "suggested_category") ->
          socket.assigns.categories
          |> Enum.map(fn cat ->
            path = build_category_path(cat, socket.assigns.category_map)
            {path, cat.name}
          end)
          |> Enum.filter(fn {path, _} -> String.contains?(String.downcase(path), search_text) end)
          |> Enum.sort_by(&elem(&1, 0))

        String.contains?(live_select_id, "quality") ->
          socket.assigns.conditions
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.name})

        String.contains?(live_select_id, "colors") ->
          socket.assigns.colors
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.name})

        String.contains?(live_select_id, "materials") ->
          socket.assigns.materials
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.name})

        true ->
          []
      end

    send_update(LiveSelect.Component, id: live_select_id, options: options)
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_image", %{"image_id" => image_id}, socket) do
    case Image.get(image_id) do
      {:ok, image} ->
        case Image.destroy(image) do
          :ok ->
            # Also delete file from disk
            upload_dir = Application.get_env(:kirbs, :image_upload_dir)
            file_path = Path.join(upload_dir, image.path)
            File.rm(file_path)

            images =
              Image.list!()
              |> Enum.filter(&(&1.item_id == socket.assigns.item.id))
              |> Enum.sort_by(& &1.order)

            {:noreply,
             socket
             |> assign(:images, images)
             |> put_flash(:info, "Image deleted successfully")}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Failed to delete image")}
        end

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Image not found")}
    end
  end

  @impl true
  def handle_event("toggle_label", %{"image_id" => image_id}, socket) do
    case Image.get(image_id) do
      {:ok, image} ->
        case Image.update(image, %{is_label: !image.is_label}) do
          {:ok, _updated_image} ->
            images =
              Image.list!()
              |> Enum.filter(&(&1.item_id == socket.assigns.item.id))
              |> Enum.sort_by(& &1.order)

            {:noreply, assign(socket, :images, images)}

          {:error, _error} ->
            {:noreply, socket}
        end

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("run_ai", _params, socket) do
    %{item_id: socket.assigns.item.id}
    |> Kirbs.Jobs.ProcessItemJob.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "AI processing job scheduled")}
  end

  @impl true
  def handle_event("delete_item", _params, socket) do
    if socket.assigns.delete_confirmation do
      # User confirmed - proceed with deletion
      item = socket.assigns.item
      bag_id = item.bag_id

      # Delete all associated images first
      upload_dir = Application.get_env(:kirbs, :image_upload_dir)

      Enum.each(socket.assigns.images, fn image ->
        # Delete file from disk
        file_path = Path.join(upload_dir, image.path)
        File.rm(file_path)
        # Delete image record
        Image.destroy(image)
      end)

      # Delete the item
      case Item.destroy(item) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Item deleted successfully")
           |> push_navigate(to: ~p"/bags/#{bag_id}")}

        {:error, _error} ->
          {:noreply,
           socket
           |> assign(:delete_confirmation, false)
           |> put_flash(:error, "Failed to delete item")}
      end
    else
      # First click - show confirmation
      {:noreply, assign(socket, :delete_confirmation, true)}
    end
  end

  @impl true
  def handle_info({:item_processed, _item_id}, socket) do
    # Reload item data when AI processing completes
    item = Item.get!(socket.assigns.item.id) |> Ash.load!([:bag])
    form = AshPhoenix.Form.for_update(item, :update, as: "item")

    {:noreply,
     socket
     |> assign(:item, item)
     |> assign(:form, to_form(form))}
  end

  defp parse_live_select_array(nil), do: []
  defp parse_live_select_array([]), do: []
  defp parse_live_select_array(list) when is_list(list), do: list
  defp parse_live_select_array(_), do: []

  defp convert_to_atoms(params) do
    params
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp convert_decimal(params) do
    case params[:listed_price] do
      nil ->
        params

      "" ->
        Map.put(params, :listed_price, nil)

      price when is_binary(price) ->
        Map.put(params, :listed_price, Decimal.new(price))

      _ ->
        params
    end
  end

  defp build_category_path(category, category_map) do
    build_path_recursive(category, category_map, [])
    |> Enum.reverse()
    |> Enum.join(" > ")
  end

  defp build_path_recursive(category, category_map, acc) do
    acc = [category.name | acc]

    case category.parent_id do
      nil ->
        acc

      parent_id ->
        case Map.get(category_map, parent_id) do
          nil -> acc
          parent -> build_path_recursive(parent, category_map, acc)
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Item Details</h1>
          <div class="flex gap-2">
            <.link
              navigate={~p"/bags/capture?bag_id=#{@item.bag_id}&item_id=#{@item.id}"}
              class="btn btn-sm"
            >
              Add Photos
            </.link>
            <.link navigate={~p"/items/#{@item.id}/split"} class="btn btn-sm">
              Split Item
            </.link>
            <button class="btn btn-sm" phx-click="run_ai">
              Run AI
            </button>
            <button
              class={"btn btn-sm #{if @delete_confirmation, do: "btn-error", else: ""}"}
              phx-click="delete_item"
            >
              {if @delete_confirmation, do: "Confirm Delete?", else: "Delete"}
            </button>
          </div>
        </div>
        
    <!-- Image Gallery -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Photos ({length(@images)})</h2>
            <%= if @images == [] do %>
              <div class="alert alert-warning">
                <span>No photos for this item</span>
              </div>
            <% else %>
              <div class="grid grid-cols-4 gap-4">
                <%= for image <- @images do %>
                  <div class="relative group">
                    <div class="aspect-square bg-base-200 rounded-lg overflow-hidden">
                      <img
                        src={"/uploads/#{image.path}"}
                        alt="Item photo"
                        class="w-full h-full object-cover"
                      />
                    </div>
                    <%= if image.is_label do %>
                      <div class="badge badge-primary badge-sm absolute top-2 left-2">
                        Label
                      </div>
                    <% end %>
                    <button
                      type="button"
                      class="btn btn-error btn-xs absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                      phx-click="delete_image"
                      phx-value-image_id={image.id}
                      data-confirm="Are you sure you want to delete this image?"
                    >
                      Delete
                    </button>
                    <button
                      type="button"
                      class="btn btn-info btn-xs absolute top-10 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                      phx-click="toggle_label"
                      phx-value-image_id={image.id}
                    >
                      {if image.is_label, do: "Unmark Label", else: "Mark Label"}
                    </button>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Item Data Form -->
        <form phx-submit="save_item" phx-change="form_change">
          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body">
              <h2 class="card-title mb-4">Basic Information</h2>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Brand</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:brand]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search brands..."
                      value={@item.brand}
                      options={@brand_options}
                      update_min_len={0}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Size</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:size]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search sizes..."
                      value={@item.size}
                      options={@size_options}
                      update_min_len={0}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Category *</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:suggested_category]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search categories..."
                      value={@item.suggested_category}
                      options={@category_options}
                      update_min_len={0}
                      dropdown_class="bg-base-200 dropdown-content menu menu-compact p-1 rounded-box shadow z-[1] min-w-[800px]"
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Condition *</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:quality]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search conditions..."
                      value={@item.quality}
                      options={@condition_options}
                      update_min_len={0}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Colors</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:colors]}
                      mode={:tags}
                      style={:daisyui}
                      placeholder="Search colors..."
                      value={@item.colors || []}
                      options={@color_options}
                      update_min_len={0}
                      keep_options_on_select={true}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Materials</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:materials]}
                      mode={:tags}
                      style={:daisyui}
                      placeholder="Search materials..."
                      value={@item.materials || []}
                      options={@material_options}
                      update_min_len={0}
                      keep_options_on_select={true}
                    />
                  </div>
                </div>

                <div class="form-control md:col-span-2">
                  <label class="label">
                    <span class="label-text font-semibold">Description</span>
                  </label>
                  <textarea
                    name="item[description]"
                    class="textarea textarea-bordered h-24 w-full"
                    placeholder="Describe the item..."
                  ><%= @item.description %></textarea>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body">
              <h2 class="card-title mb-4">Pricing</h2>

              <div class="grid grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">AI Suggested Price</span>
                  </label>
                  <input
                    type="text"
                    class="input input-bordered"
                    value={@item.ai_suggested_price}
                    disabled
                  />
                  <%= if @item.ai_price_explanation do %>
                    <label class="label">
                      <span class="label-text-alt text-gray-500 whitespace-normal break-words">
                        {@item.ai_price_explanation}
                      </span>
                    </label>
                  <% end %>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Listed Price *</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    name="item[listed_price]"
                    class="input input-bordered"
                    value={@item.listed_price}
                    placeholder="10.00"
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body">
              <h2 class="card-title mb-4">Status</h2>

              <div class="flex items-center gap-4">
                <div class="badge badge-lg">{@item.status}</div>

                <%= if @item.yaga_id do %>
                  <div class="text-sm">
                    <span class="font-semibold">Yaga ID:</span>
                    {@item.yaga_id}
                  </div>
                <% end %>

                <%= if @item.upload_error do %>
                  <div class="alert alert-error">
                    <span>{@item.upload_error}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-2">
            <button type="submit" class="btn btn-primary">
              Save Item
            </button>
            <button
              type="submit"
              name="action"
              value="save_and_upload"
              class="btn btn-success"
              disabled={@item.status == :uploaded_to_yaga}
            >
              Save and Upload to Yaga
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
