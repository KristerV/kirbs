# Kirbs 2.0 — own shop, decoupled from Yaga

Goal: run our own storefront (`/`) with great categorization and search, track an ad experiment
with `ab_funnel`, and take payment + delivery through Montonio. Yaga becomes one sales channel
among several instead of the system's identity.

## Decisions

- **Own stock only.** No marketplace/seller payouts for the shop.
- **Categories:** one primary category per item (tree, max 2 levels under an audience root) plus
  typed attributes for everything filterable. Free tags are not categories.
- **Top level is audience-based** so grown-up items and toys fit later: `Lapsed` (fully built),
  `Naised`, `Mehed`, `Kodu`, `Mänguasjad` (stubs only).
- **Search:** Postgres FTS + `pg_trgm` + `unaccent`, synonym table, facet filters. No external engine yet.
- **Payment + delivery:** Montonio (Stargate payments API + Shipping API, Montonio shipping contract).
  Bank payments (pangalink) first, cards optional. Parcel machines: Omniva, DPD, Smartposti.
- **Manual first:** the shop launches with reserve → manual bank transfer → manual postage, so the
  ad experiment can start before Montonio onboarding finishes. Montonio then replaces the manual steps.
- **Tracking:** `ab_funnel` (`../abtest`). Funnel: `shop_viewed → item_viewed → reserved → checkout_started → paid`.
- Landing moves: current landing → `/muuda` ("sell with kirbs"); `/` becomes the shop.

## Phases and issues

### Phase 0 — Foundation (sequential, blocks everything)
1. Decouple Item from Yaga: `YagaListing` resource (`yaga_id`, `yaga_slug`, `uploaded_at`,
   `upload_error`, listing status); split lifecycle status from channel status; migrate data;
   update uploader, sold-checker, importer, status services.
2. `Category` resource (self-referencing, slug, Estonian name, position) + seed `Lapsed` tree
   + stub audience roots; `YagaCategoryMapping` used only for Yaga uploads.
3. Typed item attributes: `category_id`, age/gender group, season, condition, normalized brand,
   size, colors, materials, `search_text`, parcel size class + weight, public `slug`,
   `published_at`, `kirbs_status` (`available | reserved | sold`).

### Phase 1 — Categorization
4. Taxonomy source-of-truth doc (`docs/taxonomy.md`): tree + attribute enums.
5. `Ai.ItemCategorize` service (vision LLM via OpenRouter, structured output constrained to the tree).
   Run it on new items during intake.
6. **Backfill** of all live items (see "Backfill" below).
7. Admin editing of category/attributes inside the existing item review flow.

### Phase 2 — Storefront
8. Move current landing to `/muuda`.
9. New shop `/` (LiveView): grid of available items.
10. Item page `/p/:slug`.
11. Category pages with breadcrumbs.
12. Search: Ash read action(s) on `Item` — FTS + trigram + synonyms + facets (brand, size, gender,
    season, condition, price, category).
13. Public image delivery: thumbnails/responsive sizes.
14. SEO basics: titles, OG tags, sitemap.

### Phase 3 — Tracking
15. Install `ab_funnel` (migration, plug, `on_mount`, `/admin/ab`); ad-friendly browser pipeline.
16. Declare the experiment + funnel steps.
17. Instrument LiveViews (`track`, `identify_by_email` at checkout).
18. Ad plumbing: UTM capture, Meta pixel/conversions hook.

### Phase 4 — Checkout, manual
19. `Order` / `OrderItem` resources; reservation with timeout (Oban) so qty-1 items can't double-sell.
20. Checkout LiveView: contact + delivery choice + shipping price.
21. Manual payment: confirmation email with transfer instructions + admin "mark paid".
22. Manual postage admin view.
23. Transactional emails (received / paid / shipped).

### Phase 5 — Montonio payment (code can be written against sandbox docs; needs credentials)
24. Account + credentials (HUMAN: sign up, business verification; keys into `Secrets`).
25. `Montonio.CreatePaymentOrder` service (HS256 JWT → `/api/orders` → `paymentUrl`).
26. Return + webhook endpoints (verify token, `paymentStatus == PAID`, idempotent). Webhooks are
    inherently controller-shaped — the one allowed exception to "prefer LiveView".
27. Failure paths: expired/unpaid releases reservation; refunds.

### Phase 6 — Montonio shipping
28. Daily pickup-point sync (Oban).
29. Pickup-point selector in checkout.
30. `Montonio.CreateShipment` after payment + labels + shipment webhook.
31. Shipping price per carrier/parcel size.
32. Admin shipping view (labels, tracking).

### Phase 7 — Cross-cutting
33. Cross-channel sold sync (sold on kirbs → delist from Yaga; Yaga sale → kirbs sold).
34. Accounting/payouts learn the kirbs channel (client payouts for shop sales).
35. Legal pages (terms, returns/14-day withdrawal, privacy, company details).
36. Tests + `mix precommit` for every issue.

## Backfill (issue 6)

The items to recategorize live in **production**, not local dev (local has ~41 test items).
Agents have **read-only** prod DB access (`psql "postgresql://readonly@localhost:5433/<db>"`) and must
never write to prod. So the backfill ships as an in-app, idempotent, resumable operation that runs
*on prod* (Oban job + admin button, with dry-run and a review screen) rather than an MCP or SQL
pasted by hand. Agents may read prod to size the problem and sanity-check category distributions.

## Out of scope / human tasks
- Montonio account + verification (24), ad creative/budget, legal text wording sign-off,
  running the prod backfill, and all git operations (commits are the owner's).

## Execution order
Phase 0 → (Phase 1, 2, 3 in parallel worktrees) → Phase 4 → Phase 5/6 → Phase 7.
