defmodule KirbsWeb.ItemLive.Show do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Item, Image, YagaMetadata}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    item = Item.get!(id) |> Ash.load!([:bag])
    images = Image.list!() |> Enum.filter(&(&1.item_id == item.id)) |> Enum.sort_by(& &1.order)

    # Load Yaga metadata for dropdowns
    brands = YagaMetadata.list_by_type!(:brand) |> Enum.sort_by(& &1.name)
    categories = YagaMetadata.list_by_type!(:category) |> Enum.sort_by(& &1.name)
    colors = YagaMetadata.list_by_type!(:color) |> Enum.sort_by(& &1.name)
    materials = YagaMetadata.list_by_type!(:material) |> Enum.sort_by(& &1.name)
    conditions = YagaMetadata.list_by_type!(:condition) |> Enum.sort_by(& &1.name)

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:images, images)
     |> assign(:brands, brands)
     |> assign(:categories, categories)
     |> assign(:colors, colors)
     |> assign(:materials, materials)
     |> assign(:conditions, conditions)}
  end

  @impl true
  def handle_event("save_item", params, socket) do
    # Parse array fields
    colors = parse_array(params["colors"])
    materials = parse_array(params["materials"])
    yaga_colors_id_map = parse_integer_array(params["yaga_colors_id_map"])
    yaga_materials_id_map = parse_integer_array(params["yaga_materials_id_map"])

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

  defp parse_integer_array(nil), do: []
  defp parse_integer_array(""), do: []

  defp parse_integer_array(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_integer/1)
  end

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
        <form phx-submit="save_item">
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
                  <select name="yaga_brand_id" class="select select-bordered w-full">
                    <option value="">-- Select Brand --</option>
                    <%= for brand <- @brands do %>
                      <option value={brand.yaga_id} selected={@item.yaga_brand_id == brand.yaga_id}>
                        {brand.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Category *</span>
                  </label>
                  <select name="yaga_category_id" class="select select-bordered w-full">
                    <option value="">-- Select Category --</option>
                    <%= for category <- @categories do %>
                      <option
                        value={category.yaga_id}
                        selected={@item.yaga_category_id == category.yaga_id}
                      >
                        {category.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Condition *</span>
                  </label>
                  <select name="yaga_condition_id" class="select select-bordered w-full">
                    <option value="">-- Select Condition --</option>
                    <%= for condition <- @conditions do %>
                      <option
                        value={condition.yaga_id}
                        selected={@item.yaga_condition_id == condition.yaga_id}
                      >
                        {condition.name}
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Colors (IDs)</span>
                  </label>
                  <input
                    type="text"
                    name="yaga_colors_id_map"
                    class="input input-bordered w-full"
                    value={
                      if @item.yaga_colors_id_map,
                        do: Enum.join(@item.yaga_colors_id_map, ", "),
                        else: ""
                    }
                    placeholder="1, 3, 5"
                  />
                  <label class="label">
                    <span class="label-text-alt">
                      <%= for color <- Enum.take(@colors, 5) do %>
                        <span class="badge badge-sm mr-1">
                          {color.yaga_id}:{color.name}
                        </span>
                      <% end %>
                      ...
                    </span>
                  </label>
                </div>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-semibold">Yaga Materials (IDs)</span>
                  </label>
                  <input
                    type="text"
                    name="yaga_materials_id_map"
                    class="input input-bordered w-full"
                    value={
                      if @item.yaga_materials_id_map,
                        do: Enum.join(@item.yaga_materials_id_map, ", "),
                        else: ""
                    }
                    placeholder="2, 4"
                  />
                  <label class="label">
                    <span class="label-text-alt">
                      <%= for material <- Enum.take(@materials, 5) do %>
                        <span class="badge badge-sm mr-1">
                          {material.yaga_id}:{material.name}
                        </span>
                      <% end %>
                      ...
                    </span>
                  </label>
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
          </div>
        </form>
      </div>
    </div>
    """
  end
end
