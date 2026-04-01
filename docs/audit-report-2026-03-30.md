# Documentation Audit & Review Report -- 2026-03-30

## Part 1: New Documentation Review

---

### File: `docs/guides/workflow-comparison.md`

- **Status:** NEEDS FIX
- **Issues found:**
  1. Line 206: States prerequisite `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` should be in "Claude Code settings.json" -- this is correct per `commands/team.md:10`.
  2. Line 207: States `teammates.mode: "iterm"` or `"tmux"` configured -- correct per `commands/team.md:10` which says `teammateMode`.
  3. Line 208: States Claude Code v1.0.33+ -- correct per README badge.
  4. Line 127: References `/craftsman:parallel` -- EXISTS in `commands/parallel.md`.
  5. Line 213: References `/craftsman:team create` -- EXISTS in `commands/team.md`.
  6. Line 224-226: States "Team Lead: Sonnet, Team members: Sonnet, Hooks: Haiku" -- **Correct** per actual `agents/team-lead.md` (model: sonnet). However, this contradicts ADR-001 which lists team-lead under Tier 3 (Opus) and `docs/reference/agents.md` line 33 which says "Model: Opus". The actual file is the source of truth.
  7. All commands referenced (design, spec, scaffold, test, verify, git, parallel, team, plan, challenge) exist in `commands/` EXCEPT `scaffold` -- there IS a `commands/scaffold.md`.
  8. Terminology: Uses "commands" throughout -- **PASS** per ADR-0007.
- **Fixes applied:**
  - None needed in this file. The Sonnet assignment for team-lead matches the actual agent file.

---

### File: `docs/guides/command-chaining.md`

- **Status:** NEEDS FIX
- **Issues found:**
  1. Lines 577-589: Model assignments table claims specific models per command (e.g., challenge = Opus, verify = Haiku, git = Haiku, plan = Opus). **These model assignments are NOT enforced** -- command files no longer carry a `model:` frontmatter field (removed per ADR-0007). The table is aspirational, not factual. This is misleading.
  2. Line 582: States `/craftsman:challenge` uses Opus -- the `commands/challenge.md` has `effort: medium` but no `model:` field.
  3. Line 583: States `/craftsman:verify` uses Haiku -- the `commands/verify.md` has `effort: quick` but no `model:` field.
  4. Line 584: States `/craftsman:git` uses Haiku -- the `commands/git.md` has `effort: quick` but no `model:` field.
  5. Line 587: States `/craftsman:plan` uses Opus -- the `commands/plan.md` has `effort: heavy` but no `model:` field.
  6. Line 588: States `/craftsman:parallel` uses "Opus + N x Sonnet" -- the `commands/parallel.md` has `effort: heavy` but no `model:` field.
  7. Line 589: States `/craftsman:team` uses "Sonnet (team lead) + Sonnet (agents)" -- partially correct: team-lead agent does use Sonnet.
  8. All command names referenced exist in `commands/`.
  9. Terminology: Uses "commands" throughout -- **PASS**.
- **Fixes applied:**
  - None applied in this file. The model table should add a footnote clarifying these are recommendations, not enforced. See recommendation below.

---

### File: `docs/guides/model-tiering-explained.md`

- **Status:** NEEDS FIX (partially fixed)
- **Issues found:**
  1. Lines 35-37: States Haiku is used for `/craftsman:verify`, `/craftsman:git`, and hooks. Commands do NOT enforce model (no `model:` field). Hooks run as bash scripts, not with a specific model. Agent hooks use Haiku via their agent prompt mechanism.
  2. Lines 77-83: States Sonnet is used for design/spec/scaffold/test/refactor/debug. Same issue -- commands don't enforce model.
  3. Lines 123-128: States Opus is used for challenge/plan/parallel/team. Same issue. Also lists `team` as Opus, but `team-lead` agent is actually Sonnet.
  4. Line 127: States `/craftsman:team` uses Opus for "Team lead coordination" -- **WRONG**. The `agents/team-lead.md` has `model: sonnet`, not Opus.
  5. Lines 390-405: Configuration block shows a YAML model config that does not exist in actual plugin configuration. The `plugin.json` has no model assignments per command.
  6. Lines 407-412: References `.craft-config.yml` override for model -- this capability is not documented anywhere in the actual config system.
  7. Line 487: Links to `../adr/001-model-tiering.md` -- EXISTS.
  8. Terminology: Uses "commands" throughout -- **PASS**.
