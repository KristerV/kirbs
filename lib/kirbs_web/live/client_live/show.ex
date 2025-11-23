defmodule KirbsWeb.ClientLive.Show do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Client
  alias Kirbs.Services.ClientMerge

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    client = Ash.get!(Client, id) |> Ash.load!([:bags])
    all_clients = Client.list!() |> Enum.reject(&(&1.id == id))

    {:ok,
     socket
     |> assign(:client, client)
     |> assign(:editing, false)
     |> assign(:show_merge_modal, false)
     |> assign(:all_clients, all_clients)
     |> assign(:selected_merge_client_id, nil)
     |> assign(:page_title, client.name)}
  end

  @impl true
  def handle_event("toggle_edit", _params, socket) do
    {:noreply, assign(socket, :editing, !socket.assigns.editing)}
  end

  @impl true
  def handle_event("update_client", params, socket) do
    case Ash.update(socket.assigns.client, params) do
      {:ok, client} ->
        client = Ash.load!(client, [:bags])

        {:noreply,
         socket
         |> assign(:client, client)
         |> assign(:editing, false)
         |> put_flash(:info, "Client updated successfully")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to update client: #{inspect(error)}")}
    end
  end

  @impl true
  def handle_event("show_merge_modal", _params, socket) do
    {:noreply, assign(socket, :show_merge_modal, true)}
  end

  @impl true
  def handle_event("close_merge_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_merge_modal, false)
     |> assign(:selected_merge_client_id, nil)}
  end

  @impl true
  def handle_event("select_merge_client", params, socket) do
    client_id = params["client_id"]
    client_id = if client_id == "", do: nil, else: client_id
    {:noreply, assign(socket, :selected_merge_client_id, client_id)}
  end

  @impl true
  def handle_event("confirm_merge", _params, socket) do
    primary_client_id = socket.assigns.selected_merge_client_id
    secondary_client_id = socket.assigns.client.id

    case ClientMerge.run(primary_client_id, secondary_client_id) do
      {:ok, _primary} ->
        {:noreply,
         socket
         |> put_flash(:info, "Clients merged successfully")
         |> push_navigate(to: ~p"/clients/#{primary_client_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to merge: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">{@client.name}</h1>
          <div class="flex gap-2">
            <button class="btn btn-secondary" phx-click="show_merge_modal">
              Merge into another client
            </button>
            <.link navigate="/clients" class="btn btn-ghost">
              Back to Clients
            </.link>
          </div>
        </div>
        
    <!-- Client Info -->
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <div class="flex justify-between items-start">
              <h2 class="card-title">Client Information</h2>
              <button class="btn btn-primary btn-sm" phx-click="toggle_edit">
                {if @editing, do: "Cancel", else: "Edit"}
              </button>
            </div>

            <%= if @editing do %>
              <form phx-submit="update_client" class="mt-4">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Name *</span>
                  </label>
                  <input
                    type="text"
                    name="name"
                    value={@client.name}
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
                    value={@client.phone}
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
                    value={@client.email}
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
                    value={@client.iban}
                    class="input input-bordered"
                  />
                </div>

                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary">
                    Save Changes
                  </button>
                  <button type="button" class="btn" phx-click="toggle_edit">
                    Cancel
                  </button>
                </div>
              </form>
            <% else %>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                <div>
                  <span class="font-semibold">Name:</span>
                  <span class="ml-2">{@client.name}</span>
                </div>
                <div>
                  <span class="font-semibold">Phone:</span>
                  <span class="ml-2">{@client.phone}</span>
                </div>
                <div>
                  <span class="font-semibold">Email:</span>
                  <span class="ml-2">{@client.email || "N/A"}</span>
                </div>
                <div>
                  <span class="font-semibold">IBAN:</span>
                  <span class="ml-2">{@client.iban || "N/A"}</span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Bags List -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Bags ({length(@client.bags)})</h2>

            <%= if @client.bags == [] do %>
              <div class="alert alert-info mt-4">
                <span>No bags for this client yet</span>
              </div>
            <% else %>
              <div class="overflow-x-auto mt-4">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Bag Number</th>
                      <th>Created At</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for bag <- @client.bags do %>
                      <tr>
                        <td>#{bag.number}</td>
                        <td>{Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M")}</td>
                        <td>
                          <.link navigate={~p"/bags/#{bag.id}"} class="btn btn-primary btn-sm">
                            View Bag
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <!-- Merge Modal -->
    <%= if @show_merge_modal do %>
      <div class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Merge into another client</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Select a client to merge this one into. All bags from {@client.name} will be moved to the selected client, and {@client.name} will be deleted.
          </p>

          <%= if @all_clients == [] do %>
            <div class="alert alert-warning">
              <span>No other clients available to merge</span>
            </div>
          <% else %>
            <form phx-change="select_merge_client" class="form-control mb-4">
              <label class="label">
                <span class="label-text">Client to merge</span>
              </label>
              <select
                class="select select-bordered w-full"
                name="client_id"
              >
                <option value="">Select a client...</option>
                <%= for client <- @all_clients do %>
                  <option value={client.id} selected={@selected_merge_client_id == client.id}>
                    {client.name} ({client.phone})
                  </option>
                <% end %>
              </select>
            </form>

            <%= if @selected_merge_client_id do %>
              <% selected = Enum.find(@all_clients, &(&1.id == @selected_merge_client_id)) %>
              <%= if selected do %>
                <div class="alert alert-warning mb-4">
                  <span>
                    This will move all bags from <strong>{@client.name}</strong>
                    to <strong>{selected.name}</strong>
                    and permanently delete {@client.name}.
                  </span>
                </div>
              <% end %>
            <% end %>
          <% end %>

          <div class="modal-action">
            <button class="btn" phx-click="close_merge_modal">Cancel</button>
            <%= if @selected_merge_client_id do %>
              <button class="btn btn-primary" phx-click="confirm_merge">
                Confirm Merge
              </button>
            <% end %>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="close_merge_modal"></div>
      </div>
    <% end %>
    """
  end
end
