defmodule KirbsWeb.OrdersLive.Index do
  @moduledoc "Admin: all shop orders, newest first, with manual \"mark paid\" and cancel."
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Order
  alias Kirbs.Shipping.Rates
  alias KirbsWeb.Shop.Labels

  @filters ~w(all awaiting_payment paid shipped cancelled)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Orders")
     |> assign(:filter, "all")
     |> stream(:orders, [])}
  end

  def handle_params(params, _uri, socket) do
    filter = if params["filter"] in @filters, do: params["filter"], else: "all"
    orders = Order.list_recent!() |> Enum.filter(&matches?(&1, filter))

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:orders, orders, reset: true)}
  end

  def handle_event("mark_paid", %{"id" => id}, socket) do
    {:noreply,
     act(
       socket,
       id,
       fn order -> Order.mark_paid(order, %{}, context: %{event_source: :admin}) end,
       "Marked as paid"
     )}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    {:noreply,
     act(
       socket,
       id,
       fn order ->
         Order.cancel(order, %{cancel_reason: "admin"}, context: %{event_source: :admin})
       end,
       "Cancelled"
     )}
  end

  def handle_event("refund", %{"id" => id}, socket) do
    {:noreply,
     act(
       socket,
       id,
       fn order ->
         Order.refund(order, %{cancel_reason: "refunded by admin"},
           context: %{event_source: :admin}
         )
       end,
       "Marked refunded. Now refund the payment in the Montonio partner system"
     )}
  end

  defp act(socket, id, fun, success) do
    with {:ok, order} <- Ash.get(Order, id),
         {:ok, _} <- fun.(order) do
      order = Ash.get!(Order, id, load: [:order_items])

      socket
      |> put_flash(:info, "#{order.reference}: #{success}")
      |> stream_insert(:orders, order)
    else
      {:error, error} ->
        put_flash(socket, :error, "Failed: " <> Exception.message(error))
    end
  end

  defp matches?(_order, "all"), do: true
  defp matches?(order, "awaiting_payment"), do: order.status in [:pending, :reserved]
  defp matches?(order, "paid"), do: order.status in [:paid, :delivered]
  defp matches?(order, "shipped"), do: order.status == :shipped
  defp matches?(order, "cancelled"), do: order.status == :cancelled

  defp badge_class(:pending), do: "badge-ghost"
  defp badge_class(:reserved), do: "badge-warning"
  defp badge_class(:paid), do: "badge-success"
  defp badge_class(:shipped), do: "badge-info"
  defp badge_class(:delivered), do: "badge-success badge-outline"
  defp badge_class(:cancelled), do: "badge-error badge-outline"

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Europe/Tallinn") |> Calendar.strftime("%d.%m %H:%M")
  end

  defp filter_label("all"), do: "All"
  defp filter_label("awaiting_payment"), do: "Awaiting payment"
  defp filter_label("paid"), do: "Paid"
  defp filter_label("shipped"), do: "Shipped"
  defp filter_label("cancelled"), do: "Cancelled"

  def render(assigns) do
    assigns = assign(assigns, :filters, @filters)

    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-6xl mx-auto p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">Orders</h1>
          <.link navigate={~p"/orders/shipping"} id="to-shipping" class="btn btn-outline btn-sm">
            Manual postage
          </.link>
        </div>

        <div role="tablist" id="order-filters" class="tabs tabs-boxed mb-4 w-fit">
          <.link
            :for={filter <- @filters}
            id={"filter-#{filter}"}
            role="tab"
            patch={~p"/orders?#{[filter: filter]}"}
            class={["tab", @filter == filter && "tab-active"]}
          >
            {filter_label(filter)}
          </.link>
        </div>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body overflow-x-auto p-0">
            <table class="table">
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Buyer</th>
                  <th>Items</th>
                  <th>Delivery</th>
                  <th class="text-right">Total</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody id="orders" phx-update="stream">
                <tr id="orders-empty" class="hidden only:table-row">
                  <td colspan="7" class="text-center text-base-content/60 py-8">No orders</td>
                </tr>
                <tr :for={{dom_id, order} <- @streams.orders} id={dom_id}>
                  <td>
                    <.link
                      navigate={~p"/orders/#{order.id}"}
                      id={"order-link-#{order.id}"}
                      class="font-mono font-bold link link-hover"
                    >
                      {order.reference}
                    </.link>
                    <div class="text-xs text-base-content/60">{format_time(order.created_at)}</div>
                  </td>
                  <td>
                    <div>{order.buyer_name || "-"}</div>
                    <div class="text-xs text-base-content/60">{order.buyer_email}</div>
                  </td>
                  <td class="max-w-56 text-sm">
                    <div :for={oi <- order.order_items}>{oi.title}</div>
                  </td>
                  <td class="text-sm">
                    <%= if order.delivery_method do %>
                      {Rates.label(order.delivery_method)}
                      <div class="text-xs text-base-content/60">{order.pickup_point_name}</div>
                    <% else %>
                      -
                    <% end %>
                  </td>
                  <td class="text-right font-bold">{Labels.cents(order.total_cents)}</td>
                  <td>
                    <span class={["badge", badge_class(order.status)]}>{order.status}</span>
                    <div
                      :if={order.status in [:pending, :reserved]}
                      class="text-xs text-base-content/60 mt-1"
                    >
                      until {format_time(order.reserved_until)}
                    </div>
                  </td>
                  <td class="whitespace-nowrap text-right">
                    <button
                      :if={order.status in [:reserved, :cancelled]}
                      id={"mark-paid-#{order.id}"}
                      phx-click="mark_paid"
                      phx-value-id={order.id}
                      data-confirm={"Mark #{order.reference} as paid? The items will be marked sold."}
                      class="btn btn-success btn-sm"
                    >
                      Mark paid
                    </button>
                    <button
                      :if={order.status == :paid}
                      id={"refund-#{order.id}"}
                      phx-click="refund"
                      phx-value-id={order.id}
                      data-confirm={"Cancel #{order.reference}? Refund the money manually in the Montonio partner system (or by bank transfer); the items stay sold."}
                      class="btn btn-ghost btn-sm"
                    >
                      Cancel / refund
                    </button>
                    <button
                      :if={order.status in [:pending, :reserved]}
                      id={"cancel-#{order.id}"}
                      phx-click="cancel"
                      phx-value-id={order.id}
                      data-confirm={"Cancel #{order.reference} and release the items?"}
                      class="btn btn-ghost btn-sm"
                    >
                      Cancel
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
