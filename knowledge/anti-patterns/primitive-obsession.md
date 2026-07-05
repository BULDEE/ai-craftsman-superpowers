# Anti-Pattern: Primitive Obsession

## What It Is

Modeling domain concepts with raw primitives (`string`, `int`, `float`, arrays) instead of dedicated value objects. An email is a `string`, money is a `float`, a user id is an `int`, so the same rules get re-checked (or forgotten) everywhere.

## Why It's Bad

- Validation is duplicated at every use site, and eventually missed at one.
- Type checking cannot catch a mix-up: `transfer(int $fromId, int $toId)` happily accepts the arguments swapped.
- Domain rules (a currency cannot be added to another currency) have nowhere to live.
- The code stops speaking the domain language: `float $amount` says nothing; `Money` says everything.

## Example

### BAD: Primitives everywhere

```php
function transfer(int $fromAccount, int $toAccount, float $amount): void
{
    if ($amount <= 0) { throw new \Exception('bad amount'); } // re-validated everywhere
    // nothing stops transfer($to, $from, $amount) - the ids are interchangeable
}
```

### GOOD: Value objects carry the rules and the identity

```php
final readonly class AccountId
{
    private function __construct(private string $value) {}
    public static function of(string $v): self { /* validate */ return new self($v); }
}

final readonly class Money
{
    private function __construct(private int $cents, private string $currency) {}
    public static function of(int $cents, string $currency): self
    {
        if ($cents < 0) { throw InvalidMoney::negative(); }
        return new self($cents, $currency);
    }
    public function add(self $o): self
    {
        if ($this->currency !== $o->currency) { throw InvalidMoney::currencyMismatch(); }
        return new self($this->cents + $o->cents, $this->currency);
    }
}

// The compiler now enforces what the primitives could not.
function transfer(AccountId $from, AccountId $to, Money $amount): void { /* ... */ }
```

```python
# The same idea in Python, with a frozen dataclass.
from dataclasses import dataclass

@dataclass(frozen=True)
class Money:
    cents: int
    currency: str
    def __post_init__(self) -> None:
        if self.cents < 0:
            raise ValueError("money cannot be negative")
```

## How to Detect

1. Method signatures full of `string`/`int`/`float` for domain concepts.
2. The same validation (email regex, positive-amount check) copy-pasted across files.
3. Bugs from swapped same-typed arguments.
4. Comments explaining what a primitive "really" means (`// amount in cents`).

## How to Fix

1. Introduce a value object per domain primitive (Email, Money, AccountId).
2. Validate on construction; make it immutable.
3. Replace the primitive in signatures with the value object (Introduce Parameter Object / Replace Type Code - see [[refactoring-techniques]]).
4. Move the concept's rules (comparison, arithmetic) onto the value object.

## Rule

> If a primitive has rules, it deserves a type. Give every domain concept its own value object. See [[ddd/ddd-domain-design]] and [[principles]].
