defmodule KirbsWeb.ReviewLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Bag

  @impl true
  def mount(_params, _session, socket) do
    bags = Bag.list!() |> Ash.load!([:client, :items])

    {:ok, assign(socket, :bags, bags)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Review Queue</h1>

        <%= if @bags == [] do %>
          <div class="alert alert-info">
            <span>No bags found. Start by capturing a new bag.</span>
          </div>
        <% else %>
          <div class="grid gap-4">
            <%= for bag <- @bags do %>
              <div class="card bg-base-100 shadow-xl">
                <div class="card-body">
                  <div class="flex justify-between items-start">
                    <div class="flex-1">
                      <h2 class="card-title">
                        Bag #{String.slice(bag.id, 0..7)}
                      </h2>
                      <p class="text-sm text-base-content/70">
                        Created: {Calendar.strftime(bag.created_at, "%Y-%m-%d %H:%M")}
                      </p>
                      <%= if bag.client do %>
                        <div class="badge badge-success mt-2">
                          Client: {bag.client.name}
                        </div>
                      <% else %>
                        <div class="badge badge-warning mt-2">
                          No client assigned
                        </div>
                      <% end %>
                      <div class="mt-2">
                        <span class="text-sm font-semibold">
                          {length(bag.items)} items
                        </span>
                      </div>
                    </div>

                    <div class="card-actions">
                      <.link navigate={~p"/bags/#{bag.id}"} class="btn btn-primary">
                        Review
                      </.link>
                    </div>
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
