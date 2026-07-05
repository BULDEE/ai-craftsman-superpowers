# Test-Driven Development (TDD)

> "You must write a failing test before you write any production code." - Robert C. Martin, The Three Laws of TDD

TDD, introduced by Kent Beck in the late 1990s, is a pillar of Extreme Programming and of the craft. It is **not a testing technique**: it is a design and development technique whose tests are a happy side effect. The point is to fix the goal (a failing test that encodes the expected behavior) *before* writing the code, then reach that goal with the least code possible.

## Why It Works

Beck observed that fear is legitimate when you face development. Not the paralysing kind, but the fear that makes you think, that you might not see the end of the problem. That fear can turn negative: it stops you communicating, seeking feedback, or even starting. TDD, by being highly structured, converts fear into a short, safe feedback loop.

- Writing the minimum code shortens the feedback delay and keeps the design simple.
- Deferring design decisions to the refactor step lets a **simpler design emerge** than one imagined up front.
- A green suite after every step means you always know the exact line that broke.

## The Three Laws

1. You must write a failing test before you write any production code.
2. You must not write more of a test than is sufficient to fail (or fail to compile).
3. You must not write more production code than is sufficient to make the currently failing test pass.

These laws lock you into very short cycles, seconds to minutes long, not hours.

## Red - Green - Refactor

Every iteration has three phases. At each one you write the minimum to satisfy the need.

| Phase | Goal | Rigor |
|-------|------|-------|
| **Red** | Write a failing test for one behavior | Verify it fails for the *right* reason; check the inputs and expected value actually match the business rule |
| **Green** | Make it pass as fast as possible | Write the least code; a hardcoded return is fine here; resist designing ahead |
| **Refactor** | Improve readability without changing behavior | Rename, extract; prefer IDE-automated refactorings; rerun **all** tests |

If a brand-new test is **green immediately**, distrust it: either the test is wrong (bad expected value or inputs), or the behavior was already built by accident.

## Three Strategies to Get to Green

Beck names three ways to move from red to green. Pick the smallest that fits.

```php
// 1. Fake It - return a hardcoded constant. The fastest possible green.
public function print(int $number): string
{
    return "1"; // just enough to pass "print(1) == '1'"
}
```

```php
// 2. Triangulate - add a second test with different data to force generality.
//    Test A: print(1) == "1"   Test B: print(3) == "Fizz"
public function print(int $number): string
{
    if ($number % self::FIZZ_MULTIPLIER === 0) {
        return "Fizz";
    }
    return (string) $number; // the two examples pulled the constant out
}
```

```php
// 3. Obvious Implementation - when the real code is trivial and you are sure,
//    write it directly instead of faking.
public function isMultipleOf(int $number, int $divider): bool
{
    return $number % $divider === 0;
}
```

Use **Fake It** when the design is unclear, **Triangulate** when you need a second example to justify generalizing, and **Obvious Implementation** only when the code is genuinely trivial and you trust it. Overusing Obvious Implementation is how untested branches sneak in.

## The Test List

Before coding, decompose the problem and write a list of examples (one per business rule). Keep it visible; work it one item at a time and add new items as they occur to you.

```
FizzBuzz - test list
  [x] a number that is not a multiple of 3 or 5 -> the number itself
  [x] a multiple of 3 -> "Fizz"
  [ ] a multiple of 5 -> "Buzz"
  [ ] a multiple of 3 and 5 -> "FizzBuzz"
```

Prioritize by business value or by how often the rule fires: implement the case that carries the most value soonest. Decomposition and prioritization are done **with** the domain, not alone.

## Anatomy of a Test

A test is defined by its **name** and its **body**. Both deserve care: the name states *what* is verified, the body shows *how*.

### Naming: express the business rule

The name should read as the rule under test. Two common conventions, neither objectively better; pick one per team and be consistent:

```
# should / when
Divide_should_raise_an_error_when_denominator_is_zero

# given / when / then (Gherkin-flavored, explicit about the data)
Given_five_and_zero_when_I_divide_then_an_error_is_raised
```

Do not fear a long test name. What matters is that the intent and the failure cause are obvious at a glance.

### Body: Arrange / Act / Assert

The body has three non-overlapping sections. Marking them first, then filling them in, keeps you focused.

```typescript
test("a multiple of three returns Fizz", () => {
  // Arrange
  const fizzBuzz = new FizzBuzz();
  // Act
  const result = fizzBuzz.print(3);
  // Assert
  expect(result).toBe("Fizz");
});
```

