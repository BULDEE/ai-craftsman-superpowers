# Anti-Pattern: Bare Except

## The Problem

`except:` catches everything including `KeyboardInterrupt`, `SystemExit`, and `GeneratorExit`.
This silences critical errors and makes debugging impossible.

## Bad

```python
try:
    process_data(payload)
except:
    logger.error("Something went wrong")
```

## Good

```python
try:
    process_data(payload)
except ValueError as validation_error:
    logger.warning(f"Invalid payload: {validation_error}")
except ConnectionError as network_error:
    logger.error(f"Network failure: {network_error}")
    raise
```

## Rule

**PY004** — Bare `except:` found. Always catch specific exceptions.
