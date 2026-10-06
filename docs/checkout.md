# Checkout, orders and manual payment (Phase 4)

Flow: item page `Broneeri` -> `/checkout/:slug` (connected mount reserves the item for 10 minutes
via `Order.start`, patches to `?order=TOKEN` so reloads resume) -> submit (`Order.submit`, hold
extended to 72h for bank transfer) -> `/order/:token` (bank instructions) -> admin `/orders`
"Mark paid" -> `/orders/shipping` "Mark shipped" (+ tracking number). Emails (received / paid /
shipped) are Oban jobs (`Kirbs.Jobs.SendOrderEmailJob`) enqueued inside the Order actions.

## Order lifecycle

`pending` (items reserved, no contact yet) -> `reserved` (submitted, awaiting payment) -> `paid`
-> `shipped` -> `delivered`; `cancelled` from pending/reserved (expiry or admin). Own pickup goes
`paid` -> `delivered` (`mark_delivered`).

Item side: `Item.kirbs_status` `:available -> :reserved (reserved_until) -> :sold`.
`Item.reserve` is a single atomic UPDATE guarded by `Reservable` (available, or reservation already
expired), so two buyers can never both reserve a qty-1 item. `Item.release_reservation(item, held_until)`
only frees an item still held with that exact deadline (never a newer buyer's hold, never a sold item).
`Kirbs.Jobs.ExpireReservationsJob` (cron, every minute) cancels expired orders and sweeps orphaned
item reservations.

## Order API for payment integrations (Montonio)

All in `Kirbs.Resources.Order` (code_interface):

| Call | Use |
|------|-----|
| `Order.start(item_ids, %{ab_visitor_id:, ab_assignments:})` | reserve + open pending order (checkout does this) |
| `Order.submit(order, %{buyer_name:, buyer_email:, buyer_phone:, delivery_method:, pickup_point_id:, payment_method: :montonio})` | contact + delivery; status -> `:reserved`; hold = `Orders.Config.hold_deadline(:montonio)` (30 min). Computes `shipping_cents`, `total_cents` (`order.total_cents` is what to charge, EUR cents) |
| `Order.set_montonio_ref(order, %{montonio_order_ref:, montonio_payment_url:})` | store Montonio's order uuid / paymentUrl (unique) |
| `Order.get_by_token(token)` / `Order.get(id)` | load (with `order_items: [item: :images]`) |
| `Order.mark_paid(order)` | webhook on `paymentStatus == PAID`: sells items, sends paid email, fires funnel `paid`. Errors if already paid or an item was sold elsewhere (check `order.payment_status == :paid` first for idempotency). Allowed from `:reserved` and `:cancelled` (late payment) |
| `Order.cancel(order, %{cancel_reason: "..."})` | unpaid failure/abandon; releases the items |

`order.payment_method` is `:manual | :montonio`; the `:received` email (bank instructions) is only
sent for `:manual`. For a Montonio return LiveView that lands the buyer back in the app, fire the
pixel with `KirbsWeb.Track.event(socket, :paid, %{order_id:, value:, currency: "EUR"})`; the
server-side ab_funnel `paid` event is already fired by `mark_paid` from the visitor stored on the order.
The mailer adapter in production is not configured yet (see `config/runtime.exs`).

## Montonio payment path

Checkout offers "Pangalink (Montonio)" when Montonio keys exist, else bank transfer only. Montonio
submit -> `Services.Orders.StartMontonioPayment` -> external redirect; the webhook/return feed
`Kirbs.Montonio.OrderPaymentHandler` (`mark_paid` / `cancel`), the buyer lands on `/order/:token`
(polls while `reserved`). After `mark_paid`, parcel orders get a Montonio shipment via an Oban job; see
docs/montonio.md for the full flow, owner checklist and sandbox test plan. Admin `/orders` has
"Cancel / refund" for paid orders (bookkeeping only; refund money in Montonio partner system).

## Pickup points / shipping

`Kirbs.Shipping.PickupPoints.list(carrier)` and `.get(carrier, id)` (carrier `:omniva | :dpd |
:smartposti`, point = `%{id, name, carrier, address}`) delegate to the module in
`config :kirbs, :pickup_points_provider` (a `Kirbs.Shipping.PickupPoints.Provider`). Default:
`PickupPoints.Montonio` when Montonio is configured, else `PickupPoints.Static`. The checkout picker is
searchable (`PickupPoints.list(carrier, search, limit)`). Prices: `Kirbs.Shipping.Rates` per carrier and
`Item.parcel_size` (placeholders).
`Order.submit` validates `pickup_point_id` through `PickupPoints.get/2` and snapshots the name.

## TODO(owner)

- Real IBAN and account holder on `/settings` ("Shop bank transfer details"); the placeholder
  `EE00 ...` is shown until then (`Kirbs.Orders.BankDetails`).
- Real sender address: `config :kirbs, :shop_mail, from: {"Kirbs", "pood@kirbs.ee"}`, and a
  production Swoosh adapter in `config/runtime.exs`.
- Real shipping prices and own-pickup address in `Kirbs.Shipping.Rates`.
