defmodule KirbsWeb.ClientLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Client

  @impl true
  def mount(_params, _session, socket) do
    clients =
      Client
      |> Ash.Query.load(:bags)
      |> Ash.read!()

    {:ok,
     socket
     |> assign(:clients, clients)
     |> assign(:page_title, "Clients")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Clients</h1>

        <%= if Enum.empty?(@clients) do %>
          <div class="alert alert-info">
            <span>No clients yet.</span>
          </div>
        <% else %>
          <%!-- Desktop table view --%>
          <div class="hidden md:block card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Phone</th>
                      <th>Email</th>
                      <th>Bags</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for client <- @clients do %>
                      <tr>
                        <td>{client.name}</td>
                        <td>{client.phone}</td>
                        <td>{client.email || "N/A"}</td>
                        <td>{length(client.bags)}</td>
                        <td>
                          <.link navigate={~p"/clients/#{client.id}"} class="btn btn-primary btn-sm">
                            View
                          </.link>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- Mobile card view --%>
          <div class="md:hidden space-y-4">
            <%= for client <- @clients do %>
              <div class="card bg-base-100 shadow-xl">
                <div class="card-body">
                  <h3 class="font-bold text-lg">{client.name}</h3>
                  <div class="text-sm space-y-1 mt-2">
                    <p><span class="font-semibold">Phone:</span> {client.phone}</p>
                    <p><span class="font-semibold">Email:</span> {client.email || "N/A"}</p>
                    <p><span class="font-semibold">Bags:</span> {length(client.bags)}</p>
                  </div>
                  <div class="card-actions justify-end mt-4">
                    <.link navigate={~p"/clients/#{client.id}"} class="btn btn-primary btn-sm w-full">
                      View Client
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
