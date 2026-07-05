<?php

/**
 * CANONICAL EXAMPLE: SOLID Principles in PHP (v1.0)
 *
 * One idiomatic demonstration per principle. See knowledge/principles.md
 * for the theory and the cross-language mapping table.
 */

declare(strict_types=1);

namespace App\Domain\Solid;

/* =============================================================================
 * S - Single Responsibility Principle
 * A class has one reason to change. Split persistence, formatting, and rules.
 * ========================================================================== */

// Bad: this class computes tax AND formats a report AND talks to the DB.
// Good: each responsibility is its own class.
final readonly class TaxCalculator
{
    public function calculate(Money $amount, TaxRate $rate): Money
    {
        return $amount->percentage($rate->value());
    }
}

/* =============================================================================
 * O - Open/Closed Principle
 * Open for extension, closed for modification. Add a type without editing a switch.
 * ========================================================================== */

interface DiscountPolicy
{
    public function apply(Money $subtotal): Money;
}

final readonly class SeasonalDiscount implements DiscountPolicy
{
    public function __construct(private int $percent) {}
    public function apply(Money $subtotal): Money
    {
        return $subtotal->subtract($subtotal->percentage($this->percent));
    }
}

// A new discount = a new class. The caller below never changes.
final readonly class Checkout
{
    public function total(Money $subtotal, DiscountPolicy $discount): Money
    {
        return $discount->apply($subtotal);
    }
}

/* =============================================================================
 * L - Liskov Substitution Principle
 * A subtype must be usable wherever its supertype is, with no surprises.
 * A Square that overrides setWidth to also change height breaks callers:
 * model shapes as separate immutable types instead of Square extends Rectangle.
 * ========================================================================== */

interface Shape
{
    public function area(): float;
}

final readonly class Rectangle implements Shape
{
    public function __construct(private float $width, private float $height) {}
    public function area(): float { return $this->width * $this->height; }
}

final readonly class Square implements Shape
{
    public function __construct(private float $side) {}
    public function area(): float { return $this->side ** 2; }
}

/* =============================================================================
 * I - Interface Segregation Principle
 * No client should depend on methods it does not use. Prefer small interfaces.
 * ========================================================================== */

// Bad: one fat interface forces read-only clients to implement writes.
interface OrderReader
{
    public function find(OrderId $id): ?Order;
}

interface OrderWriter
{
    public function save(Order $order): void;
}

// A read-side service depends only on OrderReader.

/* =============================================================================
 * D - Dependency Inversion Principle
 * Depend on abstractions, not concretions. High-level policy owns the interface.
 * ========================================================================== */

interface Clock
{
    public function now(): \DateTimeImmutable;
}

final readonly class PlaceOrder
{
    // Depends on the Clock abstraction, never on a concrete system clock.
    public function __construct(private Clock $clock) {}

    public function __invoke(OrderId $id): void
    {
        // ... uses $this->clock->now() instead of a hardcoded system clock
    }
}
