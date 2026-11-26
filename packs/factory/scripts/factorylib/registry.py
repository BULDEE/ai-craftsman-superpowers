"""Read side of the language registry, for the factory.

The factory holds no list of languages either. Which file belongs to which
language, which configuration files are protected and what a skipped test
looks like are declared by the packs in `pack.yml`; `hooks/lib/lang_registry.py`
compiles those manifests and this module reads the result.
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from .base import PLUGIN_ROOT, run


@lru_cache(maxsize=1)
def _rows() -> tuple:
    manifests = sorted(str(path) for path in (PLUGIN_ROOT / 'packs').glob('*/pack.yml'))
    if not manifests:
        return ()
    compiled = run(['python3', str(PLUGIN_ROOT / 'hooks/lib/lang_registry.py'), *manifests], check=False)
    rows = []
    for line in compiled.stdout.splitlines():
        fields = line.split('\t')
        if len(fields) == 4:
            rows.append(tuple(fields))
    return tuple(rows)


def capability(name: str) -> list[str]:
    """Every value any language declares for a capability, without duplicates."""
    return list(dict.fromkeys(value for _, declared, value, _ in _rows() if declared == name))


def capability_by_language(name: str) -> dict:
    values: dict = {}
    for language, declared, value, _ in _rows():
        if declared == name:
            values.setdefault(language, []).append(value)
    return values


def language_of(path: str) -> str:
    suffix = Path(path).suffix.lstrip('.').lower()
    if not suffix:
        return ''
    for language, declared, value, _ in _rows():
        if declared == 'extensions' and value.lower() == suffix:
            return language
    return ''


def pack_of(language: str) -> str:
    for declared_language, _, _, pack_dir in _rows():
        if declared_language == language:
            return Path(pack_dir.rstrip('/')).name
    return ''


def packs_of(paths: list[str]) -> list[str]:
    """The packs whose languages these files are written in, most files first."""
    counts: dict = {}
    for path in paths:
        pack = pack_of(language_of(path))
        if pack:
            counts[pack] = counts.get(pack, 0) + 1
    return sorted(counts, key=lambda pack: (-counts[pack], pack))
