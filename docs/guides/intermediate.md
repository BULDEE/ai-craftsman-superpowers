# Intermediate Guide

You've mastered the basics. Now let's go deeper into advanced patterns, pack-specific skills, and knowledge exploitation.

## What You'll Learn

- [x] Using stack-specific packs (Symfony, React)
- [x] Exploiting the knowledge base
- [x] Advanced skill combinations
- [x] Custom workflows

## Prerequisites

- Completed [Beginner Guide](./beginner.md)
- Familiarity with either PHP/Symfony or React/TypeScript

---

## Lesson 1: Stack-Specific Packs

### Symfony Pack

The Symfony pack provides DDD-focused scaffolding.

#### /craftsman:scaffold entity

```
> /craftsman:scaffold entity

Create a Product entity for an e-commerce bounded context.
Products have SKU, name, price, and stock quantity.
```

**Generated Structure:**
```
src/Domain/Product/
├── Product.php              # Entity (AggregateRoot)
├── ProductId.php            # Identity VO
├── Sku.php                  # Value Object
├── Money.php                # Value Object
├── Event/
│   ├── ProductCreated.php
│   └── StockUpdated.php
└── Exception/
    └── InsufficientStock.php

tests/Unit/Domain/Product/
├── ProductTest.php
├── SkuTest.php
└── MoneyTest.php
```

**Key Features:**
- Final classes with private constructors
- Static factory methods
- Value Objects for domain primitives
- Domain events for state changes
- Full test coverage

#### /craftsman:scaffold usecase

```
> /craftsman:scaffold usecase

Create a PlaceOrder use case.
It should validate stock and create an order.
```

**Generated Structure:**
```
src/Application/UseCase/PlaceOrder/
├── PlaceOrderCommand.php     # Input DTO
├── PlaceOrderHandler.php     # Use case implementation
└── PlaceOrderOutput.php      # Output DTO

tests/Unit/Application/UseCase/
└── PlaceOrderHandlerTest.php
```

### React Pack

#### /craftsman:scaffold component

```
> /craftsman:scaffold component

Create a ProductCard component.
Shows product image, name, price, and add to cart button.
```

**Generated Structure:**
```
src/components/ProductCard/
├── ProductCard.tsx           # Component
├── ProductCard.test.tsx      # Tests
├── ProductCard.stories.tsx   # Storybook (optional)
└── index.ts                  # Export
```

**Key Features:**
- TypeScript with strict types
- Branded types for domain primitives
- No `any` types
- Named exports only

#### /craftsman:scaffold hook

```
> /craftsman:scaffold hook

Create a useProduct hook.
Fetches product by ID with loading and error states.
```

**Generated:**
```typescript
// src/hooks/useProduct.ts
export function useProduct(productId: ProductId) {
  return useQuery({
    queryKey: ['product', productId],
    queryFn: () => fetchProduct(productId),
  });
}
```

---

## Lesson 2: Exploiting Knowledge

### Searching the Knowledge Base

With the RAG MCP server, you can query indexed content:

```
> What are the 6 MLOps principles?
```

Claude calls `search_knowledge()` and returns grounded answers from your indexed PDFs.

### Listing Available Knowledge

```
> List my knowledge sources
```

Returns all indexed documents with topics and chunk counts.

### Targeted Searches

```
> Search my knowledge base for "circuit breaker pattern"
```

Returns relevant chunks from microservices documentation.

### Knowledge-Informed Design

```
> /craftsman:design

Create an order processing system.
Use the saga pattern from my knowledge base.
```

Claude will:
1. Search knowledge for "saga pattern"
2. Apply the pattern to your specific case
3. Reference the source in recommendations

---

## Lesson 3: Advanced Skill Combinations

### Design → Test → Implement Cycle

```
# Step 1: Design
> /craftsman:design
Create a payment processing aggregate.
It handles payments with retry logic.

# Step 2: Test-first
> /craftsman:test
Write tests for the payment processing.
Include happy path, failures, and retries.

# Step 3: Implement
[Claude generates implementation to pass tests]

# Step 4: Review
> /craftsman:challenge
Review the payment processing implementation.
```

### Debug → Refactor Cycle

```
# Found a bug
> /craftsman:debug
Payments sometimes fail silently.
No error logged, but payment not recorded.

# After fixing, improve the code
> /craftsman:refactor
Refactor the payment error handling.
Make it clearer and more testable.
```

### Spec → Plan → Execute

```
# Write specification
> /craftsman:spec
Specify the order fulfillment workflow.
Include all states and transitions.

# Plan implementation
> /craftsman:plan
Plan the implementation of order fulfillment.
Break it into manageable tasks.

# Execute with tracking
[Follow the plan, marking tasks complete]
```

---

## Lesson 4: Custom Workflows

### Creating a Bounded Context

Full workflow for a new domain area:

```
# 1. Define the context
> /craftsman:design
Define a Shipping bounded context.
It handles delivery scheduling and tracking.

# 2. Identify aggregates
> /craftsman:design
What aggregates do we need for Shipping?
Consider: Shipment, Route, Carrier.

# 3. Create entities
> /craftsman:scaffold entity
Create the Shipment aggregate.

> /craftsman:scaffold entity
Create the Route entity.

# 4. Create use cases
> /craftsman:scaffold usecase
CreateShipment use case.

> /craftsman:scaffold usecase
UpdateShipmentStatus use case.

# 5. Review architecture
> /craftsman:challenge
Review the Shipping bounded context.
Check aggregate boundaries and dependencies.
```

### Feature Development Workflow

```
# 1. Understand requirement
> What does the user need?

# 2. Challenge assumptions
> /craftsman:challenge
Is this the right feature to build?
What are the alternatives?

# 3. Design solution
> /craftsman:design
[Design the feature]

# 4. Write specification
> /craftsman:spec
[Formalize the requirements]

# 5. Plan implementation
> /craftsman:plan
[Break into tasks]

# 6. Implement with TDD
> /craftsman:test + implement (TDD cycle)

# 7. Review before merge
> /craftsman:challenge
```

---

## Practice Exercises

### Exercise 1: Full Entity Lifecycle

```
# Create a Subscription entity (Symfony)
> /craftsman:scaffold entity
Subscription with: plan, status, billing cycle, next billing date.

# Write comprehensive tests
> /craftsman:test

# Create use cases
> /craftsman:scaffold usecase
CreateSubscription, CancelSubscription, RenewSubscription
```

### Exercise 2: React Feature

```
# Create subscription management UI (React)
> /craftsman:scaffold component
SubscriptionCard - shows plan, status, renewal date

> /craftsman:scaffold hook
useSubscription - manages subscription state

> /craftsman:scaffold component
SubscriptionForm - create/edit subscription
```

### Exercise 3: Knowledge-Driven Design

```
# Use CQRS pattern
> Search my knowledge for CQRS

> /craftsman:design
Apply CQRS to the subscription system.
Separate read and write models.
```

---

## Checklist: Ready for Advanced?

- [ ] Used stack-specific packs effectively
- [ ] Queried the knowledge base for patterns
- [ ] Combined multiple skills in workflows
- [ ] Created a complete bounded context
- [ ] Applied patterns from knowledge base

Continue to: [Advanced Guide](./advanced.md)
