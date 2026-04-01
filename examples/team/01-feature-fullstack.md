# Example: Full-Stack Checkout Feature with Team Workflow

This example walks through implementing a checkout system with payment processing using the `/craftsman:team` command.

## Context: User Story

**Feature:** Implement a complete checkout flow for an e-commerce platform with payment processing via Stripe.

**Requirements:**
- Users can review items in cart
- Enter shipping information
- Select payment method (credit card)
- Process payment securely
- Receive confirmation email
- Handle payment failures gracefully

**Scope:** Backend API + React frontend + security review

**Constraints:**
- Must comply with PCI-DSS (payment data security)
- Payment processing must be async (webhooks)
- Cart data must be isolated per user session

---

## Step 1: Team Setup

```bash
/craftsman:team create
```

**Claude's response:**

```
How do you want to build your team?

1. code-review     — Architecture + security + domain quality review
2. feature         — Backend + frontend + post-implementation review
3. security-audit  — Penetration testing + architecture security
4. custom          — Interactive questionnaire

Your choice: 2 (feature)
```

**Agent selection:** Backend + Frontend + Review

---

```
Template: feature
Agents: 
  - Backend Engineer (Sonnet)
  - Frontend Engineer (Sonnet)
  - Senior Reviewer (Sonnet)

Workflow: Parallel domain work, then sequential integration

Use this template as-is, or customize? [as-is/customize]: customize
```

**Customization:**

```
Q1. Add payment/security specialist?
A: Yes

Q2. Isolation strategy?
A: worktree (each agent isolated)
```

**Team created:**

```yaml
name: checkout-feature
purpose: Implement checkout with Stripe payment processing
workflow:
  type: parallel-then-review
  steps:
    - phase: domain-modeling
      agents: [backend]
      tasks:
        - task: Design Payment & Order aggregates
          id: TASK-001
        - task: Specify payment API endpoints
          id: TASK-002

    - phase: implementation
      agents: [backend, frontend]
      parallel: true
      tasks:
        - task: Scaffold backend domain layer
          id: TASK-003
          depends: [TASK-001]
        - task: Scaffold backend use cases
          id: TASK-004
          depends: [TASK-001, TASK-002]
        - task: Scaffold React checkout form
          id: TASK-005
          depends: [TASK-002]
        - task: Implement Cart validation
          id: TASK-006
          depends: [TASK-003]
        - task: Implement Stripe integration
          id: TASK-007
          depends: [TASK-004]
        - task: Build checkout UI
          id: TASK-008
          depends: [TASK-005]
        - task: Add error handling (payment failures)
          id: TASK-009
          depends: [TASK-007]

    - phase: security-review
      agents: [security]
      tasks:
        - task: PCI-DSS compliance audit
          id: TASK-010
          depends: [TASK-007]
        - task: Review payment data handling
          id: TASK-010a
          depends: [TASK-007]
        - task: Test fraud detection
          id: TASK-011
          depends: [TASK-007]

    - phase: integration
      agents: [reviewer]
      tasks:
        - task: Integration testing
          id: TASK-012
          depends: [TASK-006, TASK-008, TASK-009]
        - task: End-to-end payment flow
          id: TASK-013
          depends: [TASK-012]
        - task: Performance & load testing
          id: TASK-014
          depends: [TASK-012]
```

---

## Step 2: Domain Modeling (Sequential Foundation)

### TASK-001: Design Payment & Order Aggregates

**Agent:** Backend Engineer

**Input:** 
```
Design the domain model for payment processing.

Requirements:
- Order aggregate with line items (read from cart)
- Payment aggregate with status lifecycle (pending → processing → completed/failed)
- Event: OrderCheckoutInitiated
- Event: PaymentProcessed
- Event: PaymentFailed

Constraints:
- PCI-DSS: Do not store raw card data
- Idempotency: Handle duplicate payment requests
- Atomicity: Order + Payment must be transactional
```

**Output:**

```markdown
## Domain Model: Payment & Order

### Order Aggregate
```php
final class Order {
    private OrderId $id;
    private UserId $userId;
    private Cart $cart;           // readonly (from session)
    private ShippingAddress $address;
    private OrderStatus $status;  // new → confirmed → shipped → delivered
    private Money $totalAmount;
    private Collection $events;   // OrderCreated, OrderConfirmed, OrderShipped
    
