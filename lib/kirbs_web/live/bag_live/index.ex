defmodule KirbsWeb.BagLive.Index do
  use KirbsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    bags = Kirbs.Resources.Bag.list!()

    {:ok,
     socket
     |> assign(:bags, bags)
     |> assign(:page_title, "Bags")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Bags</h1>

        <%= if Enum.empty?(@bags) do %>
          <div class="alert alert-info">
            <span>No bags yet. Start by creating a new bag!</span>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Created At</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for bag <- @bags do %>
                      <tr>
                        <td><%= String.slice(bag.id, 0..7) %></td>
                        <td><%= Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M") %></td>
                        <td>
                          <.link navigate={~p"/bags/#{bag.id}"} class="btn btn-primary btn-sm">
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
        <% end %>
      </div>
    </div>
    """
  end
end
