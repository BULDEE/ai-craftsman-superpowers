---
type: methodology
title: "Verifying the Instrument"
description: "A check you have never seen fail proves nothing. Before believing what a measurement says about the code, establish that the measurement is capable of saying something else."
tags: [verification, testing, measurement, false-green]
status: stable
---
# Verifying the Instrument

> A green check you have never seen red is not evidence. It is a check whose failure mode you have not met yet.

Most engineering discipline is aimed at defects in the code. This page is aimed at defects in the thing that looks for them. They are more dangerous, because a broken instrument does not announce itself: it produces a confident answer that happens to be about nothing.

The rule is short. **Before you believe what a measurement says about the code, establish that the measurement is capable of saying something else.**

## The five ways an instrument lies

Each of these was observed in one working session on this plugin, in the space of a few hours, by an engineer who was actively looking for them. None of the five was a defect in the code under test.

### 1. The check reads the wrong artifact

A check asserted that a warning offered the user a way to scope a rule. It grepped the hook's **source file** for `.craft-rules.yml` and passed. The string it matched was in a comment on line 262. The message the user actually saw offered nothing.

**Guard:** assert on the emitted output, never on the source that is supposed to emit it. If the claim is about what a user sees, the check must run the thing and read what came out.

### 2. The pattern matches the fix

A check for abbreviations searched for `mode_var` with a word boundary on the left only. After the variable was renamed to `mode_variable`, the check kept firing: it was matching inside the corrected name and reporting the fix as the defect.

**Guard:** anchor both ends. Then reintroduce the defect deliberately and confirm the check goes red, and restore. A guard that has only ever been green is untested code sitting in the position of maximum trust.

### 3. The probe never triggers what is under test

A check asserted that rule SH003 names the offending identifier. Its fixture declared `local pat_var="x"`. SH003 only matches assignments of one or two characters at the start of a line, so the fixture produced no finding at all. The check could have stayed red forever with correct code, or gone green by accident.

**Guard:** before asserting on the shape of a finding, assert that a finding exists. `assert_produced_output` in this repo's test helpers exists for exactly this: an absence assertion that runs after a tool produced nothing is an assertion about nothing.

### 4. The window hides the answer

Ignore rates were computed over a rule's entire history and read as a live defect. One rule showed 98.7 percent suppression, and an issue was filed on it. Slicing the same data around the last relevant change showed the suppressions stopped four days before a fix landed, a month earlier. The rule had been healthy ever since.

**Guard:** an all-time aggregate describes a history, not a present. Compare a recent window against the period before the last change that could plausibly have moved the number. Do this before filing the issue, not after building the fix.

### 5. The verification output is discarded

A ratchet check ran inside a compound command whose output went through `head -3` shared with another command. Its result never reached the screen. The work was pushed on the belief that a verification had passed, and CI failed on it minutes later.

**Guard:** read the result. A verification whose output you piped away, truncated, or backgrounded did not happen. When a command's exit code is the verdict, check the exit code explicitly rather than eyeballing a stream.

## The pattern behind all five

None of the five failures was in the code being built. Every one was in the measurement, the fixture, the window, or the reporting. That distribution is not luck: code is exercised constantly and fails loudly, while an instrument is exercised once, silently, and its failure looks exactly like success.

This is the same principle the structural ratchet applies to debt and the correction loop applies to rules. A verdict nobody can act on teaches nothing; a check nobody has seen fail proves nothing. Both are the absence of information wearing the costume of a result.

## Practice

- **Known-good control before bisection.** Substitute a reference specimen that is known to work, ideally the example shipped with the library you are targeting. If it fails too, the fault is in the wiring, not in your content. Thirty seconds, and it replaces an entire bisection.
- **Red before green, for guards as much as for features.** TDD's discipline is usually taught for production code. It matters more for a check, because a check is never exercised by a user.
- **After fixing, reintroduce.** The bug goes back in, the check goes red, the bug comes out. Anything less leaves you with a guard of unknown polarity.
- **State the confound.** When two things differ between your control and your case, say so rather than claiming the cause. A correlation with a named confound is honest evidence; the same correlation presented as a mechanism is not.

## Related

- [[tdd]] for the red-green discipline this generalizes.
- [[testing-strategy]] for where each kind of check belongs.
- [[../docs/adr/0025-structural-ratchet]] for the committed high-water mark that makes a regression visible instead of arguable.