    private function __construct(OrderId $id, ...) {}
    
    public static function createFromCart(OrderId $id, UserId $userId, Cart $cart, ShippingAddress $address): self
    public function confirm(Payment $payment): void  // Order → confirmed after payment
    public function ship(): void
}

enum OrderStatus: string {
    case Pending = 'pending';
    case Confirmed = 'confirmed';
    case Shipped = 'shipped';
}
```

### Payment Aggregate
```php
final class Payment {
    private PaymentId $id;
    private OrderId $orderId;
    private Money $amount;
    private PaymentMethod $method;      // CreditCard value object (token, not raw data)
    private PaymentStatus $status;      // pending → processing → succeeded/failed
    private ?string $stripePaymentIntentId;  // Stripe intent ID (idempotency)
    private Collection $events;         // PaymentInitiated, PaymentProcessed, PaymentFailed
    
    private function __construct(...) {}
    
    public static function initiate(PaymentId $id, OrderId $orderId, Money $amount, CreditCard $token): self
    public function processPaymentResult(StripePaymentResult $result): void
}

enum PaymentStatus: string {
    case Pending = 'pending';
    case Processing = 'processing';
    case Succeeded = 'succeeded';
    case Failed = 'failed';
}
```

### Value Objects
```php
final class CreditCard {
    // Token only, never raw card data
    private string $stripeToken;  // Provided by Stripe.js on frontend
    
    public static function fromStripeToken(string $token): self
}

final class ShippingAddress {
    private string $street;
    private string $city;
    private string $state;
    private string $zip;
    private string $country;
}
```

### Domain Events
```php
final class OrderCheckoutInitiated extends DomainEvent {
    public function __construct(
        readonly OrderId $orderId,
        readonly Money $amount,
    ) {}
}

final class PaymentProcessingStarted extends DomainEvent {
    public function __construct(
        readonly PaymentId $paymentId,
        readonly OrderId $orderId,
    ) {}
}

final class PaymentSucceeded extends DomainEvent {
    public function __construct(
        readonly PaymentId $paymentId,
        readonly OrderId $orderId,
    ) {}
}

final class PaymentFailed extends DomainEvent {
    public function __construct(
        readonly PaymentId $paymentId,
        readonly OrderId $orderId,
        readonly string $reason,
    ) {}
}
```

### Repository Interfaces
```php
interface OrderRepositoryInterface {
    public function save(Order $order): void;
    public function findById(OrderId $id): ?Order;
}

interface PaymentRepositoryInterface {
    public function save(Payment $payment): void;
    public function findById(PaymentId $id): ?Payment;
    public function findByStripeIntentId(string $intentId): ?Payment;  // Idempotency
}
```

## Design Decisions

1. **Separate aggregates:** Order and Payment are distinct because they have different lifecycles (order → shipped, payment → succeeded/failed)

2. **CreditCard value object:** Only stores Stripe token, never raw card data. PCI-DSS compliance requirement.

3. **StripePaymentIntentId:** Used for idempotency. If webhook arrives twice, we recognize it via intent ID.

4. **Events:** Both aggregates emit events for async processing (email, order confirmation, etc.)

5. **Status enums:** Explicit state machines prevent invalid transitions.
```

---

### TASK-002: Specify Payment API Endpoints

**Agent:** Backend Engineer

**Input:**
```
Design API endpoints for checkout process.

Endpoints needed:
1. POST /api/checkout/validate   — Validate cart & get checkout session
2. POST /api/checkout/confirm    — Confirm order + create payment
3. POST /api/checkout/webhook    — Stripe webhook (async payment result)
4. GET /api/checkout/:orderId    — Get order/payment status

Requirements:
- Request/response schemas
- Error scenarios
- Authentication (user context)
```

**Output:**

