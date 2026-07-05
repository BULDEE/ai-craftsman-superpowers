# Strangler Fig

> "The most important reason to consider a strangler fig application over a cut-over rewrite is reduced risk." - Martin Fowler

The strangler fig is a vine that grows around a host tree, gradually taking over until the original rots away and the vine stands on its own. Applied to software (Fowler), it is the antidote to the big-bang rewrite: you grow a new system **around** the legacy one, redirect functionality piece by piece, and retire the old parts only once the new ones carry the load. At no point is the system down or unshippable.

## Why Not a Big-Bang Rewrite

A cut-over rewrite is a bet that you can rebuild everything correctly before the business needs change, with no incremental value until the end. It usually loses: the legacy behavior is under-documented, the deadline slips, and the two systems drift. The strangler fig trades that single huge risk for a stream of small, reversible ones. You deliver value from the first slice and can stop at any time with a working system.

Use it when the system is too large or too critical to replace at once. Do **not** use it for a small component you could rewrite safely in a day, or when the legacy system is genuinely disposable.

| | Big-Bang Rewrite | Strangler Fig |
|---|------------------|---------------|
| Value delivered | Only at the end (maybe never) | From the first slice |
| Risk | One enormous bet | A stream of small, reversible ones |
| Rollback | All-or-nothing | Per slice, behind a flag |
| Two systems in sync | Diverge for months | Coexist deliberately, briefly |
| Best for | Truly disposable, tiny systems | Large, critical, long-lived systems |

## The Enabling Patterns

### Branch by Abstraction

Introduce an abstraction over the thing you want to replace, route all callers through it, then swap the implementation behind it without touching callers.

```typescript
// 1. Abstraction all callers depend on.
interface PaymentProcessor {
  charge(amount: Money, method: PaymentMethod): Receipt;
}

// 2. Old and new implementations live side by side behind it.
class LegacyPaymentProcessor implements PaymentProcessor { /* wraps the old code */ }
class NewPaymentProcessor implements PaymentProcessor { /* the rebuilt slice */ }

// 3. A flag decides which runs; flip it per-cohort, then delete the legacy one.
const processor: PaymentProcessor = flags.newPayments ? new NewPaymentProcessor() : new LegacyPaymentProcessor();
```

This keeps `main` always releasable: the new implementation ships dormant behind the flag until it is proven. The flag can be graduated from a boolean to a cohort so you divert a slice of traffic rather than all of it:

```typescript
// Graduated rollout: a percentage cohort, not an all-or-nothing switch.
function pickProcessor(order: Order): PaymentProcessor {
  const onNew = flags.newPaymentsPercent >= hashToPercent(order.id);
  return onNew ? new NewPaymentProcessor() : new LegacyPaymentProcessor();
}
```

### Event Interception

Intercept the calls or events flowing into the legacy system and divert a subset to the new one. A facade, proxy, or router sits in front and decides, per request, whether the legacy or the new path handles it. This lets you migrate by route, by customer, or by percentage of traffic.

```typescript
// A router at the edge sends captured routes to the new component, the rest to legacy.
class MigrationRouter {
  private readonly captured = new Set(["/orders", "/orders/:id"]);
  handle(req: HttpRequest): Promise<HttpResponse> {
    return this.captured.has(route(req))
      ? this.newComponent.handle(req)   // strangled route
      : this.legacy.handle(req);        // everything not yet migrated
  }
}
// Each migrated route is added to `captured` and the legacy handler shrinks.
```

### Asset Capture

Migrate the system by **capturing** whole responsibilities (assets), one at a time, into the new component. Each captured asset is fully moved and its legacy version removed, so the seam between old and new only ever shrinks.

## The Anti-Corruption Layer

The new code must not inherit the legacy model's warts. Put an **Anti-Corruption Layer** (ACL) between them: a translation boundary that maps the legacy shapes into the clean model the new code wants, and back. The new side speaks only its own language; the ACL absorbs the mismatch.

```typescript
// The new domain never sees the legacy row shape; the ACL translates at the edge.
class LegacyCustomerAcl {
  toDomain(row: LegacyCustomerRow): Customer {
    return Customer.rehydrate(new CustomerId(row.CUST_ID), Email.of(row.EMAIL_ADDR));
  }
}
```

The ACL is **bidirectional**: it translates legacy shapes into the clean model on the way in, and the clean model back into whatever the legacy side still expects on the way out, so both can coexist during the migration.

```typescript
class CustomerAcl {
  toDomain(row: LegacyCustomerRow): Customer {
    return Customer.rehydrate(new CustomerId(row.CUST_ID), Email.of(row.EMAIL_ADDR));
  }
  toLegacy(customer: Customer): LegacyCustomerRow {
    return { CUST_ID: customer.id.value, EMAIL_ADDR: customer.email.toString() };
  }
}
```

Without an ACL, the legacy model leaks into the new one and the rewrite quietly becomes a reshuffle. Treat the ACL as temporary scaffolding: it can be removed once the legacy side is gone.

## Shadow Running: Proving Parity Before You Divert

The safest cutover runs the new path **in parallel** with the legacy one for real traffic, comparing outputs without acting on the new result. Only when the diff is zero for long enough do you start diverting.

