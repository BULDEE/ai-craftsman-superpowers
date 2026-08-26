"""Hermes plugin entry point.

This repository is a Claude Code plugin first; Claude Code reads
`.claude-plugin/plugin.json` and ignores this file. Hermes reads `plugin.yaml`
at the directory root and imports this module, so the two hosts share one
clone:

    git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
    hermes plugins enable craftsman

The implementation lives with the other Hermes host material in
`adapters/hermes/`; this file only loads it by path, because the repository is
not otherwise a Python package.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

_IMPL = Path(__file__).resolve().parent / "adapters" / "hermes" / "craftsman_plugin.py"

_spec = importlib.util.spec_from_file_location("craftsman_hermes_plugin", _IMPL)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)


def register(ctx: Any) -> None:
    _module.register(ctx)
