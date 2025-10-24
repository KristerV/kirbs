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
    <div class="container mx-auto p-4">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Bags</h1>

        <.link
          navigate={~p"/bags/capture"}
          class="bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
        >
          Start New Bag
        </.link>
      </div>

      <div class="bg-white shadow-md rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                ID
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Created At
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for bag <- @bags do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <%= bag.id %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <%= Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-blue-600">
                  <.link navigate={~p"/bags/#{bag.id}"}>View</.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if Enum.empty?(@bags) do %>
          <div class="text-center py-12 text-gray-500">
            <p>No bags yet. Start by creating a new bag!</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
