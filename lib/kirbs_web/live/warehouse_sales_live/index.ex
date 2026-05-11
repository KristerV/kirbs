defmodule KirbsWeb.WarehouseSalesLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.{StatusChecker, WarehouseSaleDetector}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Warehouse Sales")
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:candidates, [])
     |> assign(:selected, nil)
     |> assign(:form_price, nil)
     |> assign(:form_sold_at, nil)
     |> start_async(:detect, fn -> WarehouseSaleDetector.run() end)}
  end

  @impl true
  def handle_async(:detect, {:ok, {:ok, candidates}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:candidates, candidates)}
  end

  def handle_async(:detect, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, inspect(reason))}
  end

  def handle_async(:detect, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Crashed: #{inspect(reason)}")}
  end

  @impl true
  def handle_event("open_modal", %{"item-id" => item_id}, socket) do
    candidate = Enum.find(socket.assigns.candidates, &(&1.item.id == item_id))
    detail = fetch_detail(candidate.yaga_slug)

    sold_at_date =
      cond do
        detail[:updated_at] -> DateTime.to_date(detail.updated_at)
        candidate.yaga_updated_at -> DateTime.to_date(candidate.yaga_updated_at)
        true -> Date.utc_today()
      end

    price = detail[:price] || candidate.listed_price

    {:noreply,
     socket
     |> assign(:selected, candidate)
     |> assign(:form_price, price && to_string(price))
     |> assign(:form_sold_at, Date.to_iso8601(sold_at_date))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  def handle_event("form_changed", %{"price" => price, "sold_at" => sold_at}, socket) do
    {:noreply,
     socket
     |> assign(:form_price, price)
     |> assign(:form_sold_at, sold_at)}
  end

  def handle_event("confirm_sold", %{"price" => price_str, "sold_at" => sold_at_str}, socket) do
    candidate = socket.assigns.selected
    price = Decimal.new(price_str)
    date = Date.from_iso8601!(sold_at_str)
    sold_at = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

    case Item.update(candidate.item, %{status: :sold, sold_price: price, sold_at: sold_at}) do
      {:ok, _item} ->
        candidates = Enum.reject(socket.assigns.candidates, &(&1.item.id == candidate.item.id))

        {:noreply,
         socket
         |> assign(:candidates, candidates)
         |> assign(:selected, nil)
         |> put_flash(:info, "Marked #{candidate.yaga_slug} as sold")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp fetch_detail(slug) do
    case StatusChecker.run(slug) do
      {:ok, data} -> data
      _ -> %{}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-7xl mx-auto p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">Warehouse Sales</h1>
          <.link navigate={~p"/payouts"} class="btn btn-ghost btn-sm">← Payouts</.link>
        </div>

        <p class="text-base-content/70 mb-4">
          Items that Yaga lists as sold but have no completed order — likely sold from the warehouse.
          Confirm price and date to mark each one sold.
        </p>

        <%= cond do %>
          <% @loading -> %>
            <div class="alert">
              <span class="loading loading-spinner"></span>
              <span>Fetching from Yaga…</span>
            </div>
          <% @error -> %>
            <div class="alert alert-error">
              <span>Error: {@error}</span>
            </div>
          <% @candidates == [] -> %>
            <div class="alert alert-success">
              <span>No warehouse sales pending review. 🎉</span>
            </div>
          <% true -> %>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <div class="overflow-x-auto">
                  <table class="table">
                    <thead>
                      <tr>
                        <th>Item</th>
                        <th>Yaga slug</th>
                        <th class="text-right">Listed price</th>
                        <th>Yaga updated</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for candidate <- @candidates do %>
                        <tr>
                          <td>
                            <.link
                              navigate={~p"/items/#{candidate.item.id}"}
                              class="link link-primary"
                            >
                              {String.slice(candidate.item.id, 0, 8)}
                            </.link>
                          </td>
                          <td>
                            <a
                              href={"https://www.yaga.ee/kirbs-ee/toode/#{candidate.yaga_slug}"}
                              target="_blank"
                              class="link"
                            >
                              {candidate.yaga_slug}
                            </a>
                          </td>
                          <td class="text-right">
                            {candidate.listed_price && Decimal.to_string(candidate.listed_price)}
                          </td>
                          <td>
                            {candidate.yaga_updated_at &&
                              Calendar.strftime(candidate.yaga_updated_at, "%Y-%m-%d")}
                          </td>
                          <td class="text-right">
                            <button
                              class="btn btn-primary btn-xs"
                              phx-click="open_modal"
                              phx-value-item-id={candidate.item.id}
                            >
                              Mark sold
                            </button>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
        <% end %>

        <%= if @selected do %>
          <div class="modal modal-open">
            <div class="modal-box">
              <h3 class="font-bold text-lg mb-4">Mark sold: {@selected.yaga_slug}</h3>

              <form phx-submit="confirm_sold" phx-change="form_changed">
                <div class="form-control mb-4">
                  <label class="label"><span class="label-text">Sold price (€)</span></label>
                  <input
                    type="number"
                    step="0.01"
                    class="input input-bordered w-full"
                    value={@form_price}
                    name="price"
                    required
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label"><span class="label-text">Sold on</span></label>
                  <input
                    type="date"
                    class="input input-bordered w-full"
                    value={@form_sold_at}
                    name="sold_at"
                    required
                  />
                </div>

                <div class="modal-action">
                  <button type="button" class="btn" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary">Confirm sold</button>
                </div>
              </form>
            </div>
            <div class="modal-backdrop" phx-click="close_modal"></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