```typescript
function shippingWithShadow(order: Order): ShippingCost {
  const legacy = legacyShipping.calculate(order);
  try {
    const candidate = newShipping.calculate(order);
    if (!candidate.equals(legacy)) {
      metrics.increment("shipping.shadow.mismatch");
      logger.warn("shadow mismatch", { order: order.id, legacy, candidate });
    }
  } catch (e) {
    metrics.increment("shipping.shadow.error");   // never let the shadow break production
  }
  return legacy; // legacy still owns the real answer until parity is proven
}
```

The shadow path must never affect the response or throw into the real flow; it only observes. Watch the mismatch metric fall to zero before touching the traffic split.

## Incremental Cutover Checklist

For each slice you strangle:

1. Draw the abstraction/seam that fronts the legacy behavior; route all callers through it.
2. Add characterization tests on the legacy behavior so you can prove parity ([[legacy/characterization-testing]]).
3. Build the new implementation behind the abstraction, behind a flag, dormant.
4. Shadow-run or divert a small cohort (one route, one customer, 1% of traffic) through the new path.
5. Compare outputs; widen the cohort as confidence grows.
6. Flip fully; keep the flag and the legacy path for one safe rollback window.
7. **Delete** the legacy implementation, the flag, and (once no legacy remains) the ACL.

Step 7 is the one teams skip. A strangler that never removes the host is just added complexity.

## A Worked Cutover

Goal: replace a legacy monolithic `OrderService.calculateShipping()` (tangled, no tests) with a new `ShippingCalculator` module, without a freeze.

1. **Abstraction.** Introduce `ShippingPolicy` and route the monolith's one call site through it. `LegacyShippingPolicy` simply delegates to the old method, so behavior is unchanged and `main` stays green.
2. **Net.** Characterize the legacy output for a spread of orders (domestic, international, oversized, free-shipping). These become the parity oracle.
3. **New slice, dormant.** Build `NewShippingPolicy` behind a flag defaulting off, translating legacy order rows through an ACL into a clean `ShippingRequest`.
4. **Shadow.** Run the new policy in parallel for real traffic, log both results, and diff. Fix mismatches until they are zero for a week.
5. **Divert.** Flip the flag for 1% of orders, then 10%, then 50%, watching the parity metric and error rate at each step.
6. **Commit.** Flip to 100%; keep `LegacyShippingPolicy` and the flag for one rollback window.
7. **Delete.** Remove the legacy method, the flag, and once nothing else reads the legacy shape, the ACL.

At every step the system ships and can roll back. The old code is gone only when the new code has demonstrably carried production load.

## At the Architecture Level and the Code Level

Strangler fig is usually described for replacing a whole legacy system, but the same shape works inside a class. The **bubble** from [[legacy/legacy-techniques]] is a strangler at the code level: a new well-designed class that progressively takes over a legacy God Class, forwarding what it has not yet absorbed. Same philosophy, smaller radius: grow the new, fade the old, never rewrite in one shot.

## Measuring the Migration

A strangler needs a visible burn-down or it drifts into permanent dual-running. Track the shrinking seam:

| Metric | Meaning | Target |
|--------|---------|--------|
| % traffic on the new path | How far the cutover has progressed | 100%, then remove the flag |
| Shadow mismatch rate | Parity between old and new | 0 before diverting |
| Legacy call sites remaining | How much host is left | 0, then delete the abstraction |
| ACL translations remaining | Residual coupling to the legacy model | 0, then delete the ACL |

When every number reaches its target, the host tree is dead and the fig stands alone. Publish this burn-down so the migration stays funded and finished.

## When the Strangler Stalls

Migrations rot at the halfway point, where dual-running feels stable and the last slices are the hard ones. Symptoms and fixes:

- **The flag has lived for months.** Set a removal deadline per slice; a flag with no expiry is permanent complexity.
- **The new path handles only the easy cases.** The remaining legacy cases are exactly the ones worth migrating; schedule them explicitly instead of leaving the 20% forever.
- **Nobody owns the burn-down.** Assign the migration metrics to one person; unowned migrations never finish.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Never removing the legacy path | Permanent dual maintenance, worst of both worlds | Schedule and enforce step 7 |
| No Anti-Corruption Layer | Legacy model leaks; rewrite becomes reshuffle | Translate at the boundary, both directions |
| Cutover with no parity net | Silent behavior changes reach production | Characterize before diverting traffic |
| Flipping 100% at once | You reintroduced the big-bang risk | Divert a cohort, compare, widen gradually |
| Flag left forever | Dead branches, confusing routing | Delete the flag with the legacy path |
| Migrating only the easy cases | The hard 20% lives on legacy indefinitely | Schedule the hard slices explicitly |
| No owner for the burn-down | The migration stalls at 50% and never finishes | Assign the migration metrics to one person |

## The Flag Is Configuration, Not Code

Keep the rollout decision in configuration so widening the cohort never needs a deploy:

```yaml
# feature-flags.yaml - flip the percentage without shipping code.
new_shipping:
  enabled: true
  percent: 10        # raise to 25, 50, 100 as parity holds; then delete this block
```

Once `percent` reaches 100 and the mismatch metric has been zero for a safe window, remove the flag, the legacy path, and the ACL in that order.

## Rule

> Grow the new system around the old, prove parity slice by slice, and remove the host once the new one carries the load. A strangler that never strangles is just added complexity.

## Related

- [[legacy/legacy-techniques]] - seams and the code-level bubble that strangles a God Class.
- [[legacy/characterization-testing]] - the parity net that makes each cutover safe.
- [[hexagonal]] - branch-by-abstraction is a port; the new implementation is an adapter.
- [[clean-architecture]] - the target design each strangled slice grows toward.
