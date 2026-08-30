---
type: anti-pattern
title: "Anti-Pattern: Import-Time Side Effects"
description: "A bare function call at module top level runs the moment the module is imported, not when the caller decides to run it."
tags: [python, modules]
rules: [PY007]
status: stable
---
# Anti-Pattern: Import-Time Side Effects

## What It Is

A statement at module scope that is a bare function call - `setup_database()`, `logging.basicConfig(...)`, `print(...)` - executed as soon as the module is imported, rather than when the caller invokes it.

## Why It's Bad

- Importing a module for one symbol (a class, a constant) silently triggers unrelated work: a database connection, a file write, a network call.
- Import order becomes load-bearing: two modules with side effects can race or conflict depending on which is imported first.
- It breaks testing: importing the module under test to reach one function also runs everything else it does at import time.

## Bad

```python
import logging

logging.basicConfig(level=logging.INFO)
connect_to_database()

def handler(event):
    ...
```

## Good

```python
import logging

logger = logging.getLogger(__name__)

def handler(event):
    ...

def main():
    logging.basicConfig(level=logging.INFO)
    connect_to_database()

if __name__ == "__main__":
    main()
```

Code that must run unconditionally on import (module-level constants, class/function definitions) is not the target: only a bare call statement at module top level is.

## Rule

**PY007** - Module-level side effect on import. Wrap it in a function or guard it with `if __name__ == "__main__":`.