```markdown
## API Specification: Checkout

### 1. Validate Checkout
**Endpoint:** POST /api/checkout/validate

**Request:**
```json
{
  "cartId": "uuid",
  "shippingAddressId": "uuid"
}
```

**Response (200):**
```json
{
  "checkoutSessionId": "uuid",
  "totalAmount": 99.99,
  "currency": "USD",
  "shippingAddress": {...},
  "lineItems": [...],
  "estimatedDelivery": "2026-04-05"
}
```

**Errors:**
- 400: Cart is empty
- 400: Cart items out of stock
- 400: Shipping address invalid
- 401: Not authenticated

### 2. Confirm Order & Create Payment
**Endpoint:** POST /api/checkout/confirm

**Request:**
```json
{
  "checkoutSessionId": "uuid",
  "stripePaymentMethodId": "pm_xxxxx",  // From Stripe.js on frontend
  "idempotencyKey": "uuid"  // Client-generated for safety
}
```

**Response (200):**
```json
{
  "orderId": "uuid",
  "paymentId": "uuid",
  "status": "processing",
  "clientSecret": "pi_xxxxx_secret_yyyyy"  // For SCA (3D Secure) if needed
}
```

**Errors:**
- 400: Invalid payment method
- 400: Insufficient funds (from Stripe)
- 400: Checkout session expired
- 409: Duplicate idempotency key (retry with same orderId)
- 401: Not authenticated

### 3. Stripe Webhook
**Endpoint:** POST /api/checkout/webhook

**Trigger:** Stripe sends payment status updates

**Payload:**
```json
{
  "id": "evt_xxxxx",
  "type": "payment_intent.succeeded",
  "data": {
    "object": {
      "id": "pi_xxxxx",
      "status": "succeeded",
      "amount": 9999,
      "metadata": {
        "orderId": "uuid"
      }
    }
  }
}
```

**Expected response (200):**
```json
{"received": true}
```

**Actions:**
- Validate webhook signature (Stripe shared secret)
- Find Payment by stripePaymentIntentId
- Update Payment status → succeeded
- Emit PaymentSucceeded event (async handler → send confirmation email)
- Prevent duplicate processing (idempotency)

### 4. Get Checkout Status
**Endpoint:** GET /api/checkout/{orderId}

**Response (200):**
```json
{
  "orderId": "uuid",
  "status": "confirmed",  // pending | confirmed | shipped
  "paymentStatus": "succeeded",  // pending | processing | succeeded | failed
  "totalAmount": 99.99,
  "createdAt": "2026-03-30T10:00:00Z",
  "estimatedDelivery": "2026-04-05"
}
```

**Errors:**
- 404: Order not found
- 401: Not authenticated (not order owner)

## API Decisions

1. **Idempotency key:** Client provides UUID to handle retries safely. Same key = same response.

2. **Stripe webhook:** Async notification when payment completes. More reliable than polling.

3. **Client secret:** Returned for 3D Secure (SCA) verification on frontend.

4. **Metadata in intent:** Stripe intent includes orderId in metadata for webhook lookup.

5. **No card data in requests:** Frontend handles card → Stripe token conversion. API only sees token.
```

---

## Step 3: Parallel Implementation

Agents now work on independent phases in parallel.

### Phase 1: Backend Domain Layer

**Agent:** Backend Engineer

**TASK-003: Scaffold Domain Layer**

Input: Design document from TASK-001

Output:
```
src/Domain/
├── Aggregate/
│   ├── Order/
│   │   └── Order.php (skeleton)
│   └── Payment/
│       └── Payment.php (skeleton)
├── ValueObject/
│   ├── OrderId.php
│   ├── PaymentId.php
│   ├── CreditCard.php
│   ├── ShippingAddress.php
│   └── Money.php
├── Event/
│   ├── OrderCheckoutInitiated.php
│   ├── PaymentProcessingStarted.php
│   ├── PaymentSucceeded.php
│   └── PaymentFailed.php
└── Repository/
    ├── OrderRepositoryInterface.php
    └── PaymentRepositoryInterface.php
```

**TASK-004: Scaffold Use Cases**

Input: Design + API spec

Output:
```
src/Application/
├── UseCase/
│   ├── ValidateCheckout/
│   │   ├── ValidateCheckoutRequest.php
│   │   ├── ValidateCheckoutResponse.php
│   │   └── ValidateCheckoutUseCase.php (skeleton)
│   ├── ConfirmOrder/
│   │   ├── ConfirmOrderRequest.php
│   │   ├── ConfirmOrderResponse.php
│   │   └── ConfirmOrderUseCase.php (skeleton)
│   └── ProcessPaymentWebhook/
│       ├── ProcessPaymentWebhookRequest.php
│       └── ProcessPaymentWebhookUseCase.php (skeleton)
└── Port/
    ├── StripePaymentPort.php (interface)
    └── EmailPort.php (interface)
```

**TASK-006: Implement Cart Validation**

