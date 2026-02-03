<?php

declare(strict_types=1);

namespace App\Domain\ValueObject;

use App\Domain\Exception\InvalidEmailException;

/**
 * CANONICAL VALUE OBJECT PATTERN
 *
 * Key characteristics:
 * - final class
 * - immutable (readonly properties)
 * - private constructor + static factory with validation
 * - equality by value, not reference
 * - no setters (immutable = create new instance)
 * - self-validating
 */
final readonly class Email
{
    private const MAX_LENGTH = 254;

    private function __construct(
        private string $value,
    ) {
    }

    /**
     * Static factory with validation
     *
     * @throws InvalidEmailException
     */
    public static function fromString(string $value): self
    {
        $normalized = mb_strtolower(trim($value));

        if ($normalized === '') {
            throw InvalidEmailException::empty();
        }

        if (mb_strlen($normalized) > self::MAX_LENGTH) {
            throw InvalidEmailException::tooLong($normalized, self::MAX_LENGTH);
        }

        if (!filter_var($normalized, FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::invalidFormat($normalized);
        }

        return new self($normalized);
    }

    /**
     * Get the value
     */
    public function value(): string
    {
        return $this->value;
    }

    /**
     * Get domain part
     */
    public function domain(): string
    {
        return mb_substr($this->value, mb_strpos($this->value, '@') + 1);
    }

    /**
     * Get local part (before @)
     */
    public function localPart(): string
    {
        return mb_substr($this->value, 0, mb_strpos($this->value, '@'));
    }

    /**
     * Value equality (not reference equality)
     */
    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * String representation
     */
    public function __toString(): string
    {
        return $this->value;
    }
}

// ============================================
// EXAMPLE: Money Value Object (composite)
// ============================================

final readonly class Money
{
    private function __construct(
        private int $cents,
        private Currency $currency,
    ) {
    }

    public static function create(int $cents, Currency $currency): self
    {
        if ($cents < 0) {
            throw new InvalidMoneyException('Amount cannot be negative');
        }

        return new self($cents, $currency);
    }

    public static function eur(int $cents): self
    {
        return new self($cents, Currency::EUR);
    }

    public static function usd(int $cents): self
    {
        return new self($cents, Currency::USD);
    }

    public function cents(): int
    {
        return $this->cents;
    }

    public function currency(): Currency
    {
        return $this->currency;
    }

    /**
     * Immutable operation - returns NEW instance
     */
    public function add(self $other): self
    {
        $this->assertSameCurrency($other);

        return new self(
            $this->cents + $other->cents,
            $this->currency,
        );
    }

    /**
     * Immutable operation - returns NEW instance
     */
    public function subtract(self $other): self
    {
        $this->assertSameCurrency($other);

        $result = $this->cents - $other->cents;
        if ($result < 0) {
            throw new InvalidMoneyException('Result cannot be negative');
        }

        return new self($result, $this->currency);
    }

    /**
     * Immutable operation - returns NEW instance
     */
    public function multiply(float $factor): self
    {
        return new self(
            (int) round($this->cents * $factor),
            $this->currency,
        );
    }

    public function equals(self $other): bool
    {
        return $this->cents === $other->cents
            && $this->currency === $other->currency;
    }

    public function isGreaterThan(self $other): bool
    {
        $this->assertSameCurrency($other);
        return $this->cents > $other->cents;
    }

    public function format(): string
    {
        return sprintf(
            '%s %.2f',
            $this->currency->symbol(),
            $this->cents / 100
        );
    }

    private function assertSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new CurrencyMismatchException($this->currency, $other->currency);
        }
    }
}

enum Currency: string
{
    case EUR = 'EUR';
    case USD = 'USD';
    case GBP = 'GBP';

    public function symbol(): string
    {
        return match($this) {
            self::EUR => '€',
            self::USD => '$',
            self::GBP => '£',
        };
    }
}
