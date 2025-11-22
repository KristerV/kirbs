defmodule KirbsWeb.DashboardLive.Index do
  use KirbsWeb, :live_view

  import Ecto.Query
  alias Kirbs.Resources.{Bag, Client, Item}
  alias Kirbs.Repo

  @impl true
  def mount(_params, _session, socket) do
    bags = Bag.list!()
    clients = Client.list!()
    items = Item.list!()

    # Count items by status
    pending_items = Enum.count(items, &(&1.status == :pending))
    ai_processed_items = Enum.count(items, &(&1.status == :ai_processed))
    reviewed_items = Enum.count(items, &(&1.status == :reviewed))
    uploaded_items = Enum.count(items, &(&1.status == :uploaded_to_yaga))
    sold_items = Enum.count(items, &(&1.status == :sold))
    failed_uploads = Enum.count(items, &(&1.status == :upload_failed))

    # Calculate revenue
    total_revenue =
      items
      |> Enum.filter(&(&1.sold_price != nil))
      |> Enum.reduce(Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.sold_price)
      end)

    # Calculate client payouts (50% split)
    total_payouts =
      if Decimal.compare(total_revenue, Decimal.new(0)) == :gt do
        Decimal.div(total_revenue, Decimal.new(2))
      else
        Decimal.new(0)
      end

    # Check for failed/retryable Oban jobs
    failed_jobs_count =
      from(j in "oban_jobs",
        where: j.state in ["retryable", "discarded"],
        select: count(j.id)
      )
      |> Repo.one()

    {:ok,
     socket
     |> assign(:total_bags, length(bags))
     |> assign(:total_clients, length(clients))
     |> assign(:total_items, length(items))
     |> assign(:pending_items, pending_items)
     |> assign(:ai_processed_items, ai_processed_items)
     |> assign(:reviewed_items, reviewed_items)
     |> assign(:uploaded_items, uploaded_items)
     |> assign(:sold_items, sold_items)
     |> assign(:failed_uploads, failed_uploads)
     |> assign(:total_revenue, total_revenue)
     |> assign(:total_payouts, total_payouts)
     |> assign(:failed_jobs_count, failed_jobs_count)
     |> assign(:checking_sold, false)}
  end

  @impl true
  def handle_event("check_sold_items", _params, socket) do
    socket = assign(socket, :checking_sold, true)

    Kirbs.Jobs.CheckSoldItemsJob.new(%{})
    |> Oban.insert()

    {:noreply,
     socket
     |> assign(:checking_sold, false)
     |> put_flash(:info, "Checking for sold items...")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-7xl mx-auto p-6">
        <h1 class="text-4xl font-bold mb-8">Dashboard</h1>

        <%= if @failed_jobs_count > 0 do %>
          <div class="alert bg-error/10 border-2 border-error shadow-lg mb-8">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="stroke-error shrink-0 h-6 w-6"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div>
              <h3 class="font-bold text-red-400">Background Jobs Failed</h3>
              <div class="text-sm text-red-300/90">
                {@failed_jobs_count} job(s) failed. This might indicate an expired JWT token. Check Settings.
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Overview Stats -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Clients</div>
              <div class="stat-value">{@total_clients}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Bags</div>
              <div class="stat-value">{@total_bags}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Items</div>
              <div class="stat-value">{@total_items}</div>
            </div>
          </div>
        </div>
        
    <!-- Item Status -->
        <div class="card bg-base-100 shadow-xl mb-8">
          <div class="card-body">
            <div class="flex justify-between items-center mb-4">
              <h2 class="card-title">Items by Status</h2>
              <button class="btn btn-sm btn-secondary" phx-click="check_sold_items">
                Check Sold Items
              </button>
            </div>
            <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Pending</div>
                <div class="stat-value text-warning">{@pending_items}</div>
              </div>

              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">AI Processed</div>
                <div class="stat-value text-info">{@ai_processed_items}</div>
              </div>

              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Reviewed</div>
                <div class="stat-value text-success">{@reviewed_items}</div>
              </div>

              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Uploaded to Yaga</div>
                <div class="stat-value text-success">{@uploaded_items}</div>
              </div>

              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Sold</div>
                <div class="stat-value text-success">{@sold_items}</div>
              </div>

              <%= if @failed_uploads > 0 do %>
                <div class="stat bg-error/10 rounded-lg">
                  <div class="stat-title text-error">Failed Uploads</div>
                  <div class="stat-value text-error">{@failed_uploads}</div>
                  <div class="stat-desc">Needs attention</div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Financial Stats -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Revenue</div>
              <div class="stat-value text-success">€{@total_revenue}</div>
              <div class="stat-desc">From sold items</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Client Payouts</div>
              <div class="stat-value text-primary">€{@total_payouts}</div>
              <div class="stat-desc">50% split</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
