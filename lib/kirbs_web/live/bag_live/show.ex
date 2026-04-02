defmodule KirbsWeb.BagLive.Show do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Bag, Client, Image, Item}
  alias Kirbs.Services.FindFirstReviewTarget
  alias Kirbs.Services.FindNextBagItemToReview
  alias Kirbs.Services.Yaga.Importer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Subscribe to bag updates
    Phoenix.PubSub.subscribe(Kirbs.PubSub, "bag:#{id}")

    bag = Bag.get!(id) |> Ash.load!([:client, :images, items: [:images]])
    clients = Client.list!()

    upload_dir = Application.get_env(:kirbs, :image_upload_dir)

    {:ok,
     socket
     |> assign(:bag, bag)
     |> assign(:clients, clients)
     |> assign(:upload_dir, upload_dir)
     |> assign(:show_client_modal, false)
     |> assign(:creating_new_client, false)
     |> assign(:editing_client, false)
     |> assign(:show_import_modal, false)
     |> assign(:import_links, "")
     |> assign(:importing, false)
     |> assign(:delete_confirmation, false)
     |> assign(:selected, MapSet.new())}
  end

  @impl true
  def handle_event("show_client_modal", _params, socket) do
    {:noreply, assign(socket, :show_client_modal, true)}
  end

  @impl true
  def handle_event("close_client_modal", _params, socket) do
    {:noreply, assign(socket, show_client_modal: false, creating_new_client: false)}
  end

  @impl true
  def handle_event("toggle_new_client", _params, socket) do
    {:noreply, assign(socket, :creating_new_client, !socket.assigns.creating_new_client)}
  end

  @impl true
  def handle_event("select_client", %{"client_id" => client_id}, socket) do
    case Bag.update(socket.assigns.bag, %{client_id: client_id}) do
      {:ok, bag} ->
        bag = Ash.load!(bag, [:client, :images, items: [:images]])

        {:noreply,
         socket
         |> assign(:bag, bag)
         |> assign(:show_client_modal, false)
         |> put_flash(:info, "Client assigned successfully")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to assign client")}
    end
  end

  @impl true
  def handle_event("create_client", params, socket) do
    case Client.create(params) do
      {:ok, client} ->
        case Bag.update(socket.assigns.bag, %{client_id: client.id}) do
          {:ok, bag} ->
            bag = Ash.load!(bag, [:client, :images, items: [:images]])
            clients = Client.list!()

            {:noreply,
             socket
             |> assign(:bag, bag)
             |> assign(:clients, clients)
             |> assign(:show_client_modal, false)
             |> assign(:creating_new_client, false)
             |> put_flash(:info, "Client created and assigned successfully")}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, "Failed to assign client")}
        end

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to create client: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("confirm_client", _params, socket) do
    case Bag.update(socket.assigns.bag, %{status: :reviewed}) do
      {:ok, bag} ->
        bag = Ash.load!(bag, [:client, :images, items: [:images]])

        {:noreply,
         socket
         |> assign(:bag, bag)
         |> put_flash(:info, "Client confirmed!")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Failed to confirm client")}
    end
  end

  @impl true
  def handle_event("toggle_edit_client", _params, socket) do
    {:noreply, assign(socket, :editing_client, !socket.assigns.editing_client)}
  end

  @impl true
  def handle_event("update_client", params, socket) do
    case Ash.update(socket.assigns.bag.client, params) do
      {:ok, _client} ->
        bag = Ash.load!(socket.assigns.bag, [:client, :images, items: [:images]])

        {:noreply,
         socket
         |> assign(:bag, bag)
         |> assign(:editing_client, false)
         |> put_flash(:info, "Client updated successfully")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to update client: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("run_ai", _params, socket) do
    %{bag_id: socket.assigns.bag.id}
    |> Kirbs.Jobs.ProcessBagJob.new()
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "AI processing job scheduled")}
  end

  @impl true
  def handle_event("show_import_modal", _params, socket) do
    {:noreply, assign(socket, show_import_modal: true, import_links: "")}
  end

  @impl true
  def handle_event("close_import_modal", _params, socket) do
    {:noreply, assign(socket, show_import_modal: false, import_links: "", importing: false)}
  end

  @impl true
  def handle_event("update_import_links", %{"links" => links}, socket) do
    {:noreply, assign(socket, :import_links, links)}
  end

  @impl true
  def handle_event("import_from_yaga", %{"links" => links}, socket) do
    socket = socket |> assign(:importing, true) |> assign(:import_links, links)

    case Importer.run(socket.assigns.bag.id, links) do
      {:ok, %{imported: count, errors: errors}} ->
        bag = Bag.get!(socket.assigns.bag.id) |> Ash.load!([:client, :images, items: [:images]])

        socket =
          socket
          |> assign(:bag, bag)
          |> assign(:show_import_modal, false)
          |> assign(:import_links, "")
          |> assign(:importing, false)

        socket =
          if errors == [] do
            put_flash(socket, :info, "Imported #{count} product(s) successfully")
          else
            put_flash(
              socket,
              :warning,
              "Imported #{count} product(s). Errors: #{Enum.join(errors, "; ")}"
            )
          end

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Import failed: #{reason}")}
    end
  end

  @impl true
  def handle_event("review_bag", _params, socket) do
    case FindNextBagItemToReview.run(socket.assigns.bag.id) do
      {:ok, nil} ->
        {:noreply, put_flash(socket, :info, "No items to review in this bag!")}

      {:ok, item_id} ->
        {:noreply,
         push_navigate(socket, to: ~p"/items/#{item_id}?bag_id=#{socket.assigns.bag.id}")}
    end
  end

  @impl true
  def handle_event("review_next", _params, socket) do
    case FindFirstReviewTarget.run() do
      {:ok, nil} ->
        {:noreply,
         socket
         |> put_flash(:info, "All done reviewing!")
         |> push_navigate(to: ~p"/dashboard")}

      {:ok, {:bag, bag_id}} ->
        {:noreply, push_navigate(socket, to: ~p"/bags/#{bag_id}")}

      {:ok, {:item, item_id}} ->
        {:noreply, push_navigate(socket, to: ~p"/items/#{item_id}")}
    end
  end

  @impl true
  def handle_event("delete_bag", _params, socket) do
    if socket.assigns.delete_confirmation do
      bag = socket.assigns.bag
      upload_dir = Application.get_env(:kirbs, :image_upload_dir)

      # Delete item images and items
      Enum.each(bag.items, fn item ->
        Enum.each(item.images, fn image ->
          File.rm(Path.join(upload_dir, image.path))
          Image.destroy(image)
        end)

        Ash.destroy!(item)
      end)

      # Delete bag images
      Enum.each(bag.images, fn image ->
        File.rm(Path.join(upload_dir, image.path))
        Image.destroy(image)
      end)

      case Bag.destroy(bag) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Bag deleted successfully")
           |> push_navigate(to: ~p"/bags")}

        {:error, _error} ->
          {:noreply,
           socket
           |> assign(:delete_confirmation, false)
           |> put_flash(:error, "Failed to delete bag")}
      end
    else
      {:noreply, assign(socket, :delete_confirmation, true)}
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

    for item <- socket.assigns.bag.items,
        MapSet.member?(socket.assigns.selected, item.id) do
      Item.update(item, %{combination_group: group})
    end

    {:noreply, socket |> assign(:selected, MapSet.new()) |> reload_bag()}
  end

  @impl true
  def handle_event("unlink_combination", %{"group" => group}, socket) do
    for item <- socket.assigns.bag.items,
        item.combination_group == group do
      Item.update(item, %{combination_group: nil})
    end

    {:noreply, reload_bag(socket)}
  end

  defp reload_bag(socket) do
    bag = Bag.get!(socket.assigns.bag.id) |> Ash.load!([:client, :images, items: [:images]])
    assign(socket, :bag, bag)
  end

  @impl true
  def handle_info({:bag_processed, _bag_id}, socket) do
    # Reload bag data when AI processing completes
    bag = Bag.get!(socket.assigns.bag.id) |> Ash.load!([:client, :images, items: [:images]])

    {:noreply, assign(socket, :bag, bag)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Bag #{@bag.number}</h1>
          <div class="flex gap-2">
            <button
              class={"btn btn-sm #{if @delete_confirmation, do: "btn-error", else: "btn-ghost"}"}
              phx-click="delete_bag"
            >
              {if @delete_confirmation, do: "Confirm Delete?", else: "Delete"}
            </button>
            <button class="btn btn-accent" phx-click="review_next">
              Review Next
            </button>
            <.link navigate="/bags" class="btn btn-ghost">
              Back to Bags
            </.link>
          </div>
        </div>
        
    <!-- Bag Photos -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Bag Photos</h2>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
              <%= for image <- @bag.images do %>
                <div class="aspect-square bg-base-200 rounded-lg overflow-hidden">
                  <img
                    src={"/uploads/#{image.path}"}
                    alt="Bag photo"
                    class="w-full h-full object-cover"
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Client Info -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <div class="flex justify-between items-start">
              <h2 class="card-title">Client Information</h2>
              <div class="flex flex-wrap gap-2 justify-end">
                <button class="btn btn-accent btn-sm" phx-click="run_ai">
                  Run AI
                </button>
                <%= if @bag.client && !@editing_client do %>
                  <button class="btn btn-secondary btn-sm" phx-click="toggle_edit_client">
                    Edit Client
                  </button>
                  <%= if @bag.status != :reviewed do %>
                    <button
                      class="btn btn-success btn-sm"
                      phx-click="confirm_client"
                    >
                      Confirm Client
                    </button>
                  <% end %>
                <% end %>
                <button class="btn btn-primary btn-sm" phx-click="show_client_modal">
                  {if @bag.client, do: "Change Client", else: "Assign Client"}
                </button>
              </div>
            </div>

            <%= if @bag.client do %>
              <%= if @editing_client do %>
                <form phx-submit="update_client" class="mt-4">
                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Name *</span>
                    </label>
                    <input
                      type="text"
                      name="name"
                      value={@bag.client.name}
                      class="input input-bordered"
                      required
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Phone *</span>
                    </label>
                    <input
                      type="tel"
                      name="phone"
                      value={@bag.client.phone}
                      class="input input-bordered"
                      required
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Email</span>
                    </label>
                    <input
                      type="email"
                      name="email"
                      value={@bag.client.email}
                      class="input input-bordered"
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">IBAN</span>
                    </label>
                    <input
                      type="text"
                      name="iban"
                      value={@bag.client.iban}
                      class="input input-bordered"
                    />
                  </div>

                  <div class="flex gap-2">
                    <button type="submit" class="btn btn-primary">
                      Save Changes
                    </button>
                    <button type="button" class="btn" phx-click="toggle_edit_client">
                      Cancel
                    </button>
                  </div>
                </form>
              <% else %>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                  <div>
                    <span class="font-semibold">Name:</span>
                    <span class="ml-2">{@bag.client.name}</span>
                  </div>
                  <div>
                    <span class="font-semibold">Phone:</span>
                    <span class="ml-2">{@bag.client.phone}</span>
                  </div>
                  <div>
                    <span class="font-semibold">Email:</span>
                    <span class="ml-2">{@bag.client.email || "N/A"}</span>
                  </div>
                  <div>
                    <span class="font-semibold">IBAN:</span>
                    <span class="ml-2">{@bag.client.iban || "N/A"}</span>
                  </div>
                </div>
              <% end %>
            <% else %>
              <div class="alert alert-warning mt-4">
                <span>No client assigned to this bag</span>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Items List -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex justify-between items-center">
              <h2 class="card-title">Items ({length(@bag.items)})</h2>
              <div class="flex gap-2">
                <button class="btn btn-secondary btn-sm" phx-click="review_bag">
                  Review Bag
                </button>
                <button class="btn btn-secondary btn-sm" phx-click="show_import_modal">
                  Import from Yaga
                </button>
                <.link navigate={~p"/bags/capture?bag_id=#{@bag.id}"} class="btn btn-primary btn-sm">
                  + Add More Items
                </.link>
              </div>
            </div>

            <div class="flex items-center gap-2 mt-4">
              <button
                class="btn btn-sm btn-outline"
                phx-click="link_combination"
                disabled={MapSet.size(@selected) < 2}
              >
                Link combination ({MapSet.size(@selected)})
              </button>
              <%= for {group, _items} <- combination_groups(@bag.items) do %>
                <button
                  class={"btn btn-sm btn-outline #{group_border_class(group, @bag.items)}"}
                  phx-click="unlink_combination"
                  phx-value-group={group}
                >
                  Unlink
                </button>
              <% end %>
            </div>

            <%= if @bag.items == [] do %>
              <div class="alert alert-info mt-4">
                <span>No items in this bag</span>
              </div>
            <% else %>
              <div class="grid gap-4 mt-4">
                <%= for item <- @bag.items do %>
                  <div class={"card bg-base-200 border-2 #{group_border_class(item.combination_group, @bag.items)}"}>
                    <div class="card-body">
                      <div class="flex gap-4 items-start">
                        <div class="flex items-center">
                          <input
                            type="checkbox"
                            class="checkbox"
                            checked={MapSet.member?(@selected, item.id)}
                            phx-click="toggle_select"
                            phx-value-id={item.id}
                          />
                        </div>
                        <%= if item.images != [] do %>
                          <div class="w-24 h-24 bg-base-300 rounded-lg overflow-hidden flex-shrink-0">
                            <img
                              src={"/uploads/#{List.first(item.images).path}"}
                              alt="Item photo"
                              class="w-full h-full object-cover"
                            />
                          </div>
                        <% end %>

                        <div class="flex-1">
                          <%= if item.size do %>
                            <p class="font-semibold">{item.size}</p>
                          <% end %>
                          <%= if item.brand do %>
                            <p class="text-sm">{item.brand}</p>
                          <% end %>
                          <p class="text-sm text-base-content/70">
                            {length(item.images)} photos
                          </p>
                          <div class="flex flex-wrap items-center gap-2 mt-2">
                            <%= if item.status == :uploaded_to_yaga && item.yaga_slug do %>
                              <a
                                href={"https://www.yaga.ee/kirbs-ee/toode/#{item.yaga_slug}"}
                                target="_blank"
                                class={"badge badge-sm #{status_badge_class(item.status)} underline hover:opacity-80"}
                              >
                                {item.status} ↗
                              </a>
                            <% else %>
                              <div class={"badge badge-sm #{status_badge_class(item.status)}"}>
                                {item.status}
                              </div>
                            <% end %>
                            <%= if item.combination_group do %>
                              <span class={"badge badge-sm #{group_border_class(item.combination_group, @bag.items)}"}>
                                combo
                              </span>
                            <% end %>
                            <%= if item.status == :sold && item.sold_price do %>
                              <span class="text-sm text-success font-semibold">
                                €{item.sold_price}
                              </span>
                              <%= if item.sold_at do %>
                                <span class="text-xs text-base-content/60">
                                  {Calendar.strftime(item.sold_at, "%Y-%m-%d")}
                                </span>
                              <% end %>
                            <% end %>
                          </div>
                        </div>

                        <.link navigate={~p"/items/#{item.id}"} class="btn btn-primary btn-sm">
                          Details
                        </.link>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Client Modal -->
        <%= if @show_client_modal do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <h3 class="font-bold text-lg mb-4">
                {if @creating_new_client, do: "Create New Client", else: "Select Client"}
              </h3>

              <%= if @creating_new_client do %>
                <!-- Create New Client Form -->
                <form phx-submit="create_client">
                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Name *</span>
                    </label>
                    <input
                      type="text"
                      name="name"
                      class="input input-bordered"
                      required
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Phone *</span>
                    </label>
                    <input
                      type="tel"
                      name="phone"
                      class="input input-bordered"
                      required
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">Email</span>
                    </label>
                    <input
                      type="email"
                      name="email"
                      class="input input-bordered"
                    />
                  </div>

                  <div class="form-control mb-4">
                    <label class="label">
                      <span class="label-text">IBAN *</span>
                    </label>
                    <input
                      type="text"
                      name="iban"
                      class="input input-bordered"
                      required
                    />
                  </div>

                  <div class="modal-action">
                    <button type="button" class="btn" phx-click="toggle_new_client">
                      Back to List
                    </button>
                    <button type="submit" class="btn btn-primary">
                      Create & Assign
                    </button>
                  </div>
                </form>
              <% else %>
                <!-- Select Existing Client -->
                <div class="mb-4">
                  <button class="btn btn-success btn-sm" phx-click="toggle_new_client">
                    + Create New Client
                  </button>
                </div>

                <div class="max-h-96 overflow-y-auto">
                  <%= for client <- @clients do %>
                    <div
                      class="card bg-base-200 mb-2 cursor-pointer hover:bg-base-300"
                      phx-click="select_client"
                      phx-value-client_id={client.id}
                    >
                      <div class="card-body p-4">
                        <h4 class="font-semibold">{client.name}</h4>
                        <p class="text-sm text-base-content/70">
                          {client.phone} • {client.email || "No email"}
                        </p>
                      </div>
                    </div>
                  <% end %>
                </div>

                <div class="modal-action">
                  <button class="btn" phx-click="close_client_modal">Close</button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Import from Yaga Modal -->
        <%= if @show_import_modal do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <h3 class="font-bold text-lg mb-4">Import from Yaga</h3>

              <p class="text-sm text-base-content/70 mb-4">
                Paste yaga.ee product links below (one per line or comma-separated).
              </p>

              <form phx-change="update_import_links" phx-submit="import_from_yaga">
                <div class="form-control">
                  <textarea
                    class="textarea textarea-bordered h-48 font-mono text-sm"
                    placeholder="https://www.yaga.ee/kirbs-ee/toode/abc123&#10;https://www.yaga.ee/kirbs-ee/toode/def456"
                    name="links"
                    disabled={@importing}
                  >{@import_links}</textarea>
                </div>

                <div class="modal-action">
                  <button
                    type="button"
                    class="btn"
                    phx-click="close_import_modal"
                    disabled={@importing}
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="btn btn-primary"
                    disabled={@importing || @import_links == ""}
                  >
                    <%= if @importing do %>
                      <span class="loading loading-spinner loading-sm"></span> Importing...
                    <% else %>
                      Import
                    <% end %>
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
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

  defp status_badge_class(:sold), do: "badge-success"
  defp status_badge_class(:uploaded_to_yaga), do: "badge-success"
  defp status_badge_class(:reviewed), do: "badge-info"
  defp status_badge_class(:upload_failed), do: "badge-error"
  defp status_badge_class(_), do: ""
end
