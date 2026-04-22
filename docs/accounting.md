# Accounting

This spec covers three related changes:

1. **Payout LiveView changes** — the existing per-client payment table switches from "actual paid" to "owed for that calendar month", with a cutoff datetime dividing old behavior from new.
2. **New Accounting LiveView** — monthly table of outbound payouts showing total, profit, and sent amount per payout.
3. **Yaga monthly withdraw** — Oban cron that, at the start of each Tallinn month, asks Yaga to transfer available funds to kirbs's bank.

Domain assumptions that apply throughout:
- Split is always 50/50 (client / kirbs). If this ever changes, lots of things change — not this spec's problem.
- All month bucketing is in Europe/Tallinn. `sold_at` and `sent_at` are UTC in the DB; convert before grouping.
- Yaga takes no seller fees (buyer pays fees, invisible to us). So `item.sold_price` == money that arrives to kirbs for that item.
- Currency is EUR throughout. Not modeled; assumed.

---

## Pre-coding questions

These must be resolved **before** implementation starts. Don't skip.

### Q1. Cutoff datetime (global, hardcoded)

A single UTC datetime is hardcoded in the code (module attribute or config). Its meaning: everything with `sent_at <= cutoff` is "old world" (pre-cutoff payouts are the source of truth); everything with `sold_at > cutoff` is "new world" (calendar-month sales are the source of truth).

Run in production DB:

```sql
SELECT id, client_id, amount, sent_at, for_month
FROM payouts
ORDER BY sent_at DESC
LIMIT 20;
```

Paste the result. We'll pick the `sent_at` of the most recent payout as the cutoff. Expected value: around 2026-04-05.

### Q2. When does `item.status` become `:sold`?

Yaga has an escrow mechanism. Confirm (via code read + possibly asking Yaga support) whether `item.status = :sold` and `sold_at` are set:

- (a) when the buyer pays (before escrow clears), or
- (b) after escrow clears and funds are finalized to kirbs.

Preference is (b), because then `sold_at` == "money is really mine for this item" and the accounting logic is honest. If current code does (a), we either switch it or live with the small race where an accounting row exists before funds settle.

Explicit non-goal: we are NOT modeling reversals. If an item gets reversed after being marked sold, that's handled manually.

### Q3. Yaga monthly withdraw API

Does Yaga expose an API for "transfer available balance to my linked bank account"? If yes, confirm endpoint + auth. If no, this part of the spec is deferred until they do.

---

## Change 1: Payout LiveView rework

**File:** `lib/kirbs_web/live/payout_live/index.ex`

### Current columns

| Client | Jan 2026 | Feb 2026 | ... | Total Paid | Unsent | Actions |

Each month cell = sum of `payouts.amount where for_month = month`. Total Paid = sum of payouts. Unsent = `client_share_lifetime - total_paid`. Send button in Actions.

### New columns

| Client | Jan 2026 | Feb 2026 | ... | Total Paid |

- **Unsent** column: removed.
- **Actions** column: removed. The Send button moves **into the month column cell** for the month it applies to.
- **Total Paid**: unchanged (sum of all payouts for that client).

### Month column logic (the interesting bit)

Let `cutoff = @cutoff_datetime` and `cutoff_month = Tallinn month containing cutoff` (e.g. `2026-04` if cutoff is `2026-04-05 09:00 UTC`).

For a client row and column for month M (Tallinn):

- **If M < cutoff_month** (pre-cutoff): 
  cell value = `sum(payouts.amount where client_id=c AND for_month=M)`
  (Same as today.)

- **If M >= cutoff_month** (post-cutoff):
  cell value = `sum(item.sold_price where item.bag.client_id=c AND sold_at > cutoff AND Tallinn-month(sold_at) = M) / 2`
  
  Note the `sold_at > cutoff` filter: for the month M that contains the cutoff (April in our case), early-April sales that were already included in the pre-cutoff March payout are filtered out. They've been paid; we don't owe them again.

- **If a payout already exists for a post-cutoff month** (i.e. `sent_at > cutoff AND for_month = M`):
  cell displays the payout amount(s) as "paid", no Send button. Amount should equal the owed value above (since Send prefills exactly that).

### Which columns appear?

Union of:
- All distinct `for_month` values across all payouts (drives pre-cutoff columns).
- All Tallinn calendar months from `cutoff_month` through current Tallinn month that have any post-cutoff sales (drives post-cutoff columns).

