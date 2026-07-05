# Clean Architecture

> "Source code dependencies must point only inward, toward higher-level policies." - Robert C. Martin
>
> "If you think good architecture is expensive, try bad architecture." - Brian Foote & Joseph Yoder

Clean Architecture is one actionable synthesis of Hexagonal (Ports & Adapters, Cockburn), DCI (Coplien & Reenskaug), and BCE (Jacobson). They share one objective: **separation of concerns by layering**, with at least one layer for business rules and another for interfaces.

## The Five Properties of a Clean System

A system built this way is:

| Property | Meaning |
|----------|---------|
| Independent of frameworks | The framework is a tool you use, not a cage you live in |
| Testable | Business rules run without UI, database, or web server |
| Independent of UI | Swap web for CLI without touching business rules |
| Independent of the database | Swap Postgres for Mongo without touching business rules |
| Independent of any external agency | Business rules know nothing of the outside world |

If a change to the database schema, the web framework, or the JSON shape forces a change in your domain code, the architecture has already failed.

## The Concentric Circles

The further **inward** you go, the **higher-level** and more stable the code. Outer circles are mechanisms; inner circles are policies.

| Circle (in → out) | Contains | Changes when | This plugin's layer |
|-------------------|----------|--------------|---------------------|
| **Entities** | Enterprise Critical Business Rules | Almost never | `Domain/` |
| **Use Cases** | Application-specific business rules | A use case's behavior changes | `Application/` |
| **Interface Adapters** | Controllers, Presenters, Gateways, Repositories (MVC + SQL live here) | The delivery mechanism changes | `Infrastructure/`, `Presentation/` |
| **Frameworks & Drivers** | Web, DB, UI, devices, external services (glue code only) | A vendor/tool changes | framework config, vendor SDKs |

There is no rule that says exactly four. Add circles as needed; the Dependency Rule always holds.

## The Dependency Rule

> **Source code dependencies must point only inward.**

- Nothing in an inner circle may name anything in an outer circle: not a class, function, variable, or **data format**.
- A SQL row structure, an `HttpRequest`, an ORM entity annotation: none of these may be referenced inward.
- If a name declared in an outer circle appears in an inner circle, you have a violation.

```php
// Bad - Domain entity depends on the framework (outward dependency)
namespace App\Domain\Entity;

use Doctrine\ORM\Mapping as ORM;      // ✗ framework in the innermost circle
use Symfony\Component\HttpFoundation\Request; // ✗ web in the domain

#[ORM\Entity]
final class Order { /* ... */ }

// Good - Domain is pure; mapping lives outward in Infrastructure
namespace App\Domain\Entity;

final class Order
{
    private function __construct(
        private readonly OrderId $id,
        private OrderStatus $status,
    ) {}
    // no framework, no persistence, no transport
}
```

## Crossing a Boundary Against the Flow of Control

Control flows outer → inner → outer (Controller → Use Case → Presenter). But source dependencies must all point inward. Resolve the apparent contradiction with the **Dependency Inversion Principle**: the inner circle declares an interface (an *output port*), the outer circle implements it.

```typescript
// Use Case (inner) owns the port it calls - it never names the Presenter.
interface CheckoutOutputPort {
  present(result: CheckoutResult): void;
}

class CheckoutUseCase {
  constructor(private readonly output: CheckoutOutputPort) {}
  execute(request: CheckoutRequest): void {
    const result = /* orchestrate entities */;
    this.output.present(result); // calls inward-declared interface
  }
}

// Presenter (outer) implements the inner port - dependency points inward.
class JsonCheckoutPresenter implements CheckoutOutputPort {
  present(result: CheckoutResult): void { /* build ViewModel / HTTP body */ }
}
```

Dynamic polymorphism lets source-code dependencies **oppose** the flow of control at exactly the boundary points you choose. This is the single technique used to cross every boundary in the architecture.

