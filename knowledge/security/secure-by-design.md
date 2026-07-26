---
type: methodology
title: "Secure by Design - Boundaries, Secrets, and Data That Is Never Code"
description: "Security is not a review phase, it is a set of boundary decisions taken while the code is written: secrets stay out of source, input is parsed into types at the edge, data never becomes code, and SQL only ever travels through bound parameters."
tags: [security, boundaries, owasp]
rules: [SEC001, SEC002, SEC003]
status: stable
---
# Secure by Design - Boundaries, Secrets, and Data That Is Never Code

Most exploited vulnerabilities are not clever. They are a boundary someone forgot to make explicit: a secret that crossed into git, a string that crossed into an interpreter, a payload that crossed into the domain without ever being parsed. Design the boundary and the class of bug disappears; audit for it later and you are playing whack-a-mole against an attacker who only needs to win once.

Three of those boundaries are enforced by the gate (SEC001, SEC002, SEC003). They are enforced because they are absolute: there is no context in which the violating shape is the right answer.

## Secrets live in the environment or a vault (SEC001)

A credential written in a source file is not "temporary". It is committed, pushed, mirrored to every clone, and archived in every fork within the hour.

- **Read secrets at the edge only.** Infrastructure and configuration resolve `API_KEY` from the environment or the vault client and inject the resolved value. Domain and Application code receive a typed dependency, never a variable name to look up. A domain object that knows how to read `getenv()` has an I/O dependency it should not have.
- **Local means `.env` and `.env` is gitignored.** `.env.example` is committed with the key names and no values, so onboarding stays one command.
- **CI and production mean a secret store**, not a variable pasted into a pipeline definition file.
- **A secret that was ever committed is burned.** Deleting the line does not remove it from history, forks, or the attacker's scraper. Rotate first, remove second, then scan the history (`gitleaks detect`) for the rest of the family.

The gate flags string literals that look like credentials. It cannot see a secret you passed in from a config file that is itself committed, so the discipline matters more than the regex.

## Parse, do not validate, at every boundary

Validation asks a question and throws away the answer. Parsing asks the same question and returns a value that carries the proof.

```
if (!isValidEmail($input)) { throw ... }   // you are still holding a string
$email = Email::fromString($input);        // you are holding an Email, forever
```

- Parse **once**, at the boundary where untrusted data arrives: HTTP payload, queue message, third-party response, CLI argument, CSV import, or a row from a legacy schema nobody owns.
- Parse **into Value Objects** (qual-001, and see anti-patterns/primitive-obsession.md). The constructor is the only place the rule lives, so it cannot be forgotten by the third caller.
- Behind the boundary, code takes the parsed types in its signatures. Defensive re-checks become unnecessary, and their absence is now safe: an unparsed string cannot reach a method that does not accept strings.

This is what makes security a type-system property instead of a code review promise. The reviewer cannot forget what the signature will not accept.

## Data is never code (SEC002)

`eval($input)`, `new Function(str)`, a shell command built by interpolation, and deserializing an untrusted payload into arbitrary classes are the same bug wearing four costumes: the attacker supplies part of the program.

There is no safe way to sanitize input for an interpreter. Every "we escape it first" defense is a bet that you enumerated the interpreter's grammar better than the person attacking it. The fix is not a better filter, it is removing the interpreter.

| Reached for eval because | What was actually wanted | Use instead |
|--------------------------|--------------------------|-------------|
| "Pick a handler by name from config" | Dispatch | A hardcoded map `name => handler`, unknown key rejected |
| "Users write formulas" | Expression evaluation | A purpose-built evaluator with a fixed grammar and no function calls |
| "Run a git command with this URL" | Run a program with arguments | The argument-array API (`Process(['git', 'clone', $url])`), never a shell string |
| "Accept a serialized object" | Parse a message | JSON to a typed DTO, then parse it into domain types |

SEC002 has no allowlist and no "safe" configuration, because there is no safe case to configure.

## Parameterized queries are the only SQL path (SEC003)

Concatenation puts the attacker's string into the **grammar** of the query. A bound parameter puts it into a value slot the parser can never escape from. That difference is structural, not a matter of care.

```
$db->query("SELECT id FROM users WHERE name = '" . $name . "'");        // SEC003
$db->prepare("SELECT id FROM users WHERE name = :name")->execute(['name' => $name]);
```

- **Escaping is not equivalent.** It depends on the connection charset, the driver, and everyone remembering every time. Binding depends on nothing.
- **Identifiers cannot be bound.** Table and column names interpolated from input are the one remaining hole: resolve them through a hardcoded allowlist (`match ($sort) { 'name' => 'name', 'date' => 'created_at' }`), never by passing the input through.
- **An ORM is not immunity.** DQL/HQL built by string concatenation and the raw-query escape hatch reopen the exact same door. Read models (see persistence/query-boundaries.md) run raw SQL by design, so they carry this rule the hardest.
- **The same rule generalizes**: LDAP filters, NoSQL query documents, XPath, shell arguments, and template engines used in raw mode all separate structure from data. Use the separation the API already offers.

## Least privilege, layer by layer

Privilege is a design decision, and Clean Architecture already tells you where each one belongs.

| Layer | Owns | Holds no |
|-------|------|----------|
| Domain | Invariants, business rules | Credentials, I/O, environment access, framework |
| Application | Authorization (may this actor run this use case), transaction boundary | Authentication mechanics, connection strings |
| Infrastructure | Credentials, connection scopes, outbound host allowlists | Business rules |
| Presentation | Authentication, input parsing, output encoding, rate limiting | Persistence access |

Concretely: the runtime database user has no DDL rights (migrations run as a different user, see persistence/migration-discipline.md), the service token used to call a third party is scoped to the endpoints actually called, and an authorization decision lives in the use case where the business rule is, not scattered across controllers.

## What the gate sees, and what it cannot

SEC001-003 are write-time checks on the shape of a single file. They are fast and they never sleep, but they prove nothing about the rest of the system. These belong in CI, and `hooks/lib/tooling_detect.py` names them per stack:

- Dependency CVEs: `composer audit`, `npm audit`, `pip-audit`, `govulncheck`.
- Secrets across the whole history: `gitleaks detect`.
- Cross-file taint paths (input reaching a sink through three hops): `semgrep`, Psalm taint analysis, `bandit`.

The plugin suggests these and prints the install command. It never installs anything (ADR-0019): a tool you did not choose is a tool you will not maintain.
