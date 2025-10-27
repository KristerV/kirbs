defmodule KirbsWeb.ItemLive.Show do
  use KirbsWeb, :live_view
  import LiveSelect

  alias Kirbs.Resources.{Item, Image, YagaMetadata}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item = Item.get!(id) |> Ash.load!([:bag])
    images = Image.list!() |> Enum.filter(&(&1.item_id == item.id)) |> Enum.sort_by(& &1.order)

    # Load Yaga metadata for dropdowns
    brands = YagaMetadata.list_by_type!(:brand) |> Enum.sort_by(& &1.name)
    categories = YagaMetadata.list_by_type!(:category)
    colors = YagaMetadata.list_by_type!(:color) |> Enum.sort_by(& &1.name)
    materials = YagaMetadata.list_by_type!(:material) |> Enum.sort_by(& &1.name)
    conditions = YagaMetadata.list_by_type!(:condition) |> Enum.sort_by(& &1.name)

    # Prepare form changeset
    form = AshPhoenix.Form.for_update(item, :update)

    # Build category lookup map
    category_map = Map.new(categories, &{&1.yaga_id, &1})

    # Prepare options for live_select with full paths
    category_options =
      categories
      |> Enum.map(fn cat ->
        path = build_category_path(cat, category_map)
        {path, cat.yaga_id}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    brand_options = Enum.map(brands, &{&1.name, &1.yaga_id})
    condition_options = Enum.map(conditions, &{&1.name, &1.yaga_id})
    color_options = Enum.map(colors, &{&1.name, &1.yaga_id})
    material_options = Enum.map(materials, &{&1.name, &1.yaga_id})

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:images, images)
     |> assign(:brands, brands)
     |> assign(:categories, categories)
     |> assign(:colors, colors)
     |> assign(:materials, materials)
     |> assign(:conditions, conditions)
     |> assign(:form, to_form(form))
     |> assign(:category_options, category_options)
     |> assign(:category_map, category_map)
     |> assign(:brand_options, brand_options)
     |> assign(:condition_options, condition_options)
     |> assign(:color_options, color_options)
     |> assign(:material_options, material_options)}
  end

  @impl true
  def handle_event("save_item", params, socket) do
    # Parse array fields
    colors = parse_array(params["colors"])
    materials = parse_array(params["materials"])
    yaga_colors_id_map = parse_live_select_array(params["yaga_colors_id_map"])
    yaga_materials_id_map = parse_live_select_array(params["yaga_materials_id_map"])

    # Check if item is complete (all required fields filled + has images)
    has_images = socket.assigns.images != []
    yaga_category_filled = params["yaga_category_id"] not in [nil, ""]
    yaga_condition_filled = params["yaga_condition_id"] not in [nil, ""]
    listed_price_filled = params["listed_price"] not in [nil, ""]

    is_complete =
      has_images && yaga_category_filled && yaga_condition_filled && listed_price_filled

    new_status = if is_complete, do: "reviewed", else: "pending"

    update_params =
      params
      |> Map.take([
        "brand",
        "size",
        "description",
        "quality",
        "suggested_category",
        "yaga_brand_id",
        "yaga_category_id",
        "yaga_condition_id",
        "listed_price"
      ])
      |> Map.put("colors", colors)
      |> Map.put("materials", materials)
      |> Map.put("yaga_colors_id_map", yaga_colors_id_map)
      |> Map.put("yaga_materials_id_map", yaga_materials_id_map)
      |> Map.put("status", new_status)
      |> convert_to_atoms()
      |> convert_integers()
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
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_and_upload", _params, socket) do
    # TODO: Implement Yaga upload service
    # For now, just show a message that this functionality needs to be implemented
    {:noreply,
     socket
     |> put_flash(
       :info,
       "Save and upload functionality will be implemented. Please use the form to save first, then upload from bag view."
     )}
  end

  @impl true
  def handle_event("live_select_change", %{"text" => text, "id" => live_select_id}, socket) do
    search_text = String.downcase(text)

    options =
      cond do
        String.contains?(live_select_id, "yaga_brand_id") ->
          socket.assigns.brands
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.yaga_id})
          |> Enum.sort_by(&elem(&1, 0))

        String.contains?(live_select_id, "yaga_category_id") ->
          socket.assigns.categories
          |> Enum.map(fn cat ->
            path = build_category_path(cat, socket.assigns.category_map)
            {path, cat.yaga_id}
          end)
          |> Enum.filter(fn {path, _} -> String.contains?(String.downcase(path), search_text) end)
          |> Enum.sort_by(&elem(&1, 0))

        String.contains?(live_select_id, "yaga_condition_id") ->
          socket.assigns.conditions
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.yaga_id})

        String.contains?(live_select_id, "yaga_colors_id_map") ->
          socket.assigns.colors
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.yaga_id})

        String.contains?(live_select_id, "yaga_materials_id_map") ->
          socket.assigns.materials
          |> Enum.filter(&String.contains?(String.downcase(&1.name), search_text))
          |> Enum.map(&{&1.name, &1.yaga_id})

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

  defp parse_array(nil), do: []
  defp parse_array(""), do: []

  defp parse_array(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_live_select_array(nil), do: []
  defp parse_live_select_array([]), do: []

  defp parse_live_select_array(list) when is_list(list) do
    list
    |> Enum.map(fn
      val when is_integer(val) -> val
      val when is_binary(val) -> String.to_integer(val)
    end)
  end

  defp parse_live_select_array(_), do: []

  defp convert_to_atoms(params) do
    params
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp convert_integers(params) do
    params
    |> Enum.map(fn
      {k, v}
      when k in [:yaga_brand_id, :yaga_category_id, :yaga_condition_id] and is_binary(v) and
             v != "" ->
        {k, String.to_integer(v)}

      {k, v} when k in [:yaga_brand_id, :yaga_category_id, :yaga_condition_id] and v == "" ->
        {k, nil}

      {k, v} ->
        {k, v}
    end)
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
          <.link navigate={~p"/bags/#{@item.bag_id}"} class="btn btn-ghost">
            Back to Bag
          </.link>
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
                    <button
                      type="button"
                      class="btn btn-error btn-xs absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                      phx-click="delete_image"
                      phx-value-image_id={image.id}
                      data-confirm="Are you sure you want to delete this image?"
                    >
                      Delete
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
                  <input
                    type="text"
                    name="brand"
                    class="input input-bordered w-full"
                    value={@item.brand}
                    placeholder="H&M, Zara"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Size</span>
                  </label>
                  <input
                    type="text"
                    name="size"
                    class="input input-bordered w-full"
                    value={@item.size}
                    placeholder="6-9 kuud, 110"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Quality</span>
                  </label>
                  <input
                    type="text"
                    name="quality"
                    class="input input-bordered w-full"
                    value={@item.quality}
                    placeholder="like new, used, worn"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Suggested Category</span>
                  </label>
                  <input
                    type="text"
                    name="suggested_category"
                    class="input input-bordered w-full"
                    value={@item.suggested_category}
                    placeholder="Pluus, Püksid"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Colors</span>
                  </label>
                  <input
                    type="text"
                    name="colors"
                    class="input input-bordered w-full"
                    value={if @item.colors, do: Enum.join(@item.colors, ", "), else: ""}
                    placeholder="red, blue, green"
                  />
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Materials</span>
                  </label>
                  <input
                    type="text"
                    name="materials"
                    class="input input-bordered w-full"
                    value={if @item.materials, do: Enum.join(@item.materials, ", "), else: ""}
                    placeholder="cotton, polyester"
                  />
                </div>

                <div class="form-control md:col-span-2">
                  <label class="label">
                    <span class="label-text font-semibold">Description</span>
                  </label>
                  <textarea
                    name="description"
                    class="textarea textarea-bordered h-24 w-full"
                    placeholder="Describe the item..."
                  ><%= @item.description %></textarea>
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body">
              <h2 class="card-title mb-4">Yaga Integration</h2>

              <%= if @brands == [] do %>
                <div class="alert alert-warning mb-4">
                  <span>
                    No Yaga metadata found. Please go to
                    <.link navigate="/settings" class="link">Settings</.link>
                    and refresh metadata.
                  </span>
                </div>
              <% end %>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Brand</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:yaga_brand_id]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search brands..."
                      value={@item.yaga_brand_id}
                      options={@brand_options}
                      update_min_len={0}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Category *</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:yaga_category_id]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search categories..."
                      value={@item.yaga_category_id}
                      options={@category_options}
                      update_min_len={0}
                      dropdown_class="bg-base-200 dropdown-content menu menu-compact p-1 rounded-box shadow z-[1] min-w-[800px]"
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Condition *</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:yaga_condition_id]}
                      mode={:single}
                      style={:daisyui}
                      placeholder="Search conditions..."
                      value={@item.yaga_condition_id}
                      options={@condition_options}
                      update_min_len={0}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Colors</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:yaga_colors_id_map]}
                      mode={:tags}
                      style={:daisyui}
                      placeholder="Search colors..."
                      value={@item.yaga_colors_id_map || []}
                      options={@color_options}
                      update_min_len={0}
                      keep_options_on_select={true}
                    />
                  </div>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Materials</span>
                  </label>
                  <div class="[&_.live-select-wrapper]:block [&_label]:hidden">
                    <.live_select
                      field={@form[:yaga_materials_id_map]}
                      mode={:tags}
                      style={:daisyui}
                      placeholder="Search materials..."
                      value={@item.yaga_materials_id_map || []}
                      options={@material_options}
                      update_min_len={0}
                      keep_options_on_select={true}
                    />
                  </div>
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
                      <span class="label-text-alt">{@item.ai_price_explanation}</span>
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
                    name="listed_price"
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
              type="button"
              class="btn btn-success"
              phx-click="save_and_upload"
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