Input: Order aggregate, CartService

Output:
```php
// src/Application/UseCase/ValidateCheckout/ValidateCheckoutUseCase.php

final class ValidateCheckoutUseCase {
    public function __construct(
        private readonly CartRepositoryInterface $cartRepository,
        private readonly ShippingAddressRepositoryInterface $addressRepository,
        private readonly InventoryPort $inventory,
    ) {}
    
    public function execute(ValidateCheckoutRequest $request): ValidateCheckoutResponse {
        $cart = $this->cartRepository->findById($request->cartId);
        if (!$cart || $cart->isEmpty()) {
            throw new EmptyCartException('Cannot checkout with empty cart');
        }
        
        // Check inventory
        foreach ($cart->items() as $item) {
            $available = $this->inventory->checkAvailability(
                $item->productId(),
                $item->quantity()
            );
            if (!$available) {
                throw new OutOfStockException(sprintf(
                    '%s out of stock',
                    $item->productName()
                ));
            }
        }
        
        $address = $this->addressRepository->findById($request->shippingAddressId);
        if (!$address) {
            throw new InvalidAddressException('Invalid shipping address');
        }
        
        return new ValidateCheckoutResponse(
            checkoutSessionId: CheckoutSessionId::generate(),
            totalAmount: $cart->total(),
            currency: 'USD',
            shippingAddress: $address,
            lineItems: $cart->items(),
            estimatedDelivery: $this->calculateDeliveryDate(),
        );
    }
}
```

**TASK-007: Implement Stripe Integration**

Input: Payment aggregate, API spec

Output:
```php
// src/Infrastructure/Stripe/StripePaymentGateway.php

final class StripePaymentGateway implements StripePaymentPort {
    public function __construct(private readonly StripeClient $client) {}
    
    public function createPaymentIntent(
        OrderId $orderId,
        Money $amount,
        string $idempotencyKey,
    ): StripePaymentResult {
        try {
            $intent = $this->client->paymentIntents->create([
                'amount' => $amount->amountInCents(),
                'currency' => strtolower($amount->currency()),
                'metadata' => ['orderId' => $orderId->value()],
                'idempotency_key' => $idempotencyKey,
            ]);
            
            return StripePaymentResult::success(
                stripeIntentId: $intent->id,
                clientSecret: $intent->client_secret,
                status: $intent->status,
            );
        } catch (StripeException $e) {
            return StripePaymentResult::failure(
                reason: $e->getMessage(),
                code: $e->getStripeCode(),
            );
        }
    }
    
    public function confirmPayment(
        string $paymentIntentId,
        string $paymentMethodId,
    ): StripePaymentResult {
        try {
            $intent = $this->client->paymentIntents->confirm(
                $paymentIntentId,
                ['payment_method' => $paymentMethodId]
            );
            
            return StripePaymentResult::fromIntent($intent);
        } catch (StripeException $e) {
            return StripePaymentResult::failure($e->getMessage(), $e->getStripeCode());
        }
    }
}

// src/Infrastructure/Stripe/StripeWebhookHandler.php

final class StripeWebhookHandler {
    public function __construct(
        private readonly PaymentRepositoryInterface $payments,
        private readonly EventBusInterface $eventBus,
        private readonly string $webhookSecret,
    ) {}
    
    public function handleWebhook(string $payload, string $signature): void {
        // Validate signature
        $event = $this->validateAndParseWebhook($payload, $signature);
        
        match ($event->type) {
            'payment_intent.succeeded' => $this->handlePaymentSucceeded($event),
            'payment_intent.payment_failed' => $this->handlePaymentFailed($event),
            default => null,
        };
    }
    
    private function handlePaymentSucceeded(StripeEvent $event): void {
        $stripeIntentId = $event->data['object']['id'];
        $payment = $this->payments->findByStripeIntentId($stripeIntentId);
        
        if ($payment && $payment->status() === PaymentStatus::Processing) {
            $payment->markSucceeded();
            $this->payments->save($payment);
            $this->eventBus->publishAll($payment->popEvents());
        }
    }
}
```

---

### Phase 2: Frontend Implementation

**Agent:** Frontend Engineer

**TASK-005: Scaffold React Checkout Form**

Input: API spec (TASK-002)

