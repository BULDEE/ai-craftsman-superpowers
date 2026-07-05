# Strangler Fig

> "The most important reason to consider a strangler fig application over a cut-over rewrite is reduced risk." - Martin Fowler

The strangler fig is a vine that grows around a host tree, gradually taking over until the original rots away and the vine stands on its own. Applied to software (Fowler), it is the antidote to the big-bang rewrite: you grow a new system **around** the legacy one, redirect functionality piece by piece, and retire the old parts only once the new ones carry the load. At no point is the system down or unshippable.

## Why Not a Big-Bang Rewrite

A cut-over rewrite is a bet that you can rebuild everything correctly before the business needs change, with no incremental value until the end. It usually loses: the legacy behavior is under-documented, the deadline slips, and the two systems drift. The strangler fig trades that single huge risk for a stream of small, reversible ones. You deliver value from the first slice and can stop at any time with a working system.

Use it when the system is too large or too critical to replace at once. Do **not** use it for a small component you could rewrite safely in a day, or when the legacy system is genuinely disposable.

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

This keeps `main` always releasable: the new implementation ships dormant behind the flag until it is proven.

### Event Interception

Intercept the calls or events flowing into the legacy system and divert a subset to the new one. A facade, proxy, or router sits in front and decides, per request, whether the legacy or the new path handles it. This lets you migrate by route, by customer, or by percentage of traffic.

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

Without an ACL, the legacy model leaks into the new one and the rewrite quietly becomes a reshuffle. Treat the ACL as temporary scaffolding: it can be removed once the legacy side is gone.

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

## At the Architecture Level and the Code Level

Strangler fig is usually described for replacing a whole legacy system, but the same shape works inside a class. The **bubble** from [[legacy/legacy-techniques]] is a strangler at the code level: a new well-designed class that progressively takes over a legacy God Class, forwarding what it has not yet absorbed. Same philosophy, smaller radius: grow the new, fade the old, never rewrite in one shot.

## Pitfalls

| Pitfall | Consequence | Fix |
|---------|-------------|-----|
| Never removing the legacy path | Permanent dual maintenance, worst of both worlds | Schedule and enforce step 7 |
| No Anti-Corruption Layer | Legacy model leaks; rewrite becomes reshuffle | Translate at the boundary, both directions |
| Cutover with no parity net | Silent behavior changes reach production | Characterize before diverting traffic |
| Flipping 100% at once | You reintroduced the big-bang risk | Divert a cohort, compare, widen gradually |
| Flag left forever | Dead branches, confusing routing | Delete the flag with the legacy path |

## Related

- [[legacy/legacy-techniques]] - seams and the code-level bubble that strangles a God Class.
- [[legacy/characterization-testing]] - the parity net that makes each cutover safe.
- [[hexagonal]] - branch-by-abstraction is a port; the new implementation is an adapter.
- [[clean-architecture]] - the target design each strangled slice grows toward.
