# Montonio integration

Payments (Stargate API) and shipping (Shipping v2 API). Wired into the shop; no
real call has ever been made. Everything below was written from
docs.montonio.com (Stargate "orders" guide, Shipping v2 guides for shipments,
labels, webhooks, shipping-methods, sandbox).

## Credentials

1. Create a Montonio partner account at https://partner.montonio.com and a store.
2. Partner system > Stores > your store > API keys: copy the **Access key** and **Secret key**.
   The same pair signs payment orders and shipping calls.
3. Enable bank payments (payment initiation) for the store and, for shipping,
   enable the carriers (Omniva, Smartpost/Itella, DPD...). For testing turn on
   test mode and activate carriers with dummy credentials.
4. Sandbox keys come from the sandbox partner system (https://sandbox-partner.montonio.com).
   Payments sandbox and shipping sandbox use separate hosts; keys are separate from production.

## Env vars (read in `config/runtime.exs`)

| var | meaning |
| --- | --- |
| `MONTONIO_ACCESS_KEY` | access key |
| `MONTONIO_SECRET_KEY` | secret key (HS256 signing key) |
| `MONTONIO_ENV` | `sandbox` (default) or `production` |

Not required at boot. Without keys every service returns
`{:error, :montonio_not_configured}` and the daily job is a no-op.
Other keys of `config :kirbs, :montonio` (all optional): `payment_handler`,
`shipment_handler`, `carriers` (default `["omniva","smartpost","dpd"]`),
`return_redirect` (optional override; default resolves `/order/:token`),
`stargate_base_url`, `shipping_base_url`.

Hosts: Stargate `https://sandbox-stargate.montonio.com/api` / `https://stargate.montonio.com/api`;
Shipping `https://sandbox-shipping.montonio.com/api/v2` / `https://shipping.montonio.com/api/v2`.

## What is implemented

- `Kirbs.Montonio.Config`, `.Jwt` (JOSE, HS256, verify rejects bad signature, `alg: none`, expiry beyond 5 min leeway), `.Client` (Req; tests use `Req.Test` stub `Kirbs.Montonio`).
- `Kirbs.Montonio.Payments.CreateOrder.run(params)` -> `{:ok, %{payment_url, montonio_order_uuid}}`. Params are plain maps with integer cents (see moduledoc). Method `paymentInitiation`, country EE, locale `et`, currency EUR. Line items must sum to `total_cents` (add shipping as a line item).
- `Kirbs.Montonio.Payments.VerifyOrderToken.run(token)` -> `{:ok, %{merchant_reference, payment_status (:paid|:pending|:failed|:cancelled|:unknown), montonio_order_uuid, ...}}`. Also checks `accessKey`.
- `Kirbs.Montonio.Payments.ApplyPaymentUpdate.run(token)`: verify + de-dupe + call handler.
- Endpoints (no session/CSRF; auth is the signed JWT):
  - `POST /webhooks/montonio` body `{"orderToken": jwt}`; 200 ok/duplicate, 401 bad token, 500 handler error (Montonio retries 13x/48h).
  - `POST /webhooks/montonio/shipping` body `{"payload": jwt}`.
  - `GET /checkout/montonio/return?order-token=jwt`: verifies, notifies handler, redirects to `return_redirect`.
- Behaviours `Kirbs.Montonio.PaymentHandler` (`handle_payment_update(merchant_reference, status)`) and `Kirbs.Montonio.ShipmentHandler` (`handle_shipment_update(event)`), default `...Logging` implementations.
- `Kirbs.Shipping.MontonioPickupPoints` (`list(carrier:, country: "EE", search:, type:)`, `get(id)`, `refresh/1`), ETS cache in `Kirbs.Montonio.Store`, lazily filled, refreshed by `Kirbs.Jobs.RefreshMontonioPickupPointsJob` (cron `0 5 * * *`). Points: `%{id, name, type, street_address, locality, postal_code, carrier}`.
- `Kirbs.Montonio.Shipping.CreateShipment.run(params)` -> `{:ok, %{shipment_id, status, carrier_code, tracking_numbers, tracking_links}}`; `FetchLabel.run(%{shipment_ids: [...]})` -> `{:ok, pdf_url}`.

## Final flow (wired into the shop)

Everything below is implemented and covered by Req.Test stubs (no real call has been made yet).

1. **Checkout** (`ShopLive.Checkout`): the "Pangalink / pangamakse (Montonio)" option is only shown when
   `Kirbs.Montonio.Config.configured?/0`; otherwise the shop is bank-transfer only (a forged `montonio`
   value is coerced to manual). Submit calls `Order.submit(payment_method: :montonio)` (30 min hold),
   then `Services.Orders.StartMontonioPayment.run/1`: `Payments.CreateOrder` with
   `merchant_reference = order.reference` (unique, "K1234567"), items + shipping as line items,
   `Order.set_montonio_ref`, redirect (external) to `payment_url`. If Montonio is unreachable the order
   is cancelled (item released) and the buyer sees `#checkout-payment-failed` with a retry link.
2. **Payment result**: `Kirbs.Montonio.OrderPaymentHandler` (default `payment_handler`), fed by the
   webhook and the browser return. `PAID` -> `Order.mark_paid` (no-op when already paid; accepts a late
   payment of a cancelled/expired order if the item is still free; if the item was sold meanwhile the
   order gets `cancel_reason` "PAID IN MONTONIO BUT NOT FULFILLABLE - refund manually ..." and the update
   is acknowledged). `FAILED`/`CANCELLED` -> `Order.cancel` while unpaid. `PENDING`/unknown -> no-op.
3. **Return page**: `/checkout/montonio/return` resolves the order by reference and redirects to
   `/order/:token`, which polls every 3 s while a Montonio order is still `reserved` (webhook may lag).
4. **Pickup points**: `config :kirbs, :pickup_points_provider` wins if set; otherwise
   `PickupPoints.Montonio` (cached Montonio data) when configured, else `PickupPoints.Static`.
   Checkout has a search box (name/address substring, max 50 shown); `Order.submit` validates the id
   with `provider.get/2`.
5. **Shipping price**: `Kirbs.Shipping.Rates` by carrier and `Item.parcel_size` (order = largest item,
   default `m`). All prices and default parcel weights are PLACEHOLDERS (see moduledoc).
6. **Shipment**: `Order.mark_paid` enqueues `Kirbs.Jobs.CreateMontonioShipmentJob` for Montonio-paid
   parcel-machine orders. `Services.Orders.CreateMontonioShipment` is idempotent (skips if
   `montonio_shipment_id` is set), stores shipment id/status/tracking, or stores `shipment_error` and lets
   Oban retry (5 attempts). Own pickup / manual payment orders get no job.
7. **Admin** `/orders/shipping`: per Montonio order shows shipment status, tracking and error, with
   "Create/Retry shipment", "Prepare label" (FetchLabel) and "Download label" (PDF link).
   `/orders`: "Cancel / refund" for paid orders only records `payment_status: :refunded` + `cancelled`;
   **the refund itself is done manually in the Montonio partner system** (refund API not built; items stay
   sold, relist by hand).
8. **Shipping webhook**: `Kirbs.Montonio.OrderShipmentHandler` finds the order by shipment id, falling
   back to `merchant_reference`; stores status/tracking/label url/errors; `inTransit`,
   `awaitingCollection` or `delivered` -> `Order.mark_shipped` (sends the shipped email); `delivered` ->
   `Order.mark_delivered`. The status names are assumptions, verify in sandbox.

New Order columns: `montonio_shipment_id` (unique), `shipment_status`, `shipment_label_url`,
`shipment_error` (tracking uses the existing `tracking_number`/`tracking_url`).

## Owner checklist

Partner system (https://partner.montonio.com, sandbox: https://sandbox-partner.montonio.com):
- [ ] Create the store, copy Access key + Secret key (separate sandbox and production keys).
- [ ] Enable bank payments (payment initiation) for the store.
- [ ] Shipping: enable carriers Omniva, SmartPosti (Montonio code `smartpost`), DPD; fill in sender
      details; in sandbox use test mode with dummy carrier credentials.
- [ ] Register the shipping webhook: URL `https://<host>/webhooks/montonio/shipping`, events
      `shipment.registered`, `shipment.registrationFailed`, `shipment.statusUpdated`,
      `shipment.labelsCreated`, `labelFile.ready`, `labelFile.creationFailed` (partner system, or
      `POST {shipping_base}/webhooks`).
- [ ] Payment webhook needs no registration (`https://<host>/webhooks/montonio` is sent per order);
      the return URL is `https://<host>/checkout/montonio/return`.
- [ ] Refunds: do them in the partner system, then press "Cancel / refund" in `/orders` to keep our records.

App / env (fly secrets): `MONTONIO_ACCESS_KEY`, `MONTONIO_SECRET_KEY`, `MONTONIO_ENV` (`sandbox` or
`production`). Without them the shop silently stays manual-only. Also replace the placeholder prices in
`Kirbs.Shipping.Rates` and set `PHX_HOST`/endpoint url correctly (return and webhook URLs are built from it).

End-to-end in sandbox:
1. Set sandbox env vars, deploy publicly (fly, or ngrok with `PHX_HOST` set).
2. `Kirbs.Shipping.MontonioPickupPoints.refresh()`; check the checkout picker lists points and searching works.
3. Buy an item choosing Montonio + Omniva machine; pay with the sandbox bank; expect redirect to
   `/order/:token` showing "paid" within seconds (webhook) and a `shipped`-less paid order.
4. Check `/orders/shipping`: shipment created (or error + retry), "Prepare label" then "Download label".
5. Wait for / trigger sandbox status events; order moves to shipped (email) and delivered.
6. Repeat and cancel at the bank: order becomes cancelled, item available again.
7. Tamper a webhook token with curl: expect 401. Only then switch to production keys.

## Assumptions / unverified

- Shipping base URL: overview says `api.shipping.montonio.com`, guides say `shipping.montonio.com/api/v2`. We use the guides.
- Carrier codes `omniva`, `smartpost`, `dpd` (docs only show `smartpost`, `venipak`; Omniva appears in a response sample).
- Pickup point endpoint takes lowercase `carrierCode`/`countryCode`; we send lowercase.
- Pickup point response shape taken from the guide; pagination not mentioned, so none handled.
- Webhook payment status values beyond PAID/PENDING/FAILED/CANCELLED map to `:unknown`.
- `labelFile.*` webhooks: we assume `data.labelFileUrl`.
- Shipping webhook dedupe key is `eventId`; payment key is (reference, status).
- Shipment statuses `inTransit`, `awaitingCollection`, `delivered` and the `receiver` phone split (`+372` default) are guesses.
- Payment webhook IP allowlist (35.156.245.42, 35.156.159.169) is not enforced; JWT verification is the guard.
- Phone numbers: Montonio wants `phoneCountryCode` like `+372` for shipments; Stargate `phoneCountry` style is unspecified (pass what the docs example shows, e.g. `EE`/`372` to be checked in sandbox).
- Shipment product `currency` is hard-coded EUR.

## Sandbox test checklist (owner)

1. Set sandbox keys in env, `MONTONIO_ENV=sandbox`, expose the app publicly (ngrok/fly) so webhooks arrive.
2. `Kirbs.Montonio.Payments.CreateOrder.run/1` from a console with a 1 EUR order; open `payment_url`, pay with the sandbox bank, confirm redirect to `/checkout/montonio/return` and the webhook log line "Montonio payment update ... paid".
3. Repeat and cancel; expect `:cancelled`/`:failed`.
4. Replay the webhook with curl using a tampered token; expect 401.
5. `Kirbs.Shipping.MontonioPickupPoints.refresh()`; check counts per carrier, try `list(carrier: "omniva", search: "tallinn")`.
6. `CreateShipment.run/1` with a returned pickup point id; confirm `shipment.registered` webhook, then `FetchLabel.run/1` returns a PDF url.
7. Register the shipping webhook and confirm `shipment.statusUpdated` yields tracking numbers.
8. Switch to production keys only after all of the above.