Output:
```typescript
// src/components/Checkout/CheckoutFlow.tsx

export const CheckoutFlow = ({ cartId }: { cartId: string }) => {
  const [step, setStep] = useState<'validate' | 'confirm' | 'payment' | 'success'>('validate');
  const [checkoutSession, setCheckoutSession] = useState<CheckoutSession | null>(null);
  
  return (
    <>
      {step === 'validate' && (
        <ValidateCheckoutStep
          cartId={cartId}
          onValidated={(session) => {
            setCheckoutSession(session);
            setStep('confirm');
          }}
        />
      )}
      {step === 'confirm' && checkoutSession && (
        <ConfirmOrderStep
          checkoutSession={checkoutSession}
          onConfirmed={() => setStep('payment')}
        />
      )}
      {step === 'payment' && checkoutSession && (
        <PaymentStep
          checkoutSession={checkoutSession}
          onPaymentSuccess={() => setStep('success')}
        />
      )}
      {step === 'success' && <SuccessMessage />}
    </>
  );
};

// src/components/Checkout/ValidateCheckoutStep.tsx

export const ValidateCheckoutStep = ({
  cartId,
  onValidated,
}: {
  cartId: string;
  onValidated: (session: CheckoutSession) => void;
}) => {
  const { data: session, isPending, error } = useQuery(
    ['checkout', cartId],
    () => api.post('/checkout/validate', { cartId, shippingAddressId: ... }),
  );
  
  // Form for shipping address selection, order review, etc.
};

// src/components/Checkout/PaymentStep.tsx

export const PaymentStep = ({
  checkoutSession,
  onPaymentSuccess,
}: {
  checkoutSession: CheckoutSession;
  onPaymentSuccess: () => void;
}) => {
  const stripe = useStripe();
  const elements = useElements();
  
  const handlePayment = async () => {
    const { paymentMethod } = await stripe.createPaymentMethod({
      type: 'card',
      card: elements.getElement(CardElement),
    });
    
    // Send to backend (never raw card data)
    const { orderId, clientSecret } = await api.post('/checkout/confirm', {
      checkoutSessionId: checkoutSession.id,
      stripePaymentMethodId: paymentMethod.id,
      idempotencyKey: generateUUID(),
    });
    
    // Handle 3D Secure if needed
    const result = await stripe.confirmCardPayment(clientSecret);
    if (result.paymentIntent.status === 'succeeded') {
      onPaymentSuccess();
    }
  };
  
  return <CardElement onBlur={handlePayment} />;
};
```

**TASK-008: Build Checkout UI**

Input: Checkout form components

Output: Complete React UI with:
- Cart review table
- Shipping address selector/editor
- Payment method selector
- Error messages for each step
- Loading states
- Order summary

---

### Phase 3: Security Review (Parallel)

**Agent:** Security Specialist

**TASK-010: PCI-DSS Compliance Audit**

Output:
```markdown
## Security Audit: Payment Processing

### PCI-DSS Compliance Checklist

#### Requirement 1: Network Architecture
- [ ] Payment processing isolated from main application
- [x] Stripe handles payment processing (3rd party)
- [x] No direct card data touches our servers

#### Requirement 3: Protect Stored Card Data
- [x] We do NOT store card data (Stripe token only)
- [x] StripeToken is cryptographically safe to store

#### Requirement 4: Encryption in Transit
- [x] All API calls use HTTPS (enforced)
- [x] TLS 1.2+ configured on payment endpoints

#### Requirement 6: Secure Coding Practices
- [x] No card data in logs
- [x] No card data in error messages
- [x] Idempotency key prevents duplicate charges
- [x] Webhook signature validation

#### Recommendation 1: Secret Management
- [ ] Stripe API keys in environment variables (not config)
- [ ] Webhook secret in secure vault (not .env.local)
- [ ] Rotate secrets quarterly

#### Recommendation 2: Monitoring
- [ ] Log all payment API calls (for audit)
- [ ] Alert on failed payment attempts (fraud detection)
- [ ] Monitor webhook delays (payment processing issues)

### Risk Assessment

**HIGH:** Stripe API key exposed in code
→ Action: Move to .env (or secrets manager)

**MEDIUM:** Error messages expose Stripe intent ID
→ Action: Log intent ID, return generic error to client

**LOW:** No rate limiting on webhook endpoint
→ Action: Add rate limiter (nice-to-have)

### Conclusion
Payment processing is secure if recommendations are implemented.
```

---

