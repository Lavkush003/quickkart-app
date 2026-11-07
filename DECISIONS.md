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

- **How are duplicate orders prevented?** (key generation, lifetime, storage)
- **What does the user see on timeout / lost response?**
- **Edge cases you handled:**
- **Edge cases you know you did NOT handle:**

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:**
- **How live updates propagate, and how you avoid leaks:**
- **Force / optional update UX:**
- **Store closed UX:**
- **Server-driven home: robustness to bad config:**

## 4. Feature 3 (if attempted)

## 5. Other decisions

- Packages added (and why):
- Refactors you made to the existing code (and why):

## 6. Looking ahead

- What would you do with one more week?
- What breaks first at 10× users (10k DAU)? What would you change?
- How would you ship a hotfix for a critical bug without a store release?
