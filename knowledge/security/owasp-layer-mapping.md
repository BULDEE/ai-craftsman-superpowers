---
type: reference
title: "OWASP Risks by Architectural Layer"
description: "Each OWASP Top 10 category mapped onto the Clean Architecture layer that owns its defense, so a risk becomes a place in the codebase instead of a line in an audit report."
tags: [security, owasp, architecture]
rules: []
status: stable
---
# OWASP Risks by Architectural Layer

A risk category is only actionable once you know which layer owns the defense. "The team owns it" means nobody does; "the Presentation layer owns output encoding" means there is a file to open and a test to write.

One owner per row. Defense in depth is real, but it is layered redundancy on top of a named owner, not shared responsibility instead of one.

## The mapping (OWASP Top 10, 2021)

| Risk | Owning layer | The defense it implements | Fails as |
|------|--------------|---------------------------|----------|
| A01 Broken Access Control | Application | Authorization at the use case entry: this actor, this resource, this operation | Checks in controllers only, so the CLI and queue consumers bypass them |
| A02 Cryptographic Failures | Infrastructure | Transport and at-rest encryption, key handling, hashing algorithm choice | Hand-rolled crypto, secrets in source (SEC001), passwords hashed with a fast digest |
| A03 Injection | Presentation + Infrastructure | Parse at the edge into types (Presentation), bound parameters and argument arrays at the sink (Infrastructure) | String concatenation into SQL (SEC003), eval on input (SEC002), shell strings |
| A04 Insecure Design | Domain | Invariants that cannot be violated by any caller, aggregate boundaries, business limits (quota, rate, amount) | Anemic entities that let any state through (see anti-patterns/anemic-domain.md) |
| A05 Security Misconfiguration | Infrastructure | Hardened defaults, debug off in production, no default credentials, least-privilege service accounts | Prod configured by copying the dev environment |
| A06 Vulnerable and Outdated Components | Infrastructure (build) | Lockfiles, dependency audit in CI, an upgrade cadence that is scheduled rather than heroic | Audit run manually, once, before an incident |
| A07 Identification and Authentication Failures | Presentation | Session and token lifecycle, MFA, lockout, credential recovery flows | Auth logic reimplemented per entry point |
| A08 Software and Data Integrity Failures | Infrastructure (build) | Pinned and verified dependencies, signed artifacts, no deserialization of untrusted payloads | CI pipeline pulling a mutable tag from an unverified source |
| A09 Logging and Monitoring Failures | Application + Infrastructure | Emit domain events for security-relevant decisions (Application), ship and alert on them (Infrastructure) | Logs exist, nobody reads them, and they contain the secrets |
| A10 Server-Side Request Forgery | Infrastructure | Outbound host allowlist, no user-supplied URL fetched directly, no redirect following into private ranges | A "fetch this URL" feature with a blocklist instead of an allowlist |

## Reading the table

- **The Domain owns exactly one row (A04), and that is correct.** It has no I/O, so it cannot be injected, misconfigured, or made to leak a key. What it can do is refuse impossible states, which is the only defense against the design-level flaws no scanner will ever find.
- **Infrastructure carries the most rows** because that is where the process touches the outside world: credentials, sockets, files, and other people's servers.
- **A03 is the only split row**, and the split is the point: parsing at the edge (see secure-by-design.md) and binding at the sink defend the same risk from both ends. Either alone is one refactor away from being bypassed.
- **A06 and A08 are build-time**, not runtime. Their owner is the pipeline, which is why the tooling detector suggests `composer audit` / `npm audit` / `pip-audit` for CI rather than for the hook.

## Where this repository's rules land

| Rule | Risk | Enforced |
|------|------|----------|
| SEC001 hardcoded secret | A02, A05 | Hook (write time) and CI |
| SEC002 dynamic eval or exec | A03 | Hook and CI |
| SEC003 SQL by concatenation | A03 | Hook and CI |
| LAYER001-004 dependency direction | A04 | Hook and CI |

Everything else on the list needs a tool, a pipeline step, or a design conversation. The gate is the floor, not the ceiling.