Sort chronologically.

### Cell display

- Paid (post-cutoff month with matching payout, or any pre-cutoff month with payout): show amount, normal color. Clickable if today's detail-modal behavior exists — keep.
- Unpaid and owed > 0 (post-cutoff month, no payout, sales exist): show amount in **orange** with an inline **Send** button.
- Zero / no activity: dash, as today.

### Send button behavior

Moved inline into the month cell. Clicking opens the existing payout-create modal with:
- `client_id` = row's client
- `amount` = that cell's owed value
- `for_month` = that column's month (first day, Tallinn-local, stored as the existing `for_month` date)
- `sent_at` = now

This replaces today's modal logic that figured out `for_month` heuristically — the column tells us directly.

### Pre-cutoff months straddling (edge case)

In the expected cutoff scenario, the last payout's `for_month` is March, and no post-cutoff sales are attributed back to March. So there's no column collision. 

If a collision ever happens (same month has both a pre-cutoff payout and post-cutoff owed amount), sum them into a single cell and show as paid/unpaid accordingly. Unlikely in practice; don't over-engineer.

---

## Change 2: Accounting LiveView (new)

**Route:** `/accounting` (final path TBD).

### Purpose

A read-only monthly report of **outbound** client payouts — what went out of kirbs's bank to clients, and the profit kirbs booked doing so.

### UI

- Month selector (dropdown). Options = distinct `payouts.for_month` values, most recent first. Default = most recent.
- Table, one row per `Payout` where `for_month = selected`:

| Date | Total | Profit | Sent |
|------|-------|--------|------|
| `sent_at` (Tallinn, date only) | `payout.amount * 2` | `payout.amount` | `payout.amount` |

- Sort ascending by `sent_at`.
- Optional footer row with column sums. Add it — cheap and useful.

### Notes

- With the 50/50 assumption, Total/Profit/Sent are pure math off `payout.amount`. No need to link payouts to items.
- This view is **cutoff-agnostic**. It just lists payouts per `for_month`. Old and new payouts both show up naturally.
- This view is **seller-side only** (money kirbs sends out → client). A buyer-side view (money Yaga sends in → kirbs) is a likely future addition but out of scope here.

---

## Change 3: Oban cron — monthly Yaga withdraw

### Schedule

`0 0 1 * *` in `Europe/Tallinn` — midnight local time on the 1st of each month.

Use Oban's cron plugin with timezone support.

### Behavior

1. Call Yaga's withdrawal endpoint (pending Q3 above).
2. Ask it to transfer the full available balance to kirbs's linked bank account.
3. Log the attempt. No retry loop — if it fails, fix manually.

The resulting bank deposit lands asynchronously. It doesn't feed any LiveView directly; it just gets money into kirbs's bank so the next round of client payouts can happen.

### Module

Suggested: `Kirbs.Services.YagaWithdraw` with `run/0` returning `{:ok, result}` per project convention (service pattern, single responsibility — just the withdraw request).

Worker: `Kirbs.Workers.YagaMonthlyWithdraw` that calls `YagaWithdraw.run/0`.

---

## Implementation order

1. Resolve pre-coding Q1 (cutoff SQL), Q2 (escrow timing), Q3 (Yaga withdraw API).
2. Add `@cutoff_datetime` as a module attribute (config/compile-time constant).
3. Build helper function(s) for "client's owed amount for Tallinn month M" that the Payout LiveView consumes.
4. Rework Payout LiveView (columns, cells, Send button placement, orange styling).
5. Build Accounting LiveView + route.
6. Add Oban cron + Yaga withdraw service, once Q3 answered.

---

## Known blindspots (tracked, not blockers)

- **Buyer-side transactions** (money Yaga → kirbs) are not captured anywhere today and not in this spec. Likely needed eventually for reconciliation / tax reporting.
- **Sold_at vs money-actually-arrived timing** — per Q2, these may differ slightly. Accepted.
- **Reversals** — explicitly out of scope. Manual correction if/when it happens.
- **50/50 split** is hardcoded everywhere. Any change to this requires a broader redesign, not a spec update.
- **Accounting view row granularity** is per-payout (option B). A payout may cover mixed months (pre-cutoff). Accepted as "messy but correct" — `for_month` picks a single month label per payout and we trust that.
