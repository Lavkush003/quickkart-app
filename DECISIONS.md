# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?** Before each checkout order
  request, so prices, stock, product availability, and coupon terms are checked
  against the current server state. No order request is sent while review is
  required.
- **What does the user see for each kind of change?** Price decreases are
  applied without review. Price increases, quantity reductions, removals, and
  coupon updates/removals appear in a review dialog with item names and
  before/after details where available. The customer must accept and tap Place
  order again.
- **What happens to out-of-stock / discontinued items?** They are removed from
  the cart and listed in the review. Reduced stock clamps quantity to the
  purchasable amount (stock limited by the per-order maximum) and requires
  acceptance.
- **Offline-built carts:** Cart intent is retained locally, but a failed
  reconciliation does not partially update the cart or submit an order. The
  checkout error is surfaced and the customer can retry.
- **Alternatives considered and rejected:** Silently applying price increases,
  removals, or coupon rule changes would not provide informed consent. Fetching
  product details individually would violate the API batch limit and add
  unnecessary requests, so product IDs are fetched in batches of at most 50.
  Malformed/incomplete batch responses fail reconciliation rather than being
  treated as successful data.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** After fresh config, cart
  reconciliation, customer consent, and local validation, checkout generates a
  UUID key and persists it with the exact cart and pricing payload before the
  POST. Retries reuse that snapshot and key. The record is removed only after
  the order and cart cleanup are confirmed.
- **What does the user see on timeout / lost response?** Checkout retries the
  same request once. If it still cannot confirm the response, it shows an
  explicit unknown-status message and changes the action to “Check order
  status”; it does not claim failure or create a new logical order. With the
  store closed, order history is checked for a unique exact match created after
  the persisted attempt time. Ambiguous or unavailable lookup remains unknown.
- **Edge cases you handled:** Double taps share one in-flight request. Fresh
  config verifies connectivity and store status before ordering. The pending
  payload survives process restarts and cart edits; a confirmed response is
  persisted before cart cleanup. Server-side price/stock/coupon conflicts are
  reconciled and shown for review. A coupon below its minimum remains on the
  cart but is omitted from the order payload, matching the business rule that
  it gives no discount while still allowing checkout.
- **Edge cases you know you did NOT handle:** If local storage becomes
  unavailable while persisting a confirmed order, server success cannot be
  rolled back; the server idempotency key still prevents a duplicate, but
  recovery may require the next app launch or user retry.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** Startup hydrates the last valid
  config from `KeyValueStore` before the first frame and begins a forced remote
  refresh after `runApp`. A successful, validated response replaces the cache.
  Offline or malformed responses never overwrite it; ordinary loads use the
  cache and then safe defaults, while checkout's `loadFresh()` still surfaces
  failures instead of returning fallback data. Concurrent refreshes share one
  request.
- **How live updates propagate, and how you avoid leaks:** The app-config
  controller owns the single remote-update subscription, fetches validated
  config on updates, and keeps its current state if refresh fails. Riverpod
  disposal cancels the subscription. Config-dependent screens watch controller
  state rather than managing independent listeners.
- **Force / optional update UX:** Dotted versions are compared numerically,
  with omitted trailing segments treated as zero. Malformed version values fail
  open. A root-level gate blocks all routes for required updates and opens the
  configured `update_url`; optional prompts can be dismissed and the dismissed
  `latest_version` is persisted so it is not shown again.
- **Store closed UX:**
- **Server-driven home: robustness to bad config:**

## 4. Feature 3 (if attempted)

## 5. Other decisions

- Packages added (and why): `url_launcher` opens the update link supplied by
  remote configuration from both required and optional update actions.
- Refactors you made to the existing code (and why): Added an app-level update
  gate in `MaterialApp.builder` so a required update also blocks routes already
  open when live config changes.

## 6. Looking ahead

- What would you do with one more week?
- What breaks first at 10× users (10k DAU)? What would you change?
- How would you ship a hotfix for a critical bug without a store release?
