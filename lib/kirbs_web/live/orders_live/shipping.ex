defmodule KirbsWeb.OrdersLive.Shipping do
  @moduledoc """
  Admin manual postage view: paid orders that still have to leave the house. Shows where to
  send them (parcel machine or own pickup), and records "shipped" with an optional tracking
  number (which triggers the shipped email) or "handed over" for own pickup.
  """
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Order
  alias Kirbs.Services.Orders.{CreateMontonioShipment, FetchMontonioLabel}
  alias Kirbs.Shipping.Rates

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Manual postage")
     |> stream(:orders, Order.list_to_ship!())}
  end

  def handle_event("ship", %{"id" => id, "ship" => params}, socket) do
    tracking = params |> Map.get("tracking_number", "") |> String.trim()
    attrs = %{tracking_number: blank_to_nil(tracking)}

    {:noreply,
     act(socket, id, "Marked shipped", fn order -> Order.mark_shipped(order, attrs) end)}
  end

  def handle_event("deliver", %{"id" => id}, socket) do
    {:noreply, act(socket, id, "Marked handed over", &Order.mark_delivered/1)}
  end

  def handle_event("create_shipment", %{"id" => id}, socket) do
    {:noreply, reload(socket, id, "Shipment created", &CreateMontonioShipment.run/1)}
  end

  def handle_event("fetch_label", %{"id" => id}, socket) do
    {:noreply, reload(socket, id, "Label ready", &FetchMontonioLabel.run/1)}
  end

  # Runs a Montonio service and re-renders the card with the stored result or error.
  defp reload(socket, id, success, service) do
    result = service.(id)
    order = Ash.get!(Order, id, load: [:order_items])
    socket = stream_insert(socket, :orders, order)

    case result do
      {:ok, _} -> put_flash(socket, :info, "#{order.reference}: #{success}")
      {:error, error} -> put_flash(socket, :error, "#{order.reference}: " <> error_text(error))
    end
  end

  defp error_text(%{__exception__: true} = error), do: Exception.message(error)
  defp error_text(:no_shipment), do: "no Montonio shipment yet"
  defp error_text(error), do: inspect(error)

  defp act(socket, id, success, fun) do
    with {:ok, order} <- Ash.get(Order, id),
         {:ok, order} <- fun.(order) do
      socket
      |> put_flash(:info, "#{order.reference}: #{success}")
      |> stream_delete(:orders, order)
    else
      {:error, error} -> put_flash(socket, :error, "Failed: " <> Exception.message(error))
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Europe/Tallinn") |> Calendar.strftime("%d.%m %H:%M")
  end

  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-4xl mx-auto p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">Manual postage</h1>
          <.link navigate={~p"/orders"} id="to-orders" class="btn btn-outline btn-sm">
            All orders
          </.link>
        </div>

        <div id="to-ship" phx-update="stream" class="space-y-4">
          <div id="to-ship-empty" class="hidden only:block card bg-base-100 shadow">
            <div class="card-body text-center text-base-content/60">Nothing to ship right now.</div>
          </div>

          <div
            :for={{dom_id, order} <- @streams.orders}
            id={dom_id}
            class="card bg-base-100 shadow-xl"
          >
            <div class="card-body">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 class="card-title font-mono">{order.reference}</h2>
                  <p class="text-xs text-base-content/60">paid {format_time(order.paid_at)}</p>
                </div>
                <span class="badge badge-lg">{Rates.label(order.delivery_method)}</span>
              </div>

              <div class="grid gap-4 sm:grid-cols-2 mt-2">
                <div>
                  <p class="text-xs uppercase text-base-content/60">Send to</p>
                  <p class="font-bold">{order.buyer_name}</p>
                  <p class="text-sm">{order.buyer_phone}</p>
                  <p class="text-sm">{order.buyer_email}</p>
                </div>
                <div>
                  <p class="text-xs uppercase text-base-content/60">Destination</p>
                  <%= if order.delivery_method == :pickup do %>
                    <p class="font-bold">Own pickup</p>
                    <p class="text-sm">{Rates.pickup_address()}</p>
                  <% else %>
                    <p class="font-bold">{order.pickup_point_name}</p>
                    <p class="text-sm text-base-content/70">
                      {order.pickup_point_carrier} · {order.pickup_point_id}
                    </p>
                  <% end %>
                </div>
              </div>

              <div
                :if={order.payment_method == :montonio and order.delivery_method != :pickup}
                id={"shipment-#{order.id}"}
                class="mt-3 rounded-lg bg-base-200 p-3 text-sm"
              >
                <p class="text-xs uppercase text-base-content/60">Montonio shipment</p>
                <p :if={order.montonio_shipment_id}>
                  Status:
                  <span id={"shipment-status-#{order.id}"} class="font-bold">
                    {order.shipment_status || "-"}
                  </span>
                  <span :if={order.tracking_number}>
                    · tracking {order.tracking_number}
                  </span>
                </p>
                <p :if={is_nil(order.montonio_shipment_id)} class="text-base-content/70">
                  Not created yet.
                </p>
                <p :if={order.shipment_error} id={"shipment-error-#{order.id}"} class="text-error">
                  {order.shipment_error}
                </p>
                <div class="mt-2 flex flex-wrap gap-2">
                  <button
                    :if={is_nil(order.montonio_shipment_id)}
                    id={"create-shipment-#{order.id}"}
                    phx-click="create_shipment"
                    phx-value-id={order.id}
                    class="btn btn-warning btn-sm"
                  >
                    {if order.shipment_error, do: "Retry shipment", else: "Create shipment"}
                  </button>
                  <button
                    :if={order.montonio_shipment_id}
                    id={"fetch-label-#{order.id}"}
                    phx-click="fetch_label"
                    phx-value-id={order.id}
                    class="btn btn-outline btn-sm"
                  >
                    Prepare label
                  </button>
                  <a
                    :if={order.shipment_label_url}
                    id={"download-label-#{order.id}"}
                    href={order.shipment_label_url}
                    target="_blank"
                    rel="noopener"
                    class="btn btn-primary btn-sm"
                  >
                    Download label
                  </a>
                </div>
              </div>

              <ul class="mt-2 text-sm list-disc pl-5">
                <li :for={oi <- order.order_items}>{oi.title}</li>
              </ul>

              <div class="card-actions mt-4">
                <%= if order.delivery_method == :pickup do %>
                  <button
                    id={"deliver-#{order.id}"}
                    phx-click="deliver"
                    phx-value-id={order.id}
                    class="btn btn-primary btn-sm"
                  >
                    Mark handed over
                  </button>
                <% else %>
                  <form
                    id={"ship-form-#{order.id}"}
                    phx-submit="ship"
                    class="flex flex-wrap items-center gap-2"
                  >
                    <input type="hidden" name="id" value={order.id} />
                    <input
                      type="text"
                      name="ship[tracking_number]"
                      placeholder="Tracking number (optional)"
                      class="input input-bordered input-sm w-64"
                    />
                    <button type="submit" class="btn btn-primary btn-sm">Mark shipped</button>
                  </form>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