A useful trick against writing too much code: write the **Assert first**, then the **Act** it needs, then the **Arrange** those inputs require. Modern IDEs generate the missing class and method for you, so this reversed order is fluid.

## Baby Steps and Regression Safety

Advance one sure step at a time and simplify at every iteration; resist jumping to the final solution. After each green, run the **whole** suite, not just the new test: if an older test goes red, you have introduced a regression, and the newest change is not always the culprit.

Refactoring is, in a sense, infinite: you can always find something to improve. Stop when the code is readable, maintainable, and easy to extend. Extract magic numbers into named constants, remove duplication (e.g. a repeated `% multiplier == 0` becomes an `isMultipleOf` helper), and stop.

## Worked Example: FizzBuzz in Four Iterations

The cycle is easier to trust once seen end to end. Each iteration adds one example from the list and does the smallest thing.

**Iteration 1 - `print(1) == "1"`.** Red: the test names a class and method that do not exist yet; let the IDE generate them throwing `NotImplementedException`. Green: `return "1";` (Fake It). Refactor: nothing yet, but rename the test class if needed.

**Iteration 2 - `print(3) == "Fizz"`.** Red: the new test fails, the first stays green. Green: the smallest change is one condition.

```php
public function print(int $number): string
{
    if ($number % 3 === 0) {
        return "Fizz";
    }
    return (string) $number;
}
```

Refactor: the literal `3` is a magic number; extract it to a named constant `FIZZ_MULTIPLIER`.

**Iteration 3 - `print(5) == "Buzz"`.** Green: add a second guard for `% 5`, extract `BUZZ_MULTIPLIER`. All four tests green.

**Iteration 4 - `print(15) == "FizzBuzz"`.** Green: add the combined guard *first* (order matters, it must precede the single guards). Refactor now that everything is green: the repeated `% multiplier === 0` is duplication.

```php
public function print(int $number): string
{
    if ($this->isMultipleOf($number, self::FIZZ_MULTIPLIER) && $this->isMultipleOf($number, self::BUZZ_MULTIPLIER)) {
        return self::FIZZ . self::BUZZ;
    }
    if ($this->isMultipleOf($number, self::BUZZ_MULTIPLIER)) {
        return self::BUZZ;
    }
    if ($this->isMultipleOf($number, self::FIZZ_MULTIPLIER)) {
        return self::FIZZ;
    }
    return (string) $number;
}

private function isMultipleOf(int $number, int $divider): bool
{
    return $number % $divider === 0;
}
```

Notice what happened: no design was drawn up front. The examples pulled the constants, the guard order, and the `isMultipleOf` abstraction into existence one green bar at a time. This is **emergent design**.

## TDD Styles

There is more than one way to drive with tests, and they compose:

| Style | Starts from | Good when |
|-------|-------------|-----------|
| Inside-out (classicist / Detroit) | The innermost domain object, building outward | The domain rules are the hard part; you know the core |
| Outside-in (mockist / London) | An acceptance test at the boundary, mocking collaborators inward | You know the interaction shape but not the internals |

*TDD as if you meant it* is a deliberate exercise that pushes naivety to the extreme: only ever add the very smallest code, inlining everything, and let refactoring reveal the structure. It is counter-intuitive but frequently surfaces a simpler design than the one you would have planned.

## When TDD Is Not the Right Tool

TDD assumes you can express the expected behavior as a small test up front. That is not always true:

| Situation | Better first move |
|-----------|-------------------|
| Exploring an unknown API or approach | A throwaway **spike**; delete it, then TDD the real thing |
| Legacy code with no tests | Write **characterization tests** first to pin current behavior, then refactor under them - see [[legacy/characterization-testing]] |
| Pure configuration / declarative glue | Often not worth a unit test; cover at integration level |
| A UI pixel layout | Humble object: extract the logic and TDD that, leave the view untested |

For untested legacy, TDD is the destination, not the entry point: get the code under a safety net first with [[legacy/legacy-techniques]].

## Related

- [[testing-strategy]] - where unit TDD sits in the pyramid, the FIRST properties, and test doubles.
- [[refactoring-techniques]] - the catalogue used in the third phase of every cycle.
- [[clean-code]] - the readability target of the refactor step (naming, small functions, no magic numbers).
- [[principles]] - emergent design under TDD tends toward SOLID; each new test that forces a branch is a nudge toward OCP.
