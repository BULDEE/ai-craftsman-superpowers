# Contributing to AI Craftsman Superpowers

First off, thank you for considering contributing! This project aims to bring software craftsmanship practices to AI-assisted development.

## Code of Conduct

Be respectful, constructive, and professional. We're all here to build better tools.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a report, include:

- **Clear title** describing the issue
- **Steps to reproduce** the behavior
- **Expected behavior** vs what actually happened
- **Claude Code version** and **plugin version**
- **Relevant logs or screenshots**

### Suggesting Enhancements

We welcome feature requests! Please include:

- **Use case**: What problem does this solve?
- **Proposed solution**: How should it work?
- **Alternatives considered**: What else did you think about?

### Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main`: `git checkout -b feature/my-feature`
3. **Make your changes** following our standards (see below)
4. **Test your changes** with real Claude Code usage
5. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/)
6. **Push** and create a Pull Request

## Development Standards

### Skill Development

When creating or modifying skills:

```yaml
---
name: skill-name
description: |
  Clear description of what the skill does.
  Include activation triggers.

  ACTIVATES AUTOMATICALLY when detecting: "keyword1", "keyword2"
model: sonnet  # haiku | sonnet | opus
allowed-tools:
  - Read
  - Glob
  # Only tools actually needed
---

# Skill Title

Clear instructions for Claude.
```

**Checklist for new skills:**
- [ ] Clear `description` with activation triggers
- [ ] Appropriate `model` tier (see ADR-001)
- [ ] Minimal `allowed-tools` (principle of least privilege)
- [ ] Example in `/examples/{skill-name}/`
- [ ] Tests in `/tests/skills/`

### Code Standards

Follow the craftsman principles this plugin promotes:

**PHP:**
- `final class` always
- `declare(strict_types=1)` always
- No public setters
- Value Objects for domain primitives

**TypeScript:**
- No `any` types
- `readonly` properties
- Named exports only
- Branded types for domain primitives

**General:**
- Self-documenting code (minimal comments)
- Tests for behavior, not implementation
- YAGNI - don't add features "just in case"

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

feat(skill): add new RAG design skill
fix(debug): correct ReAct loop detection
docs(examples): add challenge code review example
refactor(hooks): simplify bias detection logic
test(design): add entity creation test case
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### Testing

**Manual Testing:**
1. Install plugin locally: `/plugin install craftsman@/path/to/repo`
2. Test each skill with example prompts from `/examples/`
3. Verify expected behavior matches documentation

**Automated Testing:**
```bash
# Run test suite
./tests/run-tests.sh

# Test specific skill
./tests/run-tests.sh --skill design
```

## Project Structure

```
ai-craftsman-superpowers/
├── plugins/craftsman/          # Main plugin
│   ├── .claude-plugin/         # Plugin manifest
│   ├── skills/                 # All skills
│   ├── hooks/                  # Automated hooks
│   ├── agents/                 # Specialized agents
│   └── knowledge/              # Knowledge base
├── examples/                   # Usage examples
├── tests/                      # Test suite
├── docs/
│   └── adr/                    # Architecture decisions
└── CONTRIBUTING.md
```

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)
- **Bugs**: Open an [Issue](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
- **Chat**: [Discord community](https://discord.gg/your-link)

## Recognition

Contributors are recognized in:
- CONTRIBUTORS.md
- Release notes
- README acknowledgments

Thank you for helping make AI-assisted development more rigorous!