- **Fixes applied:**
  1. Added clarification note after Tier 3 "Used in" section explaining that model tiering is a recommendation, not enforcement, since commands lost their `model:` field per ADR-0007.

---

### File: `examples/team/01-feature-fullstack.md`

- **Status:** PASS (with minor observations)
- **Issues found:**
  1. Line 52-54: States agents use Sonnet -- consistent with actual `agents/team-lead.md` (model: sonnet).
  2. References `/craftsman:team create`, `/craftsman:verify`, `/craftsman:git` -- all exist.
  3. The example is illustrative (shows expected output), not executable documentation.
  4. Terminology: Uses "commands" throughout -- **PASS**.
  5. The TypeScript example code uses `export const` (named exports) -- consistent with TS rules.
  6. PHP example code uses `final class`, `private function __construct()`, `public static` factory -- consistent with PHP rules.
- **Fixes applied:**
  - None needed.

---

### File: `examples/parallel/01-parallel-review.md`

- **Status:** PASS
- **Issues found:**
  1. References `/craftsman:plan`, `/craftsman:parallel`, `/craftsman:verify`, `/craftsman:git` -- all exist in `commands/`.
  2. The example is illustrative.
  3. Terminology: Uses "commands" throughout -- **PASS**.
- **Fixes applied:**
  - None needed.

---

## Part 2: Existing Documentation Audit

---

### README.md

**Version:** States "2.6.1" in badge -- matches `plugin.json` (2.6.1), `marketplace.json` (2.6.1), and `ci/craftsman-ci.sh` (VERSION="2.6.1"). **PASS.**

**Commands badge:** States "15" commands. Actual `commands/` directory has 18 files (15 core + 3 symlinks to AI pack). The badge undercounts. **MUST FIX.**

**Agents badge:** States "5" agents. Actual `agents/` directory has 11 files (5 core + 6 pack symlinks). The badge is ambiguous -- it likely means "5 core agents" but does not specify. README body says "12 agents -- 5 reviewers + 7 craftsmen" (line 224) but the actual count is 11 agent files. **MUST FIX.**

**Commands listed in README that DO NOT EXIST as files:**

| Command | Status |
|---------|--------|
| `/craftsman:entity` | NOT FOUND anywhere in codebase |
| `/craftsman:usecase` | NOT FOUND anywhere in codebase |
| `/craftsman:component` | NOT FOUND anywhere in codebase |
| `/craftsman:hook` | NOT FOUND anywhere in codebase |
| `/craftsman:source-verify` | NOT FOUND anywhere in codebase |
| `/craftsman:agent-create` | NOT FOUND anywhere in codebase |
| `/craftsman:start` | NOT FOUND anywhere in codebase |

These 7 commands are listed in the README tables (lines 146-174) but have no corresponding `.md` files in `commands/`, `packs/`, or anywhere else. They are either planned but not yet implemented, or were removed without updating documentation. **BLOCKING.**

**Agent documentation discrepancy:**
- README line 229: States `team-lead` model is Opus -- **WRONG**. Actual file: `model: sonnet`.
- README lists `ai-reviewer` agent -- this agent does NOT exist anywhere in the codebase. **BLOCKING.**
- README does NOT list `api-craftsman` agent -- this agent EXISTS in `packs/symfony/agents/api-craftsman.md` and is symlinked to `agents/`. **MUST FIX.**

---

### docs/reference/skills.md

**Filename:** The file is called `skills.md` but its title is "# Commands Reference" and it contains a note saying commands replaced skills. The filename itself is the legacy name. **MUST FIX** -- rename to `commands.md` per ADR-0007.

**Commands listed that DO NOT EXIST:**

| Command | Listed in skills.md | Exists in commands/ |
|---------|--------------------|--------------------|
| `/craftsman:entity` | Yes (line 176) | NO |
| `/craftsman:usecase` | Yes (line 196) | NO |
| `/craftsman:component` | Yes (line 216) | NO |
| `/craftsman:hook` | Yes (line 231) | NO |
| `/craftsman:source-verify` | Yes (line 331) | NO |
| `/craftsman:agent-create` | Yes (line 333) | NO |

