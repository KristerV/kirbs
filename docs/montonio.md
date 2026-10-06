# Montonio integration

Payments (Stargate API) and shipping (Shipping v2 API). Code only so far; no
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
`return_redirect` (default `"/orders/:merchant_reference"`),
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

### Swapping in for `Kirbs.Shipping.PickupPoints`

The other agent's stub defines the interface; make its implementation delegate
`list/1` (and `get/1,2`) to `Kirbs.Shipping.MontonioPickupPoints`, same options
(`carrier:`, `country:`, `search:`). Both return `{:ok, [point]}`.

## Hooks the Order flow must call

1. Checkout submit: `Payments.CreateOrder.run(%{merchant_reference: order.number, total_cents:, line_items:, return_url: url(~p"/checkout/montonio/return"), notification_url: url(~p"/webhooks/montonio"), billing:, shipping:})`; store `montonio_order_uuid`; redirect customer to `payment_url`.
2. Configure `payment_handler: MyOrderPaymentHandler` implementing `handle_payment_update/2` (mark paid on `:paid`, cancel/free reservation on `:failed|:cancelled`). Must be idempotent. De-dupe is in-memory only (lost on deploy).
3. Create the page behind `return_redirect` (default `/orders/:merchant_reference`) or change the config.
4. After payment: `Shipping.CreateShipment.run(...)` with the pickup point id from `MontonioPickupPoints` (pass `montonio_order_uuid` and `merchant_reference`), store `shipment_id`.
5. Configure `shipment_handler` to store tracking numbers (event has `tracking_numbers`, `tracking_links`, `status`, `merchant_reference`, `event_type`).
6. Admin "print label": `Shipping.FetchLabel.run(%{shipment_ids: [id]})`.
7. One-time per environment: register the shipping webhook (not automated yet):
   `POST {shipping_base}/webhooks` with url `https://<host>/webhooks/montonio/shipping` and events `shipment.registered`, `shipment.registrationFailed`, `shipment.statusUpdated`, `shipment.labelsCreated`, `labelFile.ready`, `labelFile.creationFailed` (or set it in the partner system). The payment webhook needs no registration: the URL is sent per order.

## Assumptions / unverified

- Shipping base URL: overview says `api.shipping.montonio.com`, guides say `shipping.montonio.com/api/v2`. We use the guides.
- Carrier codes `omniva`, `smartpost`, `dpd` (docs only show `smartpost`, `venipak`; Omniva appears in a response sample).
- Pickup point endpoint takes lowercase `carrierCode`/`countryCode`; we send lowercase.
- Pickup point response shape taken from the guide; pagination not mentioned, so none handled.
- Webhook payment status values beyond PAID/PENDING/FAILED/CANCELLED map to `:unknown`.
- `labelFile.*` webhooks: we assume `data.labelFileUrl`.
- Shipping webhook dedupe key is `eventId`; payment key is (reference, status).
- Return redirect `/orders/:merchant_reference` does not exist yet.
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