## Which Data Crosses the Boundary

Only **simple, isolated data structures** cross: DTOs, plain structs, function arguments. Never pass an Entity object or a database row across a boundary; that would force the inner circle to know an outer format.

- Use cases accept a **request model** and return a **response model**.
- These models derive from nothing (`HttpRequest`, ORM rows, framework base classes are all forbidden).
- Do **not** let request/response models hold references to Entities: they change for different reasons (a Common Closure / Single Responsibility violation), producing tramp data and conditionals.

## Entities vs Use Cases

| | Entities | Use Cases |
|---|----------|-----------|
| Holds | Enterprise Critical Business Rules | Application-specific rules |
| Job | Encapsulate the most general, high-level rules | Orchestrate the flow of data to/from Entities |
| Knows about | Nothing external | Entities (only) |
| Stability | Highest - "the family jewels" | Changes when the application's behavior changes |

## The Humble Object Pattern

Presenters are a Humble Object. Split behavior into a **hard-to-test** module (kept humble, stripped to its barest essence) and an **easy-to-test** module (holds the logic).

- The **View** is humble: it only moves fields from a ViewModel into the screen.
- The **Presenter** is testable: it formats dates, currency, and flags into the ViewModel.
- The same split defines Database Gateways (humble SQL) vs the testable code that uses them.

This is why the boundary is also a **testability boundary**: everything on the policy side is unit-testable without the mechanism.

## Screaming Architecture

> The architecture should scream its **use cases**, not its framework.

A top-level directory listing should read "Payroll System" or "Inventory", not "Rails" or "Spring". Frameworks are tools, not ways of life. A good architecture lets you **defer** the choice of database, web server, and framework, and change your mind later.

```
# Screams the framework (bad)          # Screams the domain (good)
src/                                   src/
  Controllers/                           Billing/
  Models/                                Catalog/
  Views/                                 Shipping/
  Migrations/                            Ordering/
```

## Partial Boundaries (Trade-offs)

A full boundary (reciprocal interfaces both directions) is expensive to build and maintain. Cheaper placeholders that keep the option open:

| Technique | What you keep | What degrades |
|-----------|---------------|---------------|
| Skip the last step | Full interfaces + DTOs, but one deployable component | No independent versioning; deps can drift back |
| One-dimensional (Strategy) | An interface used by clients, implemented outward | A backchannel can appear without reciprocal interfaces |
| Facade | A single class listing services | Even dependency inversion is sacrificed; transitive coupling |

It is the architect's job to decide **where** a boundary might one day exist, and whether to build it fully, partially, or not yet.

## Detection Signals

These smells indicate a Dependency Rule or boundary failure. This plugin flags several structurally:

| Smell | Rule signal | Why it breaks the architecture |
|-------|-------------|-------------------------------|
| Business logic inside a controller | controller-leak rule | Policy leaked into the outermost circle |
| God class doing orchestration + persistence + formatting | `GOD001` | A boundary that should exist was never drawn |
| Deep nesting / branching on external state | `NEST001` | Missing polymorphic boundary (Open/Closed) |
| Framework/ORM import inside `Domain/` | layer validation | Inner circle names an outer circle |
| Entity passed to the view or serialized directly | (review) | Entity crosses a boundary as an outer format |

## Mapping to This Plugin

- The pack layout (`Domain` → `Application` → `Infrastructure`/`Presentation`) is the four circles made concrete. See the DDD tactical patterns in [[ddd/ddd-domain-design]] and the port/adapter framing in [[hexagonal]].
- The Dependency Rule is the same law the pre-write layer check enforces: `Domain` imports nothing, `Application` imports only `Domain`.
- SOLID underpins every boundary crossing (DIP) and every stable inner circle (SRP, OCP). See [[principles]].
- When a boundary is missing, refactor toward it with [[refactoring-techniques]]; on untested legacy, characterize first with [[legacy/characterization-testing]].
