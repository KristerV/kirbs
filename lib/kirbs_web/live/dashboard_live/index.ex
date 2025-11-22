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
    needs_review = Enum.count(items, &(&1.status in [:pending, :ai_processed, :reviewed]))
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

    # Build chart data for last 30 days
    chart_data = build_chart_data(items)

    {:ok,
     socket
     |> assign(:total_bags, length(bags))
     |> assign(:total_clients, length(clients))
     |> assign(:total_items, length(items))
     |> assign(:needs_review, needs_review)
     |> assign(:uploaded_items, uploaded_items)
     |> assign(:sold_items, sold_items)
     |> assign(:failed_uploads, failed_uploads)
     |> assign(:total_revenue, total_revenue)
     |> assign(:total_payouts, total_payouts)
     |> assign(:failed_jobs_count, failed_jobs_count)
     |> assign(:checking_sold, false)
     |> assign(:chart_data, chart_data)}
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
        
    <!-- 30 Day Chart -->
        <div class="card bg-base-100 shadow-xl mb-8">
          <div class="card-body">
            <h2 class="card-title">Last 30 Days</h2>
            <div class="h-80">
              <canvas
                id="dashboard-chart"
                phx-hook="DashboardChart"
                data-chart-data={Jason.encode!(@chart_data)}
              >
              </canvas>
            </div>
          </div>
        </div>
        
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
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div class="stat bg-base-200 rounded-lg">
                <div class="stat-title">Needs Review</div>
                <div class="stat-value text-warning">{@needs_review}</div>
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

  defp build_chart_data(items) do
    today = Date.utc_today()

    # Generate last 30 days
    dates =
      Enum.map(29..0//-1, fn days_ago ->
        Date.add(today, -days_ago)
      end)

    # Group items by created_at date
    items_by_created =
      items
      |> Enum.group_by(fn item ->
        item.created_at |> DateTime.to_date()
      end)

    # Group sold items by sold_at date
    items_by_sold =
      items
      |> Enum.filter(&(&1.sold_at != nil))
      |> Enum.group_by(fn item ->
        item.sold_at |> DateTime.to_date()
      end)

    # Build data arrays
    labels = Enum.map(dates, &Calendar.strftime(&1, "%d %b"))

    items_created =
      Enum.map(dates, fn date ->
        Map.get(items_by_created, date, []) |> length()
      end)

    items_sold =
      Enum.map(dates, fn date ->
        Map.get(items_by_sold, date, []) |> length()
      end)

    # Monthly burndown - start at 1000€, subtract cumulative profit
    goal = Decimal.new(1000)

    {burndown, _} =
      Enum.map_reduce(dates, Decimal.new(0), fn date, cumulative_profit ->
        day_profit =
          Map.get(items_by_sold, date, [])
          |> Enum.reduce(Decimal.new(0), fn item, acc ->
            if item.sold_price do
              Decimal.add(acc, Decimal.div(item.sold_price, 2))
            else
              acc
            end
          end)

        new_cumulative = Decimal.add(cumulative_profit, day_profit)
        remaining = Decimal.sub(goal, new_cumulative) |> Decimal.max(Decimal.new(0))
        {Decimal.to_float(remaining), new_cumulative}
      end)

    %{
      labels: labels,
      items_created: items_created,
      items_sold: items_sold,
      burndown: burndown
    }
  end
end
