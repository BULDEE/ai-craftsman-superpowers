#!/usr/bin/env python3
"""
Read side of the language registry, for the Python tools.

structural_metrics, ratchet, hotspot_analysis and codemap each ran on their own
list of extensions. Four lists drift, and they had: the ratchet accepted .py and
.sh while the metrics behind it only understood php and ts, so those files were
ratcheted against a signal that was never computed for them.

The shell exports CRAFTSMAN_LANG_REGISTRY, pointing at the TSV that
lang_registry.py produced from the loaded packs' manifests. Absent, every
lookup answers "unknown", which callers must treat as "no pack claims this",
never as an error.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Dialects the engine can extract structural metrics for. A pack declaring
# anything else gets no metrics rather than wrong ones: an indentation-based
# language measured with a brace scanner reports zero nesting everywhere, which
# would ratchet against a signal that is silently absent.
SUPPORTED_METRICS_DIALECTS = ("c-like", "php-like")

_CACHE: dict | None = None


def _registry_path() -> str:
    return os.environ.get("CRAFTSMAN_LANG_REGISTRY", "")


def _manifest_paths() -> list:
    """Every installed pack's manifest, found from this file's location."""
    lib_dir = os.path.dirname(os.path.abspath(__file__))
    packs_dir = os.path.join(os.path.dirname(os.path.dirname(lib_dir)), "packs")
    if not os.path.isdir(packs_dir):
        return []
    found = []
    for entry in sorted(os.listdir(packs_dir)):
        manifest = os.path.join(packs_dir, entry, "pack.yml")
        if os.path.isfile(manifest):
            found.append(manifest)
    return found


def _build_directly() -> dict:
    """
    Parse the manifests in-process when the shell did not export a registry.

    These tools are also run standalone: by CI, by a test harness, by a
    developer. Depending on an environment variable the caller may not have set
    would make them answer "no language is claimed" - indistinguishable, to
    every caller, from "this project loads no pack". Silence is the one answer
    a registry must never give by accident.
    """
    import io
    import lang_registry

    buffer = io.StringIO()
    real_stdout = sys.stdout
    try:
        sys.stdout = buffer
        lang_registry.build(_manifest_paths())
    finally:
        sys.stdout = real_stdout
    return _rows_from_lines(buffer.getvalue().splitlines())


def _rows_from_lines(lines) -> dict:
    table: dict = {}
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        lang, capability, value = parts[0], parts[1], parts[2]
        table.setdefault(lang, {}).setdefault(capability, []).append(value)
    return table


def _read_rows(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return _rows_from_lines(handle)
    except OSError:
        return {}


def _load() -> dict:
    global _CACHE
    if _CACHE is not None:
        return _CACHE

    path = _registry_path()
    if path and os.path.isfile(path):
        _CACHE = _read_rows(path)
    else:
        try:
            _CACHE = _build_directly()
        except Exception:
            _CACHE = {}
    return _CACHE


def language_for_extension(extension: str) -> str:
    """Language id for '.dart' or 'dart', empty when no loaded pack claims it."""
    wanted = extension.lstrip(".")
    for lang, capabilities in _load().items():
        if wanted in capabilities.get("extensions", []):
            return lang
    return ""


def language_for_path(path: str) -> str:
    _, extension = os.path.splitext(path)
    if not extension:
        return ""
    return language_for_extension(extension)


def metrics_dialect(language: str) -> str:
    """Declared dialect, empty when absent or unsupported by this engine."""
    values = _load().get(language, {}).get("metrics_dialect", [])
    if not values:
        return ""
    dialect = values[0]
    return dialect if dialect in SUPPORTED_METRICS_DIALECTS else ""


def dialect_for_path(path: str) -> str:
    return metrics_dialect(language_for_path(path))


def known_extensions() -> set:
    found = set()
    for capabilities in _load().values():
        for extension in capabilities.get("extensions", []):
            found.add("." + extension)
    return found


def entry_markers() -> dict:
    """Marker filename to language id, for project-type detection."""
    markers = {}
    for lang, capabilities in _load().items():
        for marker in capabilities.get("entry_markers", []):
            markers.setdefault(marker, lang)
    return markers
