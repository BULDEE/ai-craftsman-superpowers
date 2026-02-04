# Microservices Patterns

## 10 Essential Patterns

### 1. Service Registry (Service Discovery)

**Problem:** Services need to find each other without hardcoded addresses.

**Solution:** Central registry where services register and discover others.

```
┌─────────────┐
│  Registry   │ ← Services register on startup
├─────────────┤
│ service-a   │
│ service-b   │
│ service-c   │
└─────────────┘
     ↑
     │ Lookup
     │
[Consumer Service]
```

**Implementation:**
- Consul, etcd, Eureka
- Kubernetes DNS (built-in)

**When to use:**
- Dynamic scaling (instances come and go)
- Multiple environments
- Container orchestration

---

### 2. Circuit Breaker

**Problem:** Cascading failures when a downstream service fails.

**Solution:** Stop calling failing service, fail fast, recover gradually.

```
States:
┌────────┐  failures > threshold  ┌────────┐  timeout  ┌─────────────┐
│ CLOSED │ ───────────────────→  │  OPEN  │ ───────→ │ HALF-OPEN   │
└────────┘                        └────────┘          └─────────────┘
    ↑                                                        │
    └───────────────── success ──────────────────────────────┘
```

**Configuration:**
```yaml
circuit_breaker:
  failure_threshold: 5      # Failures to open
  success_threshold: 2      # Successes to close
  timeout: 30s              # Time in open state
```

**When to use:**
- External API calls
- Database connections
- Any remote dependency

---

### 3. API Gateway

**Problem:** Clients need single entry point, cross-cutting concerns scattered.

**Solution:** Unified entry point handling routing, auth, rate limiting.

```
┌─────────────────────────────────────────────────────────┐
│                     API GATEWAY                          │
├─────────────────────────────────────────────────────────┤
│ • Authentication    • Rate limiting    • Routing        │
│ • SSL termination   • Request logging  • Load balancing │
└─────────────────────────────────────────────────────────┘
          │                │                │
          ↓                ↓                ↓
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ Service A│    │ Service B│    │ Service C│
    └──────────┘    └──────────┘    └──────────┘
```

**Implementation:**
- Kong, AWS API Gateway, Traefik
- Nginx, Envoy

---

### 4. Saga Pattern

**Problem:** Distributed transactions across services.

**Solution:** Sequence of local transactions with compensating actions.

**Choreography (event-driven):**
```
Order Created → Payment Processed → Inventory Reserved → Shipping Scheduled
     ↓                ↓                    ↓                    ↓
  (compensate)   Refund Payment    Release Inventory      Cancel Shipping
```

**Orchestration (central coordinator):**
```
┌────────────────────────────────────┐
│         SAGA ORCHESTRATOR          │
├────────────────────────────────────┤
│ 1. Create Order                    │
│ 2. Process Payment                 │
│ 3. Reserve Inventory               │
│ 4. Schedule Shipping               │
│ Compensation: Reverse in order     │
└────────────────────────────────────┘
```

**When to use:**
- Multi-service workflows
- Long-running processes
- When 2PC is not viable

---

### 5. Event Sourcing

**Problem:** Lost history, audit requirements, temporal queries.

**Solution:** Store all changes as immutable events.

```
Traditional:           Event Sourced:
┌──────────────┐       ┌──────────────────────────────────┐
│ Account      │       │ Events                            │
│ balance: 150 │       │ 1. AccountCreated(id, 0)         │
└──────────────┘       │ 2. MoneyDeposited(100)           │
                       │ 3. MoneyDeposited(100)           │
                       │ 4. MoneyWithdrawn(50)            │
                       │ → Current state: 150             │
                       └──────────────────────────────────┘
```

**Benefits:**
- Complete audit trail
- Temporal queries ("What was state at time T?")
- Event replay for debugging

---

### 6. CQRS (Command Query Responsibility Segregation)

**Problem:** Read and write have different optimization needs.

**Solution:** Separate models for commands (writes) and queries (reads).

```
         ┌─────────────────────────────────────────────┐
         │              APPLICATION                     │
         └─────────────────────────────────────────────┘
                │                        │
         Commands                    Queries
                ↓                        ↓
    ┌────────────────────┐    ┌────────────────────┐
    │    WRITE MODEL     │    │    READ MODEL      │
    │  (Normalized, DDD) │    │  (Denormalized)    │
    └────────────────────┘    └────────────────────┘
                │                        ↑
                └──── Events ────────────┘
```

**When to use:**
- Read/write ratio heavily skewed
- Complex domain logic (writes)
- Multiple read representations needed

---

### 7. Bulkhead Pattern

**Problem:** One slow consumer exhausts shared resources.

**Solution:** Isolate resources per consumer/feature.

```
┌─────────────────────────────────────────────────────────┐
│                    SERVICE                               │
├──────────────────┬──────────────────┬───────────────────┤
│  Thread Pool A   │  Thread Pool B   │  Thread Pool C    │
│  (10 threads)    │  (10 threads)    │  (10 threads)     │
│  Feature A       │  Feature B       │  External API     │
└──────────────────┴──────────────────┴───────────────────┘
```

**Implementation:**
- Separate thread pools
- Separate connection pools
- Separate instances

---

### 8. BFF (Backend for Frontend)

**Problem:** Different clients need different APIs (mobile vs web).

**Solution:** Dedicated backend per frontend type.

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Web App   │    │ Mobile App  │    │  Admin UI   │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │
       ↓                  ↓                  ↓
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Web BFF   │    │ Mobile BFF  │    │  Admin BFF  │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          ↓
              ┌────────────────────────┐
              │    Microservices       │
              └────────────────────────┘
```

---

### 9. Database per Service

**Problem:** Shared database couples services.

**Solution:** Each service owns its data completely.

```
┌────────────┐    ┌────────────┐    ┌────────────┐
│ Service A  │    │ Service B  │    │ Service C  │
└─────┬──────┘    └─────┬──────┘    └─────┬──────┘
      │                 │                 │
      ↓                 ↓                 ↓
┌────────────┐    ┌────────────┐    ┌────────────┐
│    DB A    │    │    DB B    │    │    DB C    │
│  (Postgres)│    │  (MongoDB) │    │   (Redis)  │
└────────────┘    └────────────┘    └────────────┘
```

**Rules:**
- No direct DB access between services
- Data sharing via APIs or events
- Eventual consistency accepted

---

### 10. Externalized Configuration

**Problem:** Config baked into deployments, environment-specific builds.

**Solution:** External config store, environment variables.

```
┌────────────────────────────────────────────┐
│           CONFIG SERVER                     │
│  ┌───────────┬───────────┬───────────┐     │
│  │    dev    │  staging  │   prod    │     │
│  └───────────┴───────────┴───────────┘     │
└────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        ↓           ↓           ↓
   [Service A] [Service B] [Service C]
```

**Implementation:**
- Consul KV, etcd
- AWS Parameter Store, HashiCorp Vault
- Kubernetes ConfigMaps/Secrets

## Pattern Selection Guide

| Problem | Pattern |
|---------|---------|
| Service discovery | Service Registry |
| Cascading failures | Circuit Breaker |
| Single entry point | API Gateway |
| Distributed transactions | Saga |
| Audit trail needed | Event Sourcing |
| Read/write optimization | CQRS |
| Resource isolation | Bulkhead |
| Client-specific APIs | BFF |
| Service coupling | Database per Service |
| Environment config | Externalized Configuration |
