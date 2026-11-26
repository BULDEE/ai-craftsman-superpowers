# Generic review lens

The lens a factory reviewer reads when no pack ships a specialist for the
languages of the diff. It is a checklist, not a persona.

## Correctness

- The change does what each requirement of the spec says, on the edge cases too:
  empty input, the boundary value, the error path, the concurrent caller.
- No error is swallowed, no result of a fallible call is ignored.

## Design

- Dependencies point inward: domain code imports nothing from infrastructure
  or from a framework.
- A value with rules is a type, not a primitive passed around.
- State changes through a method that says why, not through a setter.
- The change is the smallest one that meets the spec: no option, fallback or
  default nobody asked for.

## Tests

- New behaviour has a test that fails without the change.
- A test asserts behaviour, not the mock it set up.
- No existing test was weakened, skipped or special-cased to pass.

## Conventions

- The code reads like its neighbours: naming, structure, error handling,
  comment density.
- Documentation the repository keeps beside the code is updated where the
  change requires it.
