defmodule KirbsWeb.BagLive.Show do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Bag, Client, Image}
  alias Kirbs.Services.FindFirstReviewTarget

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Subscribe to bag updates
    Phoenix.PubSub.subscribe(Kirbs.PubSub, "bag:#{id}")

    bag = Bag.get!(id) |> Ash.load!([:client, :items, :images])
    clients = Client.list!()

    upload_dir = Application.get_env(:kirbs, :image_upload_dir)

    {:ok,
     socket
     |> assign(:bag, bag)
     |> assign(:clients, clients)
     |> assign(:upload_dir, upload_dir)
     |> assign(:show_client_modal, false)
     |> assign(:creating_new_client, false)
     |> assign(:editing_client, false)}
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
        bag = Ash.load!(bag, [:client, :items, :images])

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
            bag = Ash.load!(bag, [:client, :items, :images])
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
        bag = Ash.load!(bag, [:client, :items, :images])

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
        bag = Ash.load!(socket.assigns.bag, [:client, :items, :images])

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
  def handle_info({:bag_processed, _bag_id}, socket) do
    # Reload bag data when AI processing completes
    bag = Bag.get!(socket.assigns.bag.id) |> Ash.load!([:client, :items, :images])

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
              <.link navigate={~p"/bags/capture?bag_id=#{@bag.id}"} class="btn btn-primary btn-sm">
                + Add More Items
              </.link>
            </div>

            <%= if @bag.items == [] do %>
              <div class="alert alert-info mt-4">
                <span>No items in this bag</span>
              </div>
            <% else %>
              <div class="grid gap-4 mt-4">
                <%= for item <- @bag.items do %>
                  <% item_images = Image.list!() |> Enum.filter(&(&1.item_id == item.id)) %>
                  <div class="card bg-base-200">
                    <div class="card-body">
                      <div class="flex gap-4 items-start">
                        <%= if item_images != [] do %>
                          <div class="w-24 h-24 bg-base-300 rounded-lg overflow-hidden flex-shrink-0">
                            <img
                              src={"/uploads/#{List.first(item_images).path}"}
                              alt="Item photo"
                              class="w-full h-full object-cover"
                            />
                          </div>
                        <% end %>

                        <div class="flex-1">
                          <h3 class="font-semibold">
                            Item #{String.slice(item.id, 0..7)}
                          </h3>
                          <p class="text-sm text-base-content/70">
                            {length(item_images)} photos
                          </p>
                          <div class={"badge badge-sm mt-2 #{if item.status == :uploaded_to_yaga, do: "badge-success"}"}>
                            {item.status}
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
      </div>
    </div>
    """
  end
end
