defmodule KirbsWeb.DashboardLive.Index do
  use KirbsWeb, :live_view

  import Ecto.Query
  alias Kirbs.Resources.Item
  alias Kirbs.Resources.Bag
  alias Kirbs.Resources.Payout
  alias Kirbs.Repo

  @impl true
  def mount(_params, _session, socket) do
    items = Item.list!()
    bags = Bag |> Ash.read!()

    sold_items_list = Enum.filter(items, &(&1.status == :sold && &1.sold_price != nil))
    sold_count = length(sold_items_list)

    sold_total =
      Enum.reduce(sold_items_list, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, item.sold_price)
      end)

    # Row 1: Money stats
    total_profit =
      sold_total |> Decimal.div(2) |> Decimal.round(2) |> Decimal.to_float()

    avg_item_value =
      if sold_count > 0 do
        sold_total |> Decimal.div(sold_count) |> Decimal.round(2) |> Decimal.to_float()
      else
        0.0
      end

    cutoff = DateTime.utc_now() |> DateTime.add(-20, :day)
    mature_bags = Enum.filter(bags, &(DateTime.compare(&1.created_at, cutoff) == :lt))

    avg_bag_value =
      if length(mature_bags) > 0 do
        sold_total |> Decimal.div(length(mature_bags)) |> Decimal.round(2) |> Decimal.to_float()
      else
        0.0
      end

    uploaded_count = Enum.count(items, &(&1.status == :uploaded_to_yaga))

    sell_through_rate =
      if uploaded_count + sold_count > 0 do
        Float.round(sold_count / (uploaded_count + sold_count) * 100, 1)
      else
        0.0
      end

    # Unsent payouts
    payouts = Payout.list!()
    total_paid = Enum.reduce(payouts, Decimal.new(0), fn p, acc -> Decimal.add(acc, p.amount) end)
    client_share = Decimal.div(sold_total, 2)

    unsent_payouts =
      Decimal.sub(client_share, total_paid) |> Decimal.round(2) |> Decimal.to_float()

    # Row 2: Processing stats
    needs_review = Enum.count(items, &(&1.status in [:pending, :ai_processed]))
    needs_upload = Enum.count(items, &(&1.status == :reviewed))

    # Avg items per bag (excluding empty bags)
    items_by_bag = Enum.group_by(items, & &1.bag_id)
    non_empty_bags = Enum.count(items_by_bag)

    avg_items_per_bag =
      if non_empty_bags > 0 do
        Float.round(length(items) / non_empty_bags, 1)
      else
        0.0
      end

    # Check for failed/retryable Oban jobs
    failed_jobs_count =
      from(j in "oban_jobs",
        where: j.state in ["retryable", "discarded"],
        select: count(j.id)
      )
      |> Repo.one()

    # Calculate upload directory size
    upload_dir_size = get_upload_dir_size()

    # Fetch dashboard lists
    fastest_sold = Item.fastest_sold!()
    recently_sold = Item.recently_sold!()

    {:ok,
     socket
     |> assign(:total_profit, total_profit)
     |> assign(:avg_item_value, avg_item_value)
     |> assign(:avg_bag_value, avg_bag_value)
     |> assign(:sell_through_rate, sell_through_rate)
     |> assign(:unsent_payouts, unsent_payouts)
     |> assign(:needs_review, needs_review)
     |> assign(:needs_upload, needs_upload)
     |> assign(:uploaded_items, uploaded_count)
     |> assign(:avg_items_per_bag, avg_items_per_bag)
     |> assign(:upload_dir_size, upload_dir_size)
     |> assign(:monthly_earnings_chart, build_monthly_earnings_chart(items, bags))
     |> assign(:seasonal_chart, build_seasonal_chart(items))
     |> assign(:daily_chart, build_daily_chart(items, bags))
     |> assign(:failed_jobs_count, failed_jobs_count)
     |> assign(:fastest_sold, fastest_sold)
     |> assign(:recently_sold, recently_sold)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-7xl mx-auto p-6">
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
        
    <!-- Money Stats -->
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Total Profit</div>
              <div class="stat-value text-sm text-green-400">&euro;{@total_profit}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Avg Item Value</div>
              <div class="stat-value text-sm">&euro;{@avg_item_value}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Avg Bag Value</div>
              <div class="stat-value text-sm">&euro;{@avg_bag_value}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Sell-through</div>
              <div class="stat-value text-sm">{@sell_through_rate}%</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Unsent Payouts</div>
              <div class="stat-value text-sm text-warning">&euro;{@unsent_payouts}</div>
            </div>
          </div>
        </div>
        
    <!-- Monthly Earnings -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Monthly Earnings</h2>
            <div class="h-64">
              <canvas
                id="monthly-earnings-chart"
                phx-hook="MonthlyEarningsChart"
                data-chart-data={Jason.encode!(@monthly_earnings_chart)}
              >
              </canvas>
            </div>
          </div>
        </div>
        
    <!-- Seasonal Chart -->
        <div class="card bg-base-100 shadow-xl mt-8">
          <div class="card-body">
            <h2 class="card-title">Seasonal Comparison</h2>
            <div class="h-64">
              <canvas
                id="seasonal-chart"
                phx-hook="SeasonalChart"
                data-chart-data={Jason.encode!(@seasonal_chart)}
              >
              </canvas>
            </div>
          </div>
        </div>
        
    <!-- Processing Stats -->
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mt-8 mb-8">
          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Needs Review</div>
              <div class="stat-value text-warning">{@needs_review}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Needs Upload</div>
              <div class="stat-value text-orange-400">{@needs_upload}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Uploaded to Yaga</div>
              <div class="stat-value text-blue-400">{@uploaded_items}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Avg Items / Bag</div>
              <div class="stat-value text-sm">{@avg_items_per_bag}</div>
            </div>
          </div>

          <div class="stats bg-base-100 shadow">
            <div class="stat">
              <div class="stat-title">Storage Used</div>
              <div class="stat-value text-sm">{@upload_dir_size}</div>
            </div>
          </div>
        </div>
        
    <!-- Last 14 Days -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Last 14 Days</h2>
            <div class="h-64">
              <canvas
                id="daily-chart"
                phx-hook="DailyChart"
                data-chart-data={Jason.encode!(@daily_chart)}
              >
              </canvas>
            </div>
          </div>
        </div>
        
    <!-- Item Lists -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-8">
          <!-- Fastest Sold -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Fastest Sales</h2>
              <%= if Enum.empty?(@fastest_sold) do %>
                <p class="text-base-content/50">No sold items yet</p>
              <% else %>
                <div class="grid grid-cols-5 gap-2">
                  <%= for item <- @fastest_sold do %>
                    <.link navigate={~p"/items/#{item.id}"} class="flex flex-col hover:opacity-80">
                      <%= if first_image = List.first(item.images) do %>
                        <img
                          src={"/uploads/#{first_image.path}"}
                          alt=""
                          class="w-full aspect-square object-cover rounded"
                        />
                      <% else %>
                        <div class="w-full aspect-square bg-base-300 rounded"></div>
                      <% end %>
                      <div class="text-xs text-right mt-1 font-medium">
                        {format_duration(item.seconds_to_sell)}
                      </div>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Recently Sold -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Recently Sold</h2>
              <%= if Enum.empty?(@recently_sold) do %>
                <p class="text-base-content/50">No sold items yet</p>
              <% else %>
                <div class="grid grid-cols-5 gap-2">
                  <%= for item <- @recently_sold do %>
                    <.link navigate={~p"/items/#{item.id}"} class="flex flex-col hover:opacity-80">
                      <%= if first_image = List.first(item.images) do %>
                        <img
                          src={"/uploads/#{first_image.path}"}
                          alt=""
                          class="w-full aspect-square object-cover rounded"
                        />
                      <% else %>
                        <div class="w-full aspect-square bg-base-300 rounded"></div>
                      <% end %>
                      <div class="text-xs text-right mt-1">{format_relative_time(item.sold_at)}</div>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_upload_dir_size do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir)

    case File.ls(upload_dir) do
      {:ok, files} ->
        total_bytes =
          files
          |> Enum.map(&Path.join(upload_dir, &1))
          |> Enum.filter(&File.regular?/1)
          |> Enum.reduce(0, fn path, acc ->
            case File.stat(path) do
              {:ok, %{size: size}} -> acc + size
              _ -> acc
            end
          end)

        format_bytes(total_bytes)

      _ ->
        "N/A"
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 1)} GB"

  defp format_duration(nil), do: "—"

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    "#{minutes}m"
  end

  defp format_duration(seconds) when seconds < 86400 do
    hours = div(seconds, 3600)
    "#{hours}h"
  end

  defp format_duration(seconds) do
    days = div(seconds, 86400)
    "#{days}d"
  end

  defp format_relative_time(nil), do: "—"

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%d %b")
    end
  end

  defp build_monthly_earnings_chart(items, bags) do
    # Group bags by month
    bags_by_month =
      bags
      |> Enum.group_by(fn bag ->
        date = DateTime.to_date(bag.created_at)
        {date.year, date.month}
      end)
      |> Enum.map(fn {key, month_bags} -> {key, length(month_bags)} end)
      |> Map.new()

    # Group uploaded items by month
    uploaded_by_month =
      items
      |> Enum.filter(&(&1.uploaded_at != nil))
      |> Enum.group_by(fn item ->
        date = DateTime.to_date(item.uploaded_at)
        {date.year, date.month}
      end)
      |> Enum.map(fn {key, items} -> {key, length(items)} end)
      |> Map.new()

    # Group sold items by month (count and profit)
    sold_by_month =
      items
      |> Enum.filter(&(&1.sold_at != nil))
      |> Enum.group_by(fn item ->
        date = DateTime.to_date(item.sold_at)
        {date.year, date.month}
      end)
      |> Enum.map(fn {key, month_items} ->
        count = length(month_items)

        profit =
          Enum.reduce(month_items, Decimal.new(0), fn item, acc ->
            if item.sold_price do
              Decimal.add(acc, Decimal.div(item.sold_price, 2))
            else
              acc
            end
          end)

        {key, %{count: count, profit: Decimal.to_float(profit)}}
      end)
      |> Map.new()

    # Get all months that have any data
    all_months =
      (Map.keys(bags_by_month) ++ Map.keys(uploaded_by_month) ++ Map.keys(sold_by_month))
      |> Enum.uniq()
      |> Enum.sort()

    labels =
      Enum.map(all_months, fn {year, month} ->
        Date.new!(year, month, 1) |> Calendar.strftime("%b %Y")
      end)

    bags_count = Enum.map(all_months, fn key -> Map.get(bags_by_month, key, 0) end)
    uploaded = Enum.map(all_months, fn key -> Map.get(uploaded_by_month, key, 0) end)

    sold_count =
      Enum.map(all_months, fn key -> Map.get(sold_by_month, key, %{count: 0}).count end)

    sold_profit =
      Enum.map(all_months, fn key -> Map.get(sold_by_month, key, %{profit: 0}).profit end)

    %{
      labels: labels,
      bags_count: bags_count,
      uploaded: uploaded,
      sold_count: sold_count,
      sold_profit: sold_profit
    }
  end

  defp build_seasonal_chart(items) do
    month_labels = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    sold_items = Enum.filter(items, &(&1.sold_at != nil && &1.sold_price != nil))

    # Group by year and month, sum profit (50%)
    by_year_month =
      sold_items
      |> Enum.group_by(fn item ->
        date = DateTime.to_date(item.sold_at)
        {date.year, date.month}
      end)
      |> Enum.map(fn {{year, month}, month_items} ->
        profit =
          Enum.reduce(month_items, Decimal.new(0), fn item, acc ->
            Decimal.add(acc, Decimal.div(item.sold_price, 2))
          end)

        {year, month, Decimal.to_float(profit)}
      end)

    years =
      by_year_month
      |> Enum.map(fn {year, _, _} -> year end)
      |> Enum.uniq()
      |> Enum.sort()

    datasets =
      Enum.map(years, fn year ->
        data =
          Enum.map(1..12, fn month ->
            case Enum.find(by_year_month, fn {y, m, _} -> y == year && m == month end) do
              {_, _, profit} -> profit
              nil -> nil
            end
          end)

        %{year: year, data: data}
      end)

    %{labels: month_labels, datasets: datasets}
  end

  defp build_daily_chart(items, bags) do
    today = Date.utc_today()
    days = Enum.map(13..0//-1, fn offset -> Date.add(today, -offset) end)

    bags_by_day =
      bags
      |> Enum.group_by(fn bag -> DateTime.to_date(bag.created_at) end)

    items_by_day =
      items
      |> Enum.group_by(fn item -> DateTime.to_date(item.created_at) end)

    labels =
      Enum.map(days, fn date ->
        Calendar.strftime(date, "%a %d")
      end)

    bags_data = Enum.map(days, fn day -> length(Map.get(bags_by_day, day, [])) end)
    items_data = Enum.map(days, fn day -> length(Map.get(items_by_day, day, [])) end)

    bags_with_items_data =
      Enum.map(days, fn day ->
        Map.get(items_by_day, day, [])
        |> Enum.map(& &1.bag_id)
        |> Enum.uniq()
        |> length()
      end)

    %{
      labels: labels,
      bags: bags_data,
      items: items_data,
      bags_with_items: bags_with_items_data
    }
  end
end