## Step 4: Integration & Verification

### TASK-012: Integration Testing

**Agent:** Backend Engineer

Output:
```php
// tests/Integration/Checkout/CheckoutFlowTest.php

final class CheckoutFlowTest extends IntegrationTestCase {
    public function testCompleteCheckoutFlow(): void {
        // Setup
        $user = $this->createUser();
        $cart = $this->createCart($user, [
            $this->createProduct('Laptop', 1200.00, 1),
            $this->createProduct('Mouse', 25.00, 2),
        ]);
        
        // Step 1: Validate Checkout
        $validateResponse = $this->api->post('/checkout/validate', [
            'cartId' => $cart->id(),
            'shippingAddressId' => $user->defaultAddress()->id(),
        ], $user);
        
        $this->assertEquals(200, $validateResponse->status());
        $this->assertEquals(1250.00, $validateResponse->json('totalAmount'));
        $checkoutSessionId = $validateResponse->json('checkoutSessionId');
        
        // Step 2: Confirm Order
        $confirmResponse = $this->api->post('/checkout/confirm', [
            'checkoutSessionId' => $checkoutSessionId,
            'stripePaymentMethodId' => 'pm_test_success',
            'idempotencyKey' => Uuid::v4()->toString(),
        ], $user);
        
        $this->assertEquals(200, $confirmResponse->status());
        $orderId = $confirmResponse->json('orderId');
        
        // Step 3: Simulate Stripe Webhook
        $this->mockStripeWebhook($confirmResponse->json('stripePaymentIntentId'), 'succeeded');
        $this->assertPaymentProcessed($orderId);
        
        // Verify
        $order = $this->orderRepository->findById(OrderId::fromString($orderId));
        $this->assertEquals(OrderStatus::Confirmed, $order->status());
    }
}
```

### TASK-013: End-to-End Payment Flow

Integration test with real Stripe test API

### TASK-014: Performance Testing

Load testing with k6 to ensure checkout can handle peak traffic

---

## Step 5: Final Verification

```bash
/craftsman:verify
```

Output:
```
✅ PHPStan: 0 errors
✅ ESLint: 0 errors
✅ Deptrac: Layer boundaries clean
✅ Tests: 47/47 passing
✅ API spec: Synchronized with implementation
✅ PCI-DSS: Audit passed
```

---

## Step 6: Commit

```bash
/craftsman:git
```

Output:
```
feat(checkout): implement full-stack checkout with Stripe payment processing

Backend:
- Design Payment and Order aggregates with status state machines
- Create CheckoutSession value object for session management
- Implement ValidateCheckout, ConfirmOrder use cases
- Integrate Stripe payment gateway with idempotency
- Add webhook handler for async payment confirmation
- Implement PCI-DSS compliant payment flow

Frontend:
- Build React checkout flow (validate → confirm → payment → success)
- Create Stripe Elements integration for secure card input
- Add error handling and loading states
- Implement order status polling

Security:
- Validate webhook signatures (Stripe shared secret)
- Never store raw card data (token only)
- Audit PCI-DSS compliance requirements
- Add idempotency key for duplicate prevention

Tests:
- Unit tests for Payment and Order aggregates
- Integration tests for complete checkout flow
- Security audit checklist

Fixes: #42, #43
```

---

## Summary

**What the team accomplished:**

| Phase | Time | Agent | Output |
|-------|------|-------|--------|
| Domain modeling | 10 min | Backend | Aggregates, events, interfaces |
| API spec | 5 min | Backend | Endpoint definitions |
| Backend domain | 8 min | Backend | Scaffolded domain layer |
| Backend use cases | 8 min | Backend | Use case skeletons |
| Cart validation | 10 min | Backend | ValidateCheckout implementation |
| Stripe integration | 15 min | Backend | Payment gateway + webhook handler |
| React scaffolding | 5 min | Frontend | Component structure |
| Checkout UI | 20 min | Frontend | Complete checkout flow |
| Security audit | 15 min | Security | PCI-DSS compliance review |
| Integration tests | 15 min | Backend | Full flow testing |
| E2E testing | 10 min | Backend | Real API testing |

**Total:** ~120 minutes for a production-grade feature

**Alternative (sequential):** ~180 minutes (50% slower, one developer bottleneck)

**Cost:** ~$0.20-0.30 in API calls (Sonnet + Haiku model tiering)
