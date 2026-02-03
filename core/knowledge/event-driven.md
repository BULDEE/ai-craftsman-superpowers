# Event-Driven Architecture

## Core Insight

Event-Driven Architecture (EDA) is about **design**, not tools. Kafka and RabbitMQ are implementations, not architecture.

## The 4 Event Patterns (Martin Fowler)

### 1. Event Notification

**Purpose:** Signal that something happened. No expectation of response.

```
┌──────────────┐    OrderPlaced    ┌──────────────┐
│ Order Service│ ───────────────→  │ Email Service│
└──────────────┘    {orderId: 123} └──────────────┘
                          │
                          ↓
                    ┌──────────────┐
                    │Audit Service │
                    └──────────────┘
```

**Event Content:** Minimal - just enough to identify what happened.

```json
{
  "type": "OrderPlaced",
  "orderId": "123",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Characteristics:**
- Fire and forget
- Loose coupling (publisher doesn't know consumers)
- Consumers may need to call back for details

**When to use:**
- Triggering side effects
- Cross-cutting concerns (audit, notifications)
- When consumers rarely need full data

---

### 2. Event-Carried State Transfer

**Purpose:** Share data via events to avoid synchronous calls.

```
┌──────────────┐    CustomerUpdated    ┌──────────────┐
│ Customer Svc │ ─────────────────────→│ Order Service│
└──────────────┘    {id, name, email,  └──────────────┘
                     address, ...}            │
                                              ↓
                                      [Local Customer Cache]
```

**Event Content:** Full entity state.

```json
{
  "type": "CustomerUpdated",
  "customerId": "456",
  "data": {
    "name": "John Doe",
    "email": "john@example.com",
    "address": {
      "street": "123 Main St",
      "city": "Paris"
    }
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Characteristics:**
- Consumers maintain local copy
- No need for synchronous calls
- Eventual consistency

**When to use:**
- High read frequency from other services
- Performance-critical queries
- Reducing inter-service calls

---

### 3. Event Sourcing

**Purpose:** Store state as sequence of events, derive current state.

```
┌────────────────────────────────────────────────────────┐
│                    EVENT STORE                          │
├────────────────────────────────────────────────────────┤
│ 1. AccountOpened(id: A1, owner: John)                  │
│ 2. MoneyDeposited(id: A1, amount: 1000)                │
│ 3. MoneyWithdrawn(id: A1, amount: 200)                 │
│ 4. MoneyDeposited(id: A1, amount: 500)                 │
├────────────────────────────────────────────────────────┤
│ Current State: balance = 1000 - 200 + 500 = 1300       │
└────────────────────────────────────────────────────────┘
```

**Characteristics:**
- Complete history (audit trail)
- Temporal queries possible
- Rebuild state by replaying events
- Append-only store

**When to use:**
- Audit requirements
- Complex domain with business rules
- Need to answer "what was state at time T?"
- Debugging production issues

**Anti-patterns to avoid:**
- Modifying past events
- Too fine-grained events
- No snapshots for long histories

---

### 4. CQRS (Command Query Responsibility Segregation)

**Purpose:** Separate write model (commands) from read model (queries).

```
         ┌───────────────────────────────────────────────┐
         │                  APPLICATION                   │
         └───────────────────────────────────────────────┘
                 │                          │
          Commands                      Queries
          (Create, Update, Delete)      (Get, List, Search)
                 ↓                          ↓
    ┌─────────────────────┐    ┌─────────────────────────┐
    │    WRITE MODEL      │    │      READ MODEL         │
    │  ┌───────────────┐  │    │  ┌─────────────────┐   │
    │  │ Domain Logic  │  │    │  │  Denormalized   │   │
    │  │ Aggregates    │  │    │  │  Projections    │   │
    │  │ Invariants    │  │    │  │  Query-optimized│   │
    │  └───────────────┘  │    │  └─────────────────┘   │
    └──────────┬──────────┘    └───────────────────────┘
               │                          ↑
               │        Events            │
               └──────────────────────────┘
```

**Characteristics:**
- Write model: complex domain logic, normalized
- Read model: simple queries, denormalized
- Sync via events (eventual consistency)
- Can have multiple read models

**When to use:**
- Read/write ratio heavily skewed (90% reads)
- Complex domain requiring rich model
- Different optimization needs for read/write
- Multiple representations of same data

## Pattern Comparison

| Pattern | Data in Event | State Storage | Consistency |
|---------|--------------|---------------|-------------|
| Notification | Minimal (IDs) | Service owns data | Immediate |
| State Transfer | Full snapshot | Consumer cache | Eventual |
| Event Sourcing | State change | Event store | Append-only |
| CQRS | Domain events | Separate models | Eventual |

## Event Design Principles

### 1. Events are Facts
```
Good: OrderPlaced, PaymentReceived, ItemShipped
Bad:  CreateOrder, ProcessPayment, ShipItem (commands!)
```

### 2. Past Tense Naming
```
Good: UserRegistered, AccountClosed, PasswordChanged
Bad:  UserRegistration, CloseAccount, ChangePassword
```

### 3. Include Business Context
```json
{
  "type": "OrderCancelled",
  "orderId": "123",
  "reason": "customer_request",
  "cancelledBy": "user:456",
  "refundAmount": 99.99,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### 4. Versioning Strategy
```json
{
  "type": "OrderPlaced",
  "version": "2.0",
  "data": { ... }
}
```

## Common Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Event as command | Coupling, not fire-and-forget | Use past tense, no expectations |
| Fat events | Unnecessary data transfer | Only include what's needed |
| Event chains | Hidden dependencies | Document flows, use saga |
| No schema | Breaking changes | Version events, schema registry |
| Sync over async | Defeats purpose of EDA | Accept eventual consistency |

## When NOT to Use Events

- Simple CRUD with no side effects
- Strong consistency required
- Simple request-response sufficient
- Small monolith with single database
