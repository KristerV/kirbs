# Funnel tracking

Experiments live in `Kirbs.ABTests` (shop experiment), dashboard at `/admin/ab` (admin login required).
All events go through `KirbsWeb.Track.event/3`, which calls `AbFunnel.track/3`, merges UTM
attribution into the metadata, and pushes the Meta pixel event when a pixel is configured.

Requirement: the LiveView must be in a `live_session` with
`on_mount: [AbFunnel.LiveView, KirbsWeb.LiveTracking]` (the public `/` session has this) and the
route must go through the `:browser` pipeline (which runs `AbFunnel.Plug.Visitor` and
`KirbsWeb.Plugs.CaptureUtm`). Events fire only on the connected mount; the disconnected render
is ignored by ab_funnel, so calling from `mount/3` or `handle_params/3` is safe.

## Which event, from where

| Event (atom)        | ab_funnel name     | Meta pixel         | Fire from                                              |
|---------------------|--------------------|--------------------|--------------------------------------------------------|
| `:shop_viewed`      | `shop_viewed`      | `PageView`         | shop index LiveView `mount/3` (entry of the funnel)    |
| `:item_viewed`      | `item_viewed`      | `ViewContent`      | public item page `mount/3` / `handle_params/3`         |
| `:reserved`         | `reserved`         | `AddToCart`        | the reserve action's `handle_event` after it succeeds  |
| `:checkout_started` | `checkout_started` | `InitiateCheckout` | checkout page mount / "go to payment" click            |
| `:paid`             | `paid`             | `Purchase`         | payment confirmation (LiveView or webhook, see below)  |

```elixir
socket = KirbsWeb.Track.event(socket, :item_viewed, %{item_id: item.id})
socket = KirbsWeb.Track.event(socket, :paid, %{order_id: id, value: 49.0, currency: "EUR"})
```

Pixel data keys picked from the metadata: `value`, `currency`, `content_ids`, `content_name`.

Notes:

- `:paid` when confirmed by a server-side webhook has no visitor on the conn. Store the visitor id
  (`socket.assigns.ab_funnel_visitor_id`) and the assignments on the order at checkout, then
  call `AbFunnel.track(visitor_id, "paid", assignments, metadata)`. If the buyer lands back on a
  LiveView after payment, prefer `Track.event(socket, :paid, ...)`.
- Controllers: `KirbsWeb.Track.conn_event(conn, :name, meta)`.

## Identify at checkout

As soon as the buyer has given an email (before an account exists), bind the browser to the person
so phone-to-laptop journeys join up:

```elixir
AbFunnel.identify_by_email(socket, email)
```

Signed-in users are bound automatically.

## UTM / ad attribution

`KirbsWeb.Plugs.CaptureUtm` stores `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`,
`utm_term`, `ad_id`, `fbclid` from any request carrying them into the session (`kirbs_utm`).
`KirbsWeb.LiveTracking` exposes them as `@utm`, and `Track.event` merges them into every event's
metadata. ab_funnel also records its own `source:<utm_source>` event.

Ad-landing pipeline: today there is a single `:browser` pipeline and both plugs are in it. If a
separate `:ad_landing` pipeline is added for the storefront, it must include
`plug AbFunnel.Plug.Visitor` (after user loading) and `plug KirbsWeb.Plugs.CaptureUtm`, or
those visitors are not tracked.

## Meta pixel

Off by default. Enable in config (e.g. `config/runtime.exs`):

```elixir
config :kirbs, :meta_pixel, enabled: true, pixel_id: System.get_env("META_PIXEL_ID")
```

When enabled, `@meta_pixel_id` is assigned by `KirbsWeb.LiveTracking`. The storefront layout must
render, once per page:

```heex
<div :if={assigns[:meta_pixel_id]} id="meta-pixel" phx-hook="MetaPixel" data-pixel-id={@meta_pixel_id}></div>
```

The hook (`assets/js/hooks/meta_pixel.js`, registered in `app.js`) loads the pixel, sends `PageView`
on mount, and fires whatever `Track.event` pushes via the `meta_pixel` push_event. Note the hook
already sends `PageView` on mount; `:shop_viewed` also maps to PageView, so you may see two on the
shop index. Drop one if that matters for the pixel's optimisation.

## Dev note

ab_funnel is a GitHub dependency (`github: "kristerv/ab_funnel"`) so deploys work. For local
development against `/home/krister/code/abtest`, temporarily swap to
`{:ab_funnel, path: "../abtest", override: true}`; do not commit that.

## Parallel worktrees

Set `DB_NAME=kirbs_p3` (dev and test) to avoid sharing a database with other worktrees.
