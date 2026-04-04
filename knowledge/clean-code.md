# Clean Code Principles

> "Clean code reads like well-written prose." — Robert C. Martin

## Naming

### Intent-Revealing Names

Names should tell WHY something exists, WHAT it does, and HOW it's used.

```python
# Bad — reveals nothing
d = 0
lst = []
fp = open("data.csv")

# Good — reveals intent
elapsed_days = 0
active_customers = []
customer_data_file = open("data.csv")
```

### Avoid Abbreviations

```bash
# Bad
dir_b=$(dirname "$f")
tmp=$(mktemp)
cfg=$(cat config.yml)

# Good
directory_bucket=$(dirname "$file_path")
temporary_file=$(mktemp)
configuration_content=$(cat config.yml)
```

### Class Names = Nouns, Method Names = Verbs

```php
// Good: class = noun
final class InvoiceCalculator { }

// Good: method = verb
public function calculateTotal(): Money { }
public function applyDiscount(Discount $discount): void { }
```

### One Word Per Concept

Don't use `fetch`, `retrieve`, `get`, and `obtain` in the same codebase.
Pick one and stick with it.

## Functions

### Small

Functions should do ONE thing, do it well, and do it only.
**Target: 5-15 lines.** If longer, it's doing too much.

### Few Arguments

| Count | Quality |
|-------|---------|
| 0 (niladic) | Ideal |
| 1 (monadic) | Good |
| 2 (dyadic) | Acceptable |
| 3 (triadic) | Justify it |
| 4+ | Extract to object |

### No Side Effects

A function named `checkPassword()` should NOT initialize a session.
That's a hidden side effect that breaks trust.

### Command-Query Separation

Functions should EITHER change state (command) OR return data (query). Never both.

```python
# Bad — command + query mixed
def set_attribute(name, value):
    self._attributes[name] = value
    return True  # What does True mean?

# Good — separated
def set_attribute(name, value):
    self._attributes[name] = value

def has_attribute(name):
    return name in self._attributes
```

## Comments

### Don't Comment Bad Code — Rewrite It

```python
# Bad: comment explaining unclear code
# Check if employee is eligible for full benefits
if employee.flags & 0x02 and employee.age > 65:

# Good: self-documenting code
if employee.is_eligible_for_full_benefits():
```

### Acceptable Comments

- Legal headers (copyright, license)
- Explanation of intent (WHY, not WHAT)
- Warning of consequences
- TODO with ticket reference

## Error Handling

### Use Exceptions, Not Return Codes

```python
# Bad — caller must check return
result = process_data(payload)
if result == -1:
    handle_error()

# Good — exception separates happy path
try:
    process_data(payload)
except InvalidPayloadError as error:
    handle_validation_failure(error)
```

### Don't Return Null

Returning `null`/`None` forces every caller to add null checks.
Use Null Object pattern, Optional, or throw exceptions instead.

### Catch Specific Exceptions

```python
# Bad — catches everything
try:
    parse_config(path)
except:
    pass

# Good — catches what you expect
try:
    parse_config(path)
except FileNotFoundError:
    use_default_config()
except yaml.YAMLError as parse_error:
    raise ConfigurationError(f"Invalid config: {parse_error}")
```

## Objects and Data Structures

### Tell, Don't Ask

```python
# Bad — asking then telling
if order.get_status() == "pending":
    order.set_status("confirmed")
    order.set_confirmed_at(now())

# Good — telling
order.confirm()  # Object manages its own state
```

### Law of Demeter

A method should only call methods on:
- Its own object
- Objects passed as parameters
- Objects it creates
- Its direct components

```python
# Bad — train wreck
customer.get_address().get_city().get_zip_code()

# Good — delegate
customer.shipping_zip_code()
```

## The Boy Scout Rule

> "Leave the campground cleaner than you found it."

When you touch a file:
- Rename unclear variables you encounter
- Extract one small method if you see duplication
- Remove one dead code block

Don't refactor the whole file. Just leave it slightly better.

## SOLID Quick Reference

| Principle | Rule | Violation Signal |
|-----------|------|-----------------|
| **S**ingle Responsibility | One reason to change | Class >200 lines, >5 dependencies |
| **O**pen/Closed | Extend without modifying | Switch on type, if/else chains |
| **L**iskov Substitution | Subtypes must be substitutable | Override that throws, empty methods |
| **I**nterface Segregation | No fat interfaces | Classes implementing unused methods |
| **D**ependency Inversion | Depend on abstractions | `new ConcreteClass()` in domain |
