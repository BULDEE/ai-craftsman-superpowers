# ADR-0026: Adversarial Design Panel - Contradiction Before Code

## Status

Accepted

## Date

2026-07-26

## Context

Design flaws are discovered after code exists: after a month of work, the aggregate boundary is wrong, a feature violates a domain invariant, or an integration point cannot work as drawn. By that time, refactoring is costly. The plugin encourages the `/craftsman:design` skill (4-phase: Understand, Challenge, Recommend, Implement), but Challenge was unstructured advice: "think about this more." Meanwhile, the plugin's security and infrastructure rules (ADR-0024 onwards) benefit from multiple expert lenses; one view misses contradiction.

The plugin already runs headless Haiku verification (haiku-verify.sh) in hooks, gated by `agent_hooks` config and `CRAFTSMAN_HEADLESS_VERIFY` recursion guard. That mechanism ensures subprocesses do not spawn verification loops and cost is bounded by configuration.

## Decision

Convene an adversarial design panel during `/craftsman:design` Phase 2 Challenge. Three headless Haiku instances attack the proposed design under distinct lenses BEFORE any code is written:

1. **Lens 1 (YAGNI)**: Unnecessary abstraction, speculative generality, features nobody asked for, simpler alternatives dismissed without reason. Is this really an Entity, or would a Value Object suffice?
2. **Lens 2 (Invariants/Boundaries)**: Invariants that cannot be protected, aggregate boundaries forcing multi-aggregate transactions, missing value objects, anemic entities. Is this the right boundary? What domain concept is missing?
3. **Lens 3 (Feasibility)**: Hidden performance cliffs (N+1, unbounded reads), operational blind spots, failure modes without recovery, integration points that will not work as drawn. What breaks under load or concurrency?

Each contradicts the design from its lens. Every objection (max 5 per lens, most severe first) must be captured in Phase 3 Recommend as either "retained (with change made)" or "dismissed (with reason)." Silence on an objection is forbidden; the panel forces explicit trade-off accounting.

Cost is announced upfront (3 Haiku calls) before running. Placement is design-time only, never automatic on Stop or every write (no alert fatigue). A code-level refutation panel (`/craftsman:challenge --adversarial`) stays opt-in; design contradictions happen once, code contradictions can iterate.

## Consequences

### Positive

- Contradiction is cheapest at design time. Remodeling after code exists has exponential cost. The panel captures design flaws before implementation.
- Multiple lenses prevent single-view blindness: YAGNI catches over-engineering, boundaries catch invariant violations, feasibility catches operational surprises.
- The panel forces explicit accounting: dismissing an objection requires stating why. Silently ignoring it is not allowed. This creates a decision record.
- Headless Haiku respects the same `agent_hooks` gate as other verification, so teams can disable all LLM-side verification uniformly.
- Cost is transparent and optional: displayed before running, can be disabled via config.

### Negative

- Three Haiku calls per design adds latency (~2-3s) and token cost (roughly 1.5-2k tokens). For teams iterating rapidly on many small designs, this may feel slow. But the cost is paid once per design, not once per file; a 1-week design session with 1 final design pays it once.
- Haiku is smaller and faster than Opus or Sonnet; contraposition quality is good but not exhaustive. A seasoned architect may spot flaws the panel misses. The panel is advisory, not authoritative; user judgment remains the final gate.
- Objections may be vague or incorrect. The user must read them critically and decide whether to retain or dismiss them, not blindly follow the panel. Weak contradictions must still be recorded (dismissed, with reason).

### Neutral

- The panel adds no new rule categories or knowledge base entries; it reuses existing `haiku-verify.sh` infrastructure and knowledge already wired into the plugin.
- Teams that disable `agent_hooks` skip the panel entirely; design review stays structural-only via Phase 1/2 self-challenge.

## Alternatives Considered

### Alternative 1: Automatic panel on every Stop or write

Contradict every design and code change in real time. Rejected: alert fatigue makes every warning worthless, cost is prohibitive (hundreds of Haiku calls per session), and design rarely changes mid-session (Implement phase is stable).

### Alternative 2: Demand-only (already the case, but considered centralizing)

Require the user to explicitly request contradiction via a slash command. Rejected: misses the moment where contradiction is cheapest (at Phase 2, which many users skip without prompting). Centralized discovery via the design skill ensures the panel runs when it matters most.

### Alternative 3: Synthetic objections (template list without Haiku)

Provide a checklist of common design flaws instead of LLM-generated contradictions. Rejected: checklists are domain-agnostic and miss context-specific flaws; an LLM reading the actual design is more likely to spot the real contradiction hiding in the model choice.

## References

- ADR-0019 (established tooling first): philosophy of optional, cost-transparent features
- ADR-0023 (verification loop): quality gate design and cost management
- ADR-0024 (OKF knowledge bundle): knowledge routing and doctrine pointers
- ADR-0027 (situational onboarding): guided mode and help maximization
- hooks/design-panel.sh: implementation of the three lenses
- skills/design/SKILL.md: Phase 2 Challenge workflow and panel invocation
- knowledge/ddd/ddd-domain-design.md: entities, aggregates, invariants (material the panel reads)
