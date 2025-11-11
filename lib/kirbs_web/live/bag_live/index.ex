defmodule KirbsWeb.BagLive.Index do
  use KirbsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    bags =
      Kirbs.Resources.Bag
      |> Ash.Query.load([
        :item_count,
        :bag_needs_review,
        :items_needing_review_count,
        :client,
        :images
      ])
      |> Ash.Query.sort(number: :asc)
      |> Ash.read!()

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
          <%!-- Desktop table view --%>
          <div class="hidden md:block card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Image</th>
                      <th>Number</th>
                      <th>Items</th>
                      <th>Bag Review</th>
                      <th>Items Need Review</th>
                      <th>Created At</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for bag <- @bags do %>
                      <tr>
                        <td>
                          <%= if first_image = List.first(bag.images) do %>
                            <img
                              src={"/uploads/#{first_image.path}"}
                              alt="Bag preview"
                              class="w-16 h-16 object-cover rounded"
                            />
                          <% else %>
                            <div class="w-16 h-16 bg-base-300 rounded flex items-center justify-center">
                              <span class="text-xs text-gray-400">No image</span>
                            </div>
                          <% end %>
                        </td>
                        <td>{bag.number}</td>
                        <td>{bag.item_count}</td>
                        <td>
                          <%= if bag.bag_needs_review do %>
                            <span class="badge badge-warning">Needs Review</span>
                          <% end %>
                        </td>
                        <td>
                          <%= if bag.items_needing_review_count > 0 do %>
                            <span class="text-yellow-500 font-bold">
                              {bag.items_needing_review_count}
                            </span>
                          <% end %>
                        </td>
                        <td>{Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M")}</td>
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

          <%!-- Mobile block view --%>
          <div class="md:hidden space-y-4">
            <%= for bag <- @bags do %>
              <div class="card bg-base-100 shadow-xl">
                <div class="card-body">
                  <div class="flex gap-4">
                    <%= if first_image = List.first(bag.images) do %>
                      <img
                        src={"/uploads/#{first_image.path}"}
                        alt="Bag preview"
                        class="w-24 h-24 object-cover rounded flex-shrink-0"
                      />
                    <% else %>
                      <div class="w-24 h-24 bg-base-300 rounded flex items-center justify-center flex-shrink-0">
                        <span class="text-xs text-gray-400">No image</span>
                      </div>
                    <% end %>

                    <div class="flex-1">
                      <h3 class="font-bold text-lg">Bag #{bag.number}</h3>
                      <div class="text-sm space-y-1 mt-2">
                        <p><span class="font-semibold">Items:</span> {bag.item_count}</p>
                        <%= if bag.bag_needs_review do %>
                          <p>
                            <span class="font-semibold">Bag Review:</span>
                            <span class="badge badge-warning badge-sm">Needs Review</span>
                          </p>
                        <% end %>
                        <%= if bag.items_needing_review_count > 0 do %>
                          <p>
                            <span class="font-semibold">Items Need Review:</span>
                            <span class="text-yellow-500 font-bold">
                              {bag.items_needing_review_count}
                            </span>
                          </p>
                        <% end %>
                        <p class="text-xs text-gray-500">
                          {Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M")}
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="card-actions justify-end mt-4">
                    <.link navigate={~p"/bags/#{bag.id}"} class="btn btn-primary btn-sm w-full">
                      View Bag
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
