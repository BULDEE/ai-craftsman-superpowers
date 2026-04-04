# Design Patterns Catalog

> "Each pattern describes a problem which occurs over and over again in our environment, and then describes the core of the solution to that problem." — Christopher Alexander

Reference: [refactoring.guru/design-patterns](https://refactoring.guru/design-patterns)

## Creational Patterns

Control object creation mechanisms — increase flexibility and reuse.

### Factory Method

Define an interface for creating objects, let subclasses decide which class to instantiate.

```python
# Abstract creator
class NotificationFactory(ABC):
    @abstractmethod
    def create_notification(self) -> Notification: ...

    def send(self, message: str) -> None:
        notification = self.create_notification()
        notification.deliver(message)

# Concrete creators
class EmailNotificationFactory(NotificationFactory):
    def create_notification(self) -> Notification:
        return EmailNotification()

class SlackNotificationFactory(NotificationFactory):
    def create_notification(self) -> Notification:
        return SlackNotification()
```

**When:** You don't know ahead of time the exact types of objects to create.

### Abstract Factory

Create families of related objects without specifying concrete classes.

**When:** Code needs to work with various families of related products (e.g., UI themes: DarkButton + DarkCheckbox).

### Builder

Construct complex objects step by step. Same construction process, different representations.

```python
class QueryBuilder:
    def __init__(self):
        self._table = ""
        self._conditions = []
        self._order = ""

    def from_table(self, table: str) -> QueryBuilder:
        self._table = table
        return self

    def where(self, condition: str) -> QueryBuilder:
        self._conditions.append(condition)
        return self

    def order_by(self, field: str) -> QueryBuilder:
        self._order = field
        return self

    def build(self) -> str:
        query = f"SELECT * FROM {self._table}"
        if self._conditions:
            query += " WHERE " + " AND ".join(self._conditions)
        if self._order:
            query += f" ORDER BY {self._order}"
        return query
```

**When:** Object construction involves many optional parameters or step-by-step assembly.

### Singleton

Ensure a class has only one instance with a global access point.

**When:** Exactly one instance needed (database connection, config). Use sparingly — often an anti-pattern.

### Prototype

Clone existing objects without coupling to their concrete classes.

**When:** You need copies of objects and don't care about their concrete classes.

## Structural Patterns

Assemble objects and classes into larger structures while keeping them flexible.

### Adapter

Convert the interface of a class into another interface clients expect.

```python
class LegacyPaymentGateway:
    def make_payment(self, amount_cents: int, card_number: str) -> bool: ...

class PaymentGatewayAdapter:
    """Adapts legacy gateway to our domain interface."""
    def __init__(self, legacy_gateway: LegacyPaymentGateway):
        self._gateway = legacy_gateway

    def charge(self, money: Money, payment_method: PaymentMethod) -> PaymentResult:
        success = self._gateway.make_payment(
            money.amount_in_cents,
            payment_method.card_number
        )
        return PaymentResult(success=success)
```

**When:** You want to use an existing class but its interface doesn't match what you need.

### Decorator

Attach additional responsibilities to an object dynamically.

```python
class LoggingRepository:
    """Adds logging to any repository without modifying it."""
    def __init__(self, inner: UserRepository, logger: Logger):
        self._inner = inner
        self._logger = logger

    def find_by_id(self, user_id: UserId) -> User | None:
        self._logger.debug(f"Finding user {user_id}")
        result = self._inner.find_by_id(user_id)
        if result is None:
            self._logger.warning(f"User {user_id} not found")
        return result
```

**When:** You need to add behavior to objects without affecting others of the same class.

### Facade

Provide a simplified interface to a complex subsystem.

```python
class OrderFacade:
    """Simplifies the complex order processing workflow."""
    def __init__(self, inventory: Inventory, payment: PaymentService, shipping: ShippingService):
        self._inventory = inventory
        self._payment = payment
        self._shipping = shipping

    def place_order(self, order: Order) -> OrderConfirmation:
        self._inventory.reserve(order.items)
        payment_result = self._payment.charge(order.total, order.payment_method)
        shipping_label = self._shipping.create_label(order.shipping_address)
        return OrderConfirmation(payment=payment_result, tracking=shipping_label)
```

**When:** You need a simple interface to a complex subsystem.

### Composite

Compose objects into tree structures — treat individual objects and compositions uniformly.

**When:** You need to represent part-whole hierarchies (file systems, UI components, organizational charts).

### Proxy

Provide a substitute or placeholder for another object to control access.

**When:** Lazy initialization, access control, logging, caching.

### Bridge

Split a large class into two separate hierarchies (abstraction and implementation) that can develop independently.

**When:** You want to extend a class in several orthogonal dimensions.

### Flyweight

Share common state between multiple objects to reduce memory usage.

**When:** Many similar objects consuming too much RAM.

## Behavioral Patterns

Handle communication between objects and responsibility assignment.

### Strategy

Define a family of algorithms, encapsulate each one, make them interchangeable.

```python
class PricingStrategy(Protocol):
    def calculate(self, base_price: Money) -> Money: ...

class RegularPricing:
    def calculate(self, base_price: Money) -> Money:
        return base_price

class PremiumPricing:
    def calculate(self, base_price: Money) -> Money:
        discount = base_price.amount * 20 // 100
        return Money(amount=base_price.amount - discount)

class Order:
    def __init__(self, pricing: PricingStrategy):
        self._pricing = pricing

    def total(self, base: Money) -> Money:
        return self._pricing.calculate(base)
```

**When:** You want to use different variants of an algorithm at runtime.

### Observer

Define a subscription mechanism to notify objects about events.

```python
class EventDispatcher:
    def __init__(self):
        self._listeners: dict[str, list[Callable]] = {}

    def subscribe(self, event_type: str, listener: Callable) -> None:
        self._listeners.setdefault(event_type, []).append(listener)

    def dispatch(self, event_type: str, data: Any) -> None:
        for listener in self._listeners.get(event_type, []):
            listener(data)
```

**When:** Changes in one object need to notify others without tight coupling.

### Command

Encapsulate a request as an object — parameterize, queue, log, and undo operations.

**When:** You need to queue operations, schedule execution, or support undo.

### State

Let an object alter its behavior when its internal state changes.

```python
class OrderState(ABC):
    @abstractmethod
    def confirm(self, order: Order) -> None: ...
    @abstractmethod
    def ship(self, order: Order) -> None: ...
    @abstractmethod
    def cancel(self, order: Order) -> None: ...

class PendingState(OrderState):
    def confirm(self, order: Order) -> None:
        order.transition_to(ConfirmedState())
    def ship(self, order: Order) -> None:
        raise InvalidTransitionError("Cannot ship a pending order")
    def cancel(self, order: Order) -> None:
        order.transition_to(CancelledState())
```

**When:** An object has many conditional behaviors tied to its state.

### Template Method

Define the skeleton of an algorithm in a base class, let subclasses override specific steps.

**When:** Several classes contain similar algorithms with minor differences.

### Chain of Responsibility

Pass requests along a chain of handlers until one handles it.

**When:** You need to process a request through multiple handlers without coupling sender to receiver.

### Iterator

Traverse collection elements without exposing underlying representation.

**When:** You need to traverse complex data structures (trees, graphs) with a uniform interface.

### Mediator

Reduce chaotic dependencies between objects — force them to communicate via a mediator.

**When:** Classes are too tightly coupled through many direct relationships.

### Memento

Save and restore previous state without revealing implementation details.

**When:** You need undo/redo or snapshots.

### Visitor

Separate algorithms from the objects on which they operate.

**When:** You need to perform operations on elements of a complex object structure and want to avoid polluting their classes.

## Pattern Selection Guide

| Problem | Pattern |
|---------|---------|
| Need to create objects flexibly | Factory Method, Abstract Factory |
| Object construction is complex | Builder |
| Need to use incompatible interface | Adapter |
| Want to add behavior dynamically | Decorator |
| Complex subsystem needs simple API | Facade |
| Algorithm should be swappable | Strategy |
| Object behavior depends on state | State |
| Need to decouple event producer/consumer | Observer |
| Need to undo/redo | Command + Memento |
| Processing pipeline | Chain of Responsibility |

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| God Object | One class does everything | Extract classes by responsibility |
| Spaghetti Code | No clear structure | Extract Method, Move Method |
| Golden Hammer | One pattern for everything | Choose pattern by problem |
| Premature Optimization | Optimizing before profiling | YAGNI — measure first |
| Cargo Cult | Patterns without understanding | Understand the WHY |