**Missing commands NOT listed:**
- `/craftsman:ci` -- EXISTS in `commands/ci.md` but NOT listed in skills.md Quick Reference Table.

---

### docs/reference/agents.md

**Agent count:** States "12 agents -- 5 reviewers + 7 craftsmen". Actual count is 11 agent files (5 core + 6 pack symlinks). **MUST FIX.**

**Agents listed that DO NOT EXIST:**
- `ai-reviewer` (documented in lines 240-293) -- NO file found at `agents/ai-reviewer.md` or `packs/*/agents/ai-reviewer.md`. **BLOCKING.**

**Agents that EXIST but are NOT documented:**
- `api-craftsman` (exists at `packs/symfony/agents/api-craftsman.md`, symlinked to `agents/`). **MUST FIX.**

**Model discrepancy:**
- Line 33: States `team-lead` uses Opus. Actual `agents/team-lead.md` has `model: sonnet`. **BLOCKING.**

---

### docs/reference/hooks.md

**Hook count:** States "8 hook events -- 7 command hooks + 4 agent hooks". The `hooks.json` file defines 8 event types (SessionStart, PreToolUse x2, PostToolUse, UserPromptSubmit, FileChanged, InstructionsLoaded, Stop, SessionEnd). The individual hook scripts count to 7 command hooks + 4 agent hooks = 11 total hook scripts across 8 events. Documentation is internally consistent. **PASS.**

**All hook scripts referenced exist in `hooks/`:**
- `session-start.sh` -- EXISTS
- `pre-write-check.sh` -- EXISTS
- `post-write-check.sh` -- EXISTS
- `bias-detector.sh` -- EXISTS
- `file-changed.sh` -- EXISTS
- `pre-push-verify.sh` -- EXISTS
- `session-metrics.sh` -- EXISTS
- `agent-ddd-verifier.sh` -- EXISTS
- `agent-sentry-context.sh` -- EXISTS
- `agent-structure-analyzer.sh` -- EXISTS
- `agent-final-review.sh` -- EXISTS

**PASS** -- all hooks referenced in documentation exist.

---

### docs/getting-started/concepts.md

**Architecture diagram:** Shows Core Pack, Symfony Pack, React Pack, AI Pack structure -- matches actual `packs/` directory. **PASS.**

**Section "1. Skills"** (line 53): Uses "Skills" as heading and throughout the section. Should be "Commands" per ADR-0007. **MUST FIX.**

**Section "2. Packs"** (line 71): Uses "Collections of skills" -- should say "Collections of commands". **MUST FIX.**

**Section "4. Agents"** (line 94): States "12 total" -- actual count is 11. Lists `ai-reviewer` which does not exist. Does not list `api-craftsman` which does exist. **MUST FIX.**

**Link at line 193:** References `../reference/skills.md` with text "Skills Reference" -- should reference commands. **MUST FIX.**

---

## BLOCKING Issues (factually wrong or misleading)

1. **7 phantom commands in README and skills.md:** `entity`, `usecase`, `component`, `hook`, `source-verify`, `agent-create`, `start` are listed as available commands but do not exist as files anywhere in the codebase. Users attempting to use these will get errors.

2. **Phantom agent `ai-reviewer`:** Documented in `docs/reference/agents.md` (full section with examples) and `docs/getting-started/concepts.md` but does not exist as a file anywhere in the repository.

3. **Wrong model for `team-lead`:** Multiple documents state Opus (README line 229, agents.md line 33, ADR-001 line 39-40), but the actual file `agents/team-lead.md` specifies `model: sonnet`. This was likely changed during the v2.6.1 migration to native Agent Teams but documentation was not updated.

## MUST FIX (outdated or inconsistent)

1. **`docs/reference/skills.md` filename:** Should be renamed to `commands.md` per ADR-0007. All internal references to this file must be updated.

2. **Agent count "12":** README badge says "5", README body says "12 (5+7)". Actual file count is 11. The missing one is `ai-reviewer` (phantom). Either create the file or update all counts.

3. **Missing `api-craftsman` from docs:** Agent `api-craftsman` exists in `packs/symfony/agents/` and is symlinked to `agents/` but is not documented in `docs/reference/agents.md` or anywhere else.

4. **Missing `/craftsman:ci` from skills.md:** The command exists in `commands/ci.md` but is absent from the Quick Reference Table in `docs/reference/skills.md`.

