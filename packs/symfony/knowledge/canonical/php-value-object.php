<?php

/**
 * CANONICAL EXAMPLE: Value Object Pattern (v1.0)
 *
 * This is THE reference. Copy this structure exactly.
 *
 * Key characteristics:
 * - final readonly class (MUST)
 * - private constructor (MUST)
 * - static factory with validation (MUST)
 * - Immutable - no state changes (MUST)
 * - equals() method for comparison (SHOULD)
 * - Self-validating on creation (MUST)
 */

declare(strict_types=1);

namespace App\Domain\ValueObject;

use App\Domain\Exception\InvalidEmailException;

final readonly class Email
{
    private const PATTERN = '/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/';

    private function __construct(
        public string $value,
    ) {}

    public static function create(string $value): self
    {
        $normalized = mb_strtolower(trim($value));

        if (!self::isValid($normalized)) {
            throw new InvalidEmailException($value);
        }

        return new self($normalized);
    }

    public static function isValid(string $value): bool
    {
        return preg_match(self::PATTERN, $value) === 1;
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function domain(): string
    {
        return mb_substr($this->value, mb_strpos($this->value, '@') + 1);
    }

    public function __toString(): string
    {
        return $this->value;
    }
}

// ============================================================
// CANONICAL EXAMPLE: Money Value Object (v1.0)
// ============================================================

final readonly class Money
{
    private function __construct(
        public int $cents,
        public Currency $currency,
    ) {}

    public static function create(int $cents, Currency $currency): self
    {
        if ($cents < 0) {
            throw new NegativeMoneyException($cents);
        }

        return new self($cents, $currency);
    }

    public static function eur(int $cents): self
    {
        return new self($cents, Currency::EUR);
    }

    public function add(self $other): self
    {
        $this->ensureSameCurrency($other);

        return new self($this->cents + $other->cents, $this->currency);
    }

    public function subtract(self $other): self
    {
        $this->ensureSameCurrency($other);

        $result = $this->cents - $other->cents;

        if ($result < 0) {
            throw new InsufficientFundsException($this, $other);
        }

        return new self($result, $this->currency);
    }

    public function multiply(float $factor): self
    {
        return new self((int) round($this->cents * $factor), $this->currency);
    }

    public function equals(self $other): bool
    {
        return $this->cents === $other->cents
            && $this->currency === $other->currency;
    }

    public function isGreaterThan(self $other): bool
    {
        $this->ensureSameCurrency($other);

        return $this->cents > $other->cents;
    }

    public function format(): string
    {
        return number_format($this->cents / 100, 2) . ' ' . $this->currency->value;
    }

    private function ensureSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new CurrencyMismatchException($this->currency, $other->currency);
        }
    }
}

// ============================================================
// CANONICAL EXAMPLE: ID Value Object (v1.0)
// ============================================================

final readonly class UserId
{
    private function __construct(
        public string $value,
    ) {}

    public static function generate(): self
    {
        return new self(Uuid::v7()->toString());
    }

    public static function fromString(string $value): self
    {
        if (!Uuid::isValid($value)) {
            throw new InvalidUserIdException($value);
        }

        return new self($value);
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
