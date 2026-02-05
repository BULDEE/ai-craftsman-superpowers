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

### Command Development

When creating or modifying commands:

```yaml
---
name: command-name
description: Clear, concise description of what the command does (shown in skill list).
---

# /craftsman:command-name - Title

Clear instructions for Claude.

## Process

### Phase 1: [Name]
...

### Phase 2: [Name]
...

## Output Format
...

## Bias Protection
...
```

**Checklist for new commands:**
- [ ] Clear `name` and `description` in frontmatter
- [ ] Structured process with clear phases
- [ ] Output format examples
- [ ] Bias protection section
- [ ] Example in `/examples/{command-name}/`
- [ ] Tests in `/tests/commands/`

See [ADR-0007](docs/adr/0007-commands-over-skills.md) for the rationale behind the commands structure.

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

# Test specific command
./tests/run-tests.sh --command design
```

## Project Structure

```
ai-craftsman-superpowers/
├── .claude-plugin/             # Plugin manifest
├── commands/                   # User-invocable commands (20 *.md files)
├── agents/                     # Specialized reviewers (5)
├── hooks/                      # Automated validation scripts
├── knowledge/                  # Patterns & principles
├── examples/                   # Usage examples
├── tests/                      # Test suite
├── docs/
│   └── adr/                    # Architecture decisions
└── CONTRIBUTING.md
```

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)
- **Bugs**: Open an [Issue](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
- **Chat**: [Discord community](https://discord.gg/eBpgHAGu)

## Recognition

Contributors are recognized in:
- CONTRIBUTORS.md
- Release notes
- README acknowledgments

Thank you for helping make AI-assisted development more rigorous!
