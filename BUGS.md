# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Cart mutations are not persisted (QK-101)

- **Symptom:** Decrementing/removing an item or removing a coupon appears to work until restart; the previous cart contents return. Concurrent taps can also lose quantity updates.
- **Steps to reproduce:**
  1. Add a product twice, decrement or remove it, then restart and restore the cart.
  2. Repeat an increment twice before the first storage write completes.
- **Root cause:** `CartController.decrement`, `remove` and `removeCoupon` changed only in-memory state. Other mutations could read the same old state while an earlier asynchronous save was pending.
- **Fix:** Serialize cart mutations, persist every updated cart (and clear the stored cart on checkout) before publishing the new state.
- **Test:** `test/cart_persistence_regression_test.dart` → decrement, remove, removeCoupon persistence tests and simultaneous increments test.
- **Commits:** test `335da37`, `be3f990` → fix `5b19e11`

---

## BUG-2: Pull-to-refresh shows stale catalog prices (QK-102)

- **Symptom:** A changed product price remains unchanged after pull-to-refresh.
- **Steps to reproduce:**
  1. Load the product catalog.
  2. Change a product price through Dev tools and pull to refresh.
- **Root cause:** `CatalogController.refresh` repeated the same GET, which `ApiClient` served from its ten-minute in-memory response cache.
- **Fix:** Added an opt-in GET cache bypass and use it for explicit catalog refresh/retry; normal reads retain caching.
- **Test:** `test/catalog_refresh_regression_test.dart` → pull-to-refresh fetches updated catalog prices.
- **Commits:** test `335da37` → fix `5b19e11`

---

## BUG-3: Order history remains stale after checkout

- **Symptom:** A recently placed order may not appear in My orders until the app is restarted.
- **Steps to reproduce:**
  1. Load My orders while there are no orders.
  2. Place an order and open My orders again.
- **Root cause:** The completed `ordersProvider` result was not invalidated after checkout, and the API client could also serve a cached `/v1/orders` response.
- **Fix:** Invalidate order history after successful checkout and fetch order history without using the GET response cache.
- **Test:** `test/catalog_refresh_regression_test.dart` → order history refreshes after a successful checkout.
- **Commits:** test `335da37` → fix `5b19e11`

---

## BUG-4: Offline pages can show products from another category

- **Symptom:** After viewing one category online, a different category can show the first category's products while offline.
- **Steps to reproduce:**
  1. Load the fruits and beverages categories online.
  2. Go offline and load each category again.
- **Root cause:** `CatalogRepository` keyed cached pages only by cursor, so first pages for different categories overwrote each other.
- **Fix:** Include category, page size and cursor in the offline page-cache key.
- **Test:** `test/catalog_refresh_regression_test.dart` → offline fallback keeps catalog pages scoped to their category.
- **Commits:** test `b5e0308` → fix `5b19e11`

---

## BUG-5: Checkout can create duplicate orders after a lost response

- **Symptom:** Retrying after a timeout or submitting twice can create multiple orders for one cart.
- **Steps to reproduce:**
  1. Add an item and queue two lost order responses in Dev tools.
  2. Place the order, then retry after the timeout; alternatively submit twice on a slow connection.
- **Root cause:** Checkout retried POST requests without an idempotency key and accepted simultaneous calls as separate submissions.
- **Fix:** Persist a payload-bound idempotency key, send it on every attempt, reuse the in-flight request, and show an honest message after an ambiguous timeout.
- **Test:** `test/checkout_idempotency_regression_test.dart` → lost response/retry and simultaneous place-order tests.
- **Commits:** test `a937000` → fix `5b19e11`

---

## BUG-6: Cart at the free-delivery threshold pays a fee

- **Symptom:** A cart worth exactly ₹199 after discounts is charged delivery.
- **Steps to reproduce:**
  1. Build a cart whose post-coupon payable amount equals the configured free-delivery threshold.
  2. Inspect the cart total.
- **Root cause:** `CartPricing.compute` used a strict greater-than comparison although the rule grants free delivery at the threshold.
- **Fix:** Make delivery free when payable value is greater than or equal to the threshold.
- **Test:** `test/cart_pricing_regression_test.dart` → cart at the free-delivery threshold has no delivery fee.
- **Commits:** test `335da37` → fix `5b19e11`

---

## BUG-7: Legacy catalog products crash category browsing

- **Symptom:** Opening a category containing legacy products can throw while parsing the catalog response.
- **Steps to reproduce:**
  1. Open the dairy category, which includes legacy product payloads.
  2. The response's null MRP and string stock values reach strict DTO casts.
- **Root cause:** `ProductDto.fromJson` required a numeric MRP and integer stock, but the documented legacy payload omits MRP and encodes stock as a string.
- **Fix:** Use the selling price when legacy MRP is absent and parse integer stock values from supported numeric/string forms; malformed values still fail explicitly.
- **Test:** `test/catalog_refresh_regression_test.dart` → legacy catalog fields parse without crashing category browsing.
- **Commits:** test `b5e0308` → fix `5b19e11`

---

## BUG-8: Concurrent pagination appends duplicate products

- **Symptom:** Rapid scrolling can show the same page of products twice.
- **Steps to reproduce:**
  1. Load the first catalog page.
  2. Trigger `loadMore` twice before the first request finishes.
- **Root cause:** `CatalogController.loadMore` did not reject another request while `isLoadingMore` was already true.
- **Fix:** Ignore overlapping pagination calls while a page is loading.
- **Test:** `test/catalog_refresh_regression_test.dart` → concurrent pagination requests do not append duplicate products.
- **Commits:** test `be3f990` → fix `5b19e11`

---

## BUG-9: Displayed prices omit paise

- **Symptom:** Products priced at ₹19.99 are displayed as ₹19.
- **Steps to reproduce:**
  1. View a product with a price containing paise, such as ₹19.99.
  2. Compare the displayed price to the catalog value.
- **Root cause:** `formatMoney` discarded the remainder when converting paise to rupees.
- **Fix:** Include a zero-padded paise fraction when nonzero, while keeping whole-rupee display unchanged.
- **Test:** `test/money_format_regression_test.dart` → formats paise when a displayed amount has a fractional rupee.
- **Commits:** test `be3f990` → fix `5b19e11`

---

## Suspicious but NOT a bug

- A coupon below its minimum cart value stays applied while providing no discount; this is intentional per `docs/BUSINESS_RULES.md` §3.
- Normal catalog GETs remain cached to support efficient browsing. Only explicit refresh and mutable order-history reads bypass that cache.
- Remote-config caching, live updates, version gating and server-driven home layout are Feature 2 work and remain for the corresponding phase.