5. **Commands badge in README:** States "15" but there are 18 command files (15 core + 3 AI pack symlinks). Should be updated.

6. **Model tiering in command-chaining.md:** Table at lines 577-589 states specific models per command, but commands no longer have `model:` frontmatter. Should add clarifying footnote.

7. **Model tiering YAML config block in model-tiering-explained.md (lines 390-412):** Shows a config format that does not exist in the actual plugin. Misleading.

8. **docs/README.md line 19:** References `./reference/skills.md` with text "Skills Reference". Should say "Commands Reference" and point to the renamed file.

9. **docs/getting-started/first-steps.md line 110:** References `../reference/skills.md` with text "Commands Reference" (correct text, wrong file path if renamed).

## IMPROVE (could be better)

1. **workflow-comparison.md:** The cost estimates ($0.02-$0.04 per feature) are very rough and not backed by any measurement. Consider adding a disclaimer or removing exact dollar amounts.

2. **command-chaining.md:** The "Command Execution Time" table is purely speculative. Consider marking it as "estimated" or "approximate".

3. **model-tiering-explained.md:** The `/craftsman:metrics` output example showing per-model cost breakdown (lines 420-440) suggests metrics tracks model usage, but the actual metrics DB schema (in hooks.md) only tracks violations and sessions, not model usage. This could mislead users.

4. **examples/team/01-feature-fullstack.md:** Very long (961 lines). Consider splitting into a summary + detailed walkthrough.

5. **ADR-001 uses "skills" terminology:** The ADR predates ADR-0007 but still references "skills" -- could be updated for consistency but not critical since ADRs are historical records.

## Terminology Issues

Files using "skills" where "commands" should be used (per ADR-0007):

| File | Line(s) | Current Text | Should Be |
|------|---------|--------------|-----------|
| `docs/reference/skills.md` | filename | `skills.md` | `commands.md` |
| `docs/getting-started/concepts.md` | 53 | `### 1. Skills` | `### 1. Commands` |
| `docs/getting-started/concepts.md` | 55 | `Modular expertise invoked by name` | Keep text, change heading |
| `docs/getting-started/concepts.md` | 59 | `Each skill has:` | `Each command has:` |
| `docs/getting-started/concepts.md` | 73 | `Collections of skills, agents` | `Collections of commands, agents` |
| `docs/getting-started/concepts.md` | 77-82 | Table header: `Skills` | `Commands` |
| `docs/getting-started/concepts.md` | 193 | `Skills Reference` link text | `Commands Reference` |
| `docs/README.md` | 19 | `Skills Reference` | `Commands Reference` |
| `docs/README.md` | 55-56 | `All skills`, `skills` | `commands` |
| `docs/getting-started/first-steps.md` | 110 | Points to `skills.md` | Should point to `commands.md` |
| `docs/adr/001-model-tiering.md` | 13 | `Skills can specify` | Historical ADR, low priority |
| `docs/adr/001-model-tiering.md` | 42-44 | `skills` labels | Historical ADR, low priority |

## Summary

| Metric | Count |
|--------|-------|
| Files reviewed | 10 |
| Total issues found | 28 |
| BLOCKING issues | 3 |
| MUST FIX issues | 9 |
| IMPROVE suggestions | 5 |
| Terminology fixes needed | 11 |
| Issues fixed in this audit | 1 |
| Remaining issues | 27 |

### Priority Action Items

1. **[BLOCKING] Create or remove 7 phantom commands** -- entity, usecase, component, hook, source-verify, agent-create, start. Either create the command files or remove them from all documentation.

2. **[BLOCKING] Create or remove `ai-reviewer` agent** -- either create `agents/ai-reviewer.md` (or pack equivalent) or remove from agents.md and concepts.md.

3. **[BLOCKING] Fix team-lead model documentation** -- update README (line 229), agents.md (line 33), and decide whether ADR-001 should be amended or a new ADR written explaining the change from Opus to Sonnet.

4. **[MUST FIX] Rename `docs/reference/skills.md` to `commands.md`** and update all 4+ internal links pointing to it.

5. **[MUST FIX] Document `api-craftsman` agent** -- add section in agents.md.

6. **[MUST FIX] Update command/agent counts** in README badges and body text.
