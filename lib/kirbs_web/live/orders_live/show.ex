defmodule KirbsWeb.OrdersLive.Show do
  @moduledoc "Admin: one order with buyer, delivery, payment and shipment facts and its OrderEvent timeline."
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Order, OrderEvent}
  alias Kirbs.Shipping.Rates
  alias KirbsWeb.Shop.Labels

  def mount(%{"id" => id}, _session, socket) do
    case Order.get(id, not_found_error?: false) do
      {:ok, %Order{} = order} ->
        {:ok,
         socket
         |> assign(:page_title, "Order #{order.reference}")
         |> assign(:order, order)
         |> assign(:note_form, note_form())
         |> assign_events()}

      _ ->
        {:ok, socket |> put_flash(:error, "Order not found") |> push_navigate(to: ~p"/orders")}
    end
  end

  def handle_event("add_note", %{"note" => %{"summary" => summary}}, socket) do
    summary = String.trim(summary)

    if summary == "" do
      {:noreply, socket}
    else
      case OrderEvent.add_note(%{order_id: socket.assigns.order.id, summary: summary}) do
        {:ok, _event} ->
          {:noreply, socket |> assign(:note_form, note_form()) |> assign_events()}

        {:error, error} ->
          {:noreply, put_flash(socket, :error, "Failed: " <> Exception.message(error))}
      end
    end
  end

  defp note_form, do: to_form(%{"summary" => ""}, as: :note)

  defp assign_events(socket) do
    assign(socket, :events, OrderEvent.list_for_order!(socket.assigns.order.id))
  end

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Europe/Tallinn") |> Calendar.strftime("%d.%m.%Y %H:%M:%S")
  end

  defp money(nil, _currency), do: "-"
  defp money(cents, "EUR"), do: Labels.cents(cents)
  defp money(cents, currency), do: "#{Labels.cents(cents)} #{currency}"

  defp fact(assigns) do
    ~H"""
    <div class="flex justify-between gap-4 py-1 text-sm border-b border-base-200 last:border-0">
      <dt class="text-base-content/60">{@label}</dt>
      <dd class="font-medium text-right break-all">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-5xl mx-auto p-6 space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-3xl font-bold">
            Order <span class="font-mono" id="order-reference">{@order.reference}</span>
            <span id="order-status" class="badge badge-lg ml-2">{@order.status}</span>
          </h1>
          <.link navigate={~p"/orders"} id="back-to-orders" class="btn btn-outline btn-sm">
            All orders
          </.link>
        </div>

        <div class="grid gap-6 md:grid-cols-2">
          <div id="order-buyer" class="card bg-base-100 shadow-xl">
            <dl class="card-body">
              <h2 class="card-title">Buyer</h2>
              <.fact label="Name">{@order.buyer_name || "-"}</.fact>
              <.fact label="Email">{@order.buyer_email || "-"}</.fact>
              <.fact label="Phone">{@order.buyer_phone || "-"}</.fact>
              <.fact label="Created">{format_time(@order.created_at)}</.fact>
              <div :for={oi <- @order.order_items} class="text-sm pt-2">
                {oi.title} <span class="float-right">{Labels.cents(oi.price_cents)}</span>
              </div>
            </dl>
          </div>

          <div id="order-delivery" class="card bg-base-100 shadow-xl">
            <dl class="card-body">
              <h2 class="card-title">Delivery</h2>
              <.fact label="Method">
                {if @order.delivery_method, do: Rates.label(@order.delivery_method), else: "-"}
              </.fact>
              <.fact label="Pickup point">{@order.pickup_point_name || "-"}</.fact>
              <.fact label="Pickup point id">{@order.pickup_point_id || "-"}</.fact>
              <.fact label="Items">{money(@order.items_total_cents, @order.currency)}</.fact>
              <.fact label="Shipping">{money(@order.shipping_cents, @order.currency)}</.fact>
              <.fact label="Total">{money(@order.total_cents, @order.currency)}</.fact>
            </dl>
          </div>

          <div id="order-payment" class="card bg-base-100 shadow-xl">
            <dl class="card-body">
              <h2 class="card-title">Payment</h2>
              <.fact label="Method">{@order.payment_method}</.fact>
              <.fact label="Status">{@order.payment_status}</.fact>
              <.fact label="Montonio order uuid">{@order.montonio_order_uuid || "-"}</.fact>
              <.fact label="Montonio order ref">{@order.montonio_order_ref || "-"}</.fact>
              <.fact label="Montonio payment method">
                {@order.montonio_payment_method || "-"}
              </.fact>
              <.fact label="Last Montonio status">{@order.last_montonio_status || "-"}</.fact>
              <.fact label="Paid at">{format_time(@order.paid_at)}</.fact>
              <.fact label="Amount paid">{money(@order.amount_paid_cents, @order.currency)}</.fact>
              <.fact label="Refunded">{money(@order.refunded_cents, @order.currency)}</.fact>
              <.fact label="Refunded at">{format_time(@order.refunded_at)}</.fact>
              <.fact label="Failure reason">{@order.payment_failure_reason || "-"}</.fact>
              <.fact label="Cancel reason">{@order.cancel_reason || "-"}</.fact>
            </dl>
          </div>

          <div id="order-shipment" class="card bg-base-100 shadow-xl">
            <dl class="card-body">
              <h2 class="card-title">Shipment</h2>
              <.fact label="Shipment id">{@order.montonio_shipment_id || "-"}</.fact>
              <.fact label="Status">{@order.shipment_status || "-"}</.fact>
              <.fact label="Tracking">{@order.tracking_number || "-"}</.fact>
              <.fact label="Label">
                <a :if={@order.shipment_label_url} href={@order.shipment_label_url} class="link">
                  PDF
                </a>
                <span :if={!@order.shipment_label_url}>-</span>
              </.fact>
              <.fact label="Error">{@order.shipment_error || "-"}</.fact>
              <.fact label="Shipped at">{format_time(@order.shipped_at)}</.fact>
              <.fact label="Delivered at">{format_time(@order.delivered_at)}</.fact>
            </dl>
          </div>
        </div>

        <div id="order-timeline" class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Timeline</h2>
            <ol class="space-y-3">
              <li :if={@events == []} id="timeline-empty" class="text-base-content/60">
                No events yet
              </li>
              <li
                :for={event <- @events}
                id={"event-#{event.id}"}
                data-kind={event.kind}
                class="border-l-4 border-base-300 pl-3"
              >
                <div class="text-xs text-base-content/60">
                  {format_time(event.occurred_at)}
                  <span class="badge badge-sm badge-ghost ml-1">{event.kind}</span>
                  <span class="badge badge-sm badge-outline">{event.source}</span>
                </div>
                <div class="text-sm">{event.summary}</div>
                <details :if={map_size(event.payload) > 0} class="text-xs">
                  <summary class="cursor-pointer text-base-content/60">payload</summary>
                  <pre class="overflow-x-auto bg-base-200 p-2 rounded">{Jason.encode!(event.payload, pretty: true)}</pre>
                </details>
              </li>
            </ol>

            <.form for={@note_form} id="note-form" phx-submit="add_note" class="flex gap-2 mt-4">
              <div class="grow">
                <.input field={@note_form[:summary]} type="text" placeholder="Add a note" />
              </div>
              <button id="add-note" type="submit" class="btn btn-primary">Add note</button>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
