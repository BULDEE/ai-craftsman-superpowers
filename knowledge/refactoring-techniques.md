# Refactoring Techniques

> "Refactoring is a disciplined technique for restructuring code, altering its internal structure without changing its external behavior." — Martin Fowler

Reference: [refactoring.guru/refactoring](https://refactoring.guru/refactoring)

## When to Refactor

### The Rule of Three

1. First time: just do it
2. Second time: wince but do it anyway
3. Third time: refactor

### Code Smells — Detection Guide

| Category | Smell | Detection Signal |
|----------|-------|-----------------|
| **Bloaters** | Long Method | >15 lines, multiple comments needed |
| | Large Class | >200 lines, >5 responsibilities |
| | Primitive Obsession | `string $email`, `int $cents` |
| | Long Parameter List | >3 parameters |
| | Data Clumps | Same 3+ params appear together |
| **OO Abusers** | Switch Statements | switch/if-else on type |
| | Refused Bequest | Subclass ignores parent methods |
| | Alternative Classes | Different classes, same interface |
| | Temporary Field | Fields only used in some cases |
| **Change Preventers** | Divergent Change | One class changed for many reasons |
| | Shotgun Surgery | One change touches many classes |
| | Parallel Inheritance | New subclass requires another hierarchy |
| **Dispensables** | Comments | Explaining bad code instead of fixing |
| | Duplicate Code | Same structure in 2+ places |
| | Dead Code | Unreachable or unused code |
| | Lazy Class | Class that doesn't do enough |
| | Speculative Generality | YAGNI — built for hypothetical futures |
| **Couplers** | Feature Envy | Method uses other object's data more |
| | Inappropriate Intimacy | Classes access each other's privates |
| | Message Chains | `a.b().c().d()` |
| | Middle Man | Class only delegates |

## Composing Methods

### Extract Method

The most common refactoring. If a code fragment can be grouped together:

```python
# Before
def print_invoice(invoice):
    # print header
    print(f"Invoice #{invoice.number}")
    print(f"Date: {invoice.date}")
    print("---")
    # print items
    for item in invoice.items:
        print(f"  {item.name}: {item.price}")
    # print total
    total = sum(item.price for item in invoice.items)
    print(f"Total: {total}")

# After
def print_invoice(invoice):
    print_header(invoice)
    print_items(invoice.items)
    print_total(invoice.items)
```

### Inline Method

Inverse of Extract. When a method body is as clear as the name:

```python
# Before
def is_more_than_five_late_deliveries():
    return get_number_of_late_deliveries() > 5

def get_rating():
    return 2 if is_more_than_five_late_deliveries() else 1

# After
def get_rating():
    return 2 if get_number_of_late_deliveries() > 5 else 1
```

### Replace Temp with Query

```python
# Before
base_price = quantity * item_price
if base_price > 1000:
    return base_price * 0.95

# After
def base_price():
    return quantity * item_price

if base_price() > 1000:
    return base_price() * 0.95
```

### Introduce Explaining Variable

```python
# Before
if platform.upper().find("MAC") > -1 and browser.upper().find("IE") > -1 and resize > 0:

# After
is_mac_os = platform.upper().find("MAC") > -1
is_ie_browser = browser.upper().find("IE") > -1
was_resized = resize > 0
if is_mac_os and is_ie_browser and was_resized:
```

## Moving Features Between Objects

### Move Method

When a method uses more features of another class than its own.

### Extract Class

When one class does the work of two. Split responsibilities.

### Inline Class

Inverse — when a class does almost nothing. Merge it back.

### Hide Delegate

```python
# Before — client knows about department
manager = person.department.manager

# After — person delegates
manager = person.manager  # person.manager delegates to department
```

## Organizing Data

### Replace Magic Number with Constant

```bash
# Before
if [[ ${#files} -gt 3 ]]; then

# After
readonly CROSS_FILE_PATTERN_THRESHOLD=3
if [[ ${#files} -gt $CROSS_FILE_PATTERN_THRESHOLD ]]; then
```

### Replace Type Code with Class

```python
# Before
BLOOD_A = 0
BLOOD_B = 1
BLOOD_AB = 2
BLOOD_O = 3

# After
class BloodGroup(Enum):
    A = auto()
    B = auto()
    AB = auto()
    O = auto()
```

### Encapsulate Field

```python
# Before
class Person:
    name: str  # public access

# After
class Person:
    _name: str

    @property
    def name(self) -> str:
        return self._name
```

### Replace Array with Object

```python
# Before
row = ["Liverpool", 15]
row[0]  # team name
row[1]  # wins

# After
@dataclass
class TeamRecord:
    team_name: str
    wins: int
```

## Simplifying Conditionals

### Decompose Conditional

```python
# Before
if date.before(SUMMER_START) or date.after(SUMMER_END):
    charge = quantity * winter_rate + winter_service_charge
else:
    charge = quantity * summer_rate

# After
if is_summer(date):
    charge = summer_charge(quantity)
else:
    charge = winter_charge(quantity)
```

### Replace Conditional with Polymorphism

```python
# Before
def calculate_area(shape):
    if shape.type == "circle":
        return math.pi * shape.radius ** 2
    elif shape.type == "rectangle":
        return shape.width * shape.height

# After
class Circle:
    def area(self) -> float:
        return math.pi * self.radius ** 2

class Rectangle:
    def area(self) -> float:
        return self.width * self.height
```

### Introduce Null Object

```python
# Before
customer = site.customer
plan = customer.plan if customer else BillingPlan.basic()

# After
class NullCustomer:
    @property
    def plan(self):
        return BillingPlan.basic()
```

### Replace Nested Conditional with Guard Clauses

```python
# Before
def get_payment_amount():
    if is_dead:
        result = dead_amount()
    else:
        if is_separated:
            result = separated_amount()
        else:
            if is_retired:
                result = retired_amount()
            else:
                result = normal_amount()
    return result

# After
def get_payment_amount():
    if is_dead:
        return dead_amount()
    if is_separated:
        return separated_amount()
    if is_retired:
        return retired_amount()
    return normal_amount()
```

## Simplifying Method Calls

### Rename Method

The most important refactoring for readability. If you have to think about what a method does, rename it.

### Introduce Parameter Object

```python
# Before
def amount_invoiced(start_date, end_date): ...
def amount_received(start_date, end_date): ...
def amount_overdue(start_date, end_date): ...

# After
@dataclass(frozen=True)
class DateRange:
    start: date
    end: date

def amount_invoiced(period: DateRange): ...
```

### Replace Parameter with Method Call

```python
# Before
base_price = quantity * item_price
discount = get_discount_level()
final_price = discounted_price(base_price, discount)

# After (method gets discount itself)
base_price = quantity * item_price
final_price = discounted_price(base_price)
```

## Dealing with Generalization

### Pull Up / Push Down Method

Move methods up when shared by siblings, down when used by only one.

### Extract Interface

When multiple classes share part of their interface, formalize it.

### Replace Inheritance with Delegation

When a subclass only uses part of its superclass. Use composition instead.

```python
# Before
class Stack(list):
    def push(self, item): self.append(item)

# After
class Stack:
    def __init__(self):
        self._items = []
    def push(self, item):
        self._items.append(item)
```
