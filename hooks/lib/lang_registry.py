#!/usr/bin/env python3
"""
Language registry builder.

Reads every pack.yml handed to it and emits one flat TSV describing the
languages those packs contribute. The engine holds no list of languages of its
own: adding the fiftieth language is adding a fiftieth pack.

Output, one capability value per line:

    <lang_id>\t<capability>\t<value>\t<pack_dir>

Capabilities are deliberately flat rather than nested so bash 3.2 can query
them with grep and cut. macOS ships bash 3.2, which has no associative arrays,
and a registry the shell cannot read is a registry that gets bypassed by a
literal case statement.

Usage:
    lang_registry.py <pack.yml> [<pack.yml> ...]

Graceful degradation: works without PyYAML, on the subset of YAML that pack
manifests actually use.
"""

from __future__ import annotations

import os
import re
import sys

# A capability holding several values (emitted as one line each) as opposed to
# a scalar. Anything not listed here is emitted verbatim as a single line.
LIST_CAPABILITIES = (
    "extensions",
    "entry_markers",
    "protected_configs",
    "validators",
    "static_analysis",
    "test_commands",
    "supersedes",  # <tool>=<RULE>,... see precedence_defers in precedence.sh
)

SCALAR_CAPABILITIES = (
    "lsp",
    "metrics_dialect",
)

KNOWN_CAPABILITIES = LIST_CAPABILITIES + SCALAR_CAPABILITIES

_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$")


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _split_inline_list(value: str) -> list[str]:
    value = value.strip()
    if value.startswith("[") and value.endswith("]"):
        value = value[1:-1]
    return [_unquote(part) for part in value.split(",") if _unquote(part)]


def _parse_with_pyyaml(path: str) -> dict:
    import yaml

    with open(path, "r") as handle:
        return yaml.safe_load(handle) or {}


class _FallbackReader:
    """
    Minimal reader for the `languages:` block without PyYAML.

    Handles both forms a manifest may use for a capability value: an inline
    list (`extensions: [dart]`) and a block sequence. The hand-rolled reader in
    pack-loader.sh only ever handled the inline form, which silently produced
    empty packs for anyone writing idiomatic YAML.
    """

    def __init__(self) -> None:
        self.languages: list[dict] = []
        self._current: dict | None = None
        self._pending_key: str | None = None
        self._in_languages = False

    def feed(self, raw: str) -> None:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            return
        if re.match(r"^[A-Za-z_]", line):
            self._enter_top_level(line)
            return
        if self._in_languages:
            self._read_entry_line(line.strip())

    def result(self) -> list[dict]:
        self._close_current()
        return self.languages

    def _enter_top_level(self, line: str) -> None:
        self._close_current()
        self._in_languages = line.startswith("languages:")
        self._pending_key = None

    def _close_current(self) -> None:
        if self._current:
            self.languages.append(self._current)
        self._current = None

    def _read_entry_line(self, stripped: str) -> None:
        if stripped.startswith("- ") and not self._pending_key:
            self._close_current()
            self._current = {}
            stripped = stripped[2:].strip()
            if not stripped:
                return
        if self._current is None:
            return
        if stripped.startswith("- ") and self._pending_key:
            self._current.setdefault(self._pending_key, []).append(
                _unquote(stripped[2:])
            )
            return
        self._read_key_value(stripped)

    def _read_key_value(self, stripped: str) -> None:
        match = _KEY_RE.match(stripped)
        if not match or self._current is None:
            return
        key, value = match.group(1), match.group(2).strip()
        if not value:
            self._pending_key = key
            self._current.setdefault(key, [])
            return
        self._pending_key = None
        if value.startswith("["):
            self._current[key] = _split_inline_list(value)
        else:
            self._current[key] = _unquote(value)


def _parse_languages_fallback(path: str) -> list[dict]:
    reader = _FallbackReader()
    with open(path, "r") as handle:
        for raw in handle:
            reader.feed(raw)
    return reader.result()


def _languages_of(path: str) -> list[dict]:
    try:
        manifest = _parse_with_pyyaml(path)
    except ImportError:
        return _parse_languages_fallback(path)
    except Exception:
        return []

    languages = manifest.get("languages")
    if not isinstance(languages, list):
        return []
    return [entry for entry in languages if isinstance(entry, dict)]


# craftsman-ignore: WARN-PY001 - the four parameters are the four TSV columns;
# wrapping one output row in an object is ceremony, not a boundary.
def _emit(lang_id: str, capability: str, value: str, pack_dir: str) -> None:
    if not value:
        return
    # A tab or newline inside a manifest value would corrupt every downstream
    # cut, so drop the record rather than emit a row that shifts the columns.
    if "\t" in value or "\n" in value:
        return
    sys.stdout.write(f"{lang_id}\t{capability}\t{value}\t{pack_dir}\n")


def _as_list(value) -> list:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def _tool_name(spec: str) -> str:
    """What a tool spec resolves to: no directory, no file extension."""
    name = str(spec).strip().split("/")[-1]
    return name.rsplit(".", 1)[0] if "." in name else name


# A tool may not be declared the owner of its own verdicts, and both shapes of
# that loop are readable from the manifest alone. Either the named tool IS one
# of the language's own Level 2/3 adapters, so it would outrank the level it
# belongs to; or the rule id is that tool's own code family (`<tool>NNN`),
# which is the same loop written in the other column. Either way the analyser
# would fall silent because the analyser is present.
#
# The engine holds no list of tools or rules to check this against: the
# contradiction is between two lines of the same manifest.
def _self_superseding(tool: str, rule: str, analysers: list) -> bool:
    name = _tool_name(tool)
    if not name:
        return True
    if any(_tool_name(adapter) == name for adapter in analysers):
        return True
    return rule.rstrip("0123456789").lower() == name.lower()


class _Indexer:
    """Carries the cross-manifest state (which language owns which extension)
    so the per-capability helpers stay within the three-parameter budget."""

    def __init__(self) -> None:
        self._owners: dict[str, str] = {}
        self.conflicts = 0
        self._pack_dir = ""

    def index_manifest(self, manifest_path: str) -> None:
        self._pack_dir = os.path.dirname(os.path.abspath(manifest_path))
        for entry in _languages_of(manifest_path):
            self._index_language(entry)

    def _index_language(self, entry: dict) -> None:
        lang_id = str(entry.get("id") or "").strip()
        if not lang_id:
            return
        for capability in KNOWN_CAPABILITIES:
            if capability not in entry:
                continue
            if capability == "supersedes":
                self._index_supersedes(lang_id, entry)
            elif capability in LIST_CAPABILITIES:
                self._index_list(lang_id, capability, entry[capability])
            else:
                _emit(
                    lang_id,
                    capability,
                    str(entry[capability]).strip(),
                    self._pack_dir,
                )

    def _index_supersedes(self, lang_id: str, entry: dict) -> None:
        """Compile-time refusal, so a self-silencing pair never reaches the
        registry the hooks read. Deferring already makes it structurally
        impossible for a Level 2/3 verdict to be held; this is the net under
        it, and it fires at the manifest rather than at runtime."""
        analysers = _as_list(entry.get("static_analysis"))
        for item in _as_list(entry.get("supersedes")):
            tool, separator, rules = str(item).strip().partition("=")
            if not separator:
                continue
            kept = self._keep_claims(tool, rules, analysers)
            if kept:
                _emit(lang_id, "supersedes", f"{tool}={kept}", self._pack_dir)

    def _keep_claims(self, tool: str, rules: str, analysers: list) -> str:
        kept = []
        for rule in (part.strip() for part in rules.split(",")):
            if not rule:
                continue
            if _self_superseding(tool, rule, analysers):
                sys.stderr.write(
                    f"craftsman: '{tool}' cannot supersede '{rule}' - a tool "
                    f"may not outrank its own verdicts; entry ignored\n"
                )
                continue
            kept.append(rule)
        return ",".join(kept)

    def _index_list(self, lang_id: str, capability: str, value) -> None:
        values = value if isinstance(value, list) else [value]
        for item in values:
            item = str(item).strip()
            if capability == "extensions":
                # Only extensions are normalised: a manifest may write `dart`
                # or `.dart`. Stripping the dot from every list turned
                # `.eslintrc.json` into `eslintrc.json`, so a declared protected
                # config silently stopped matching its own filename.
                item = item.lstrip(".")
                if not self._claim(item, lang_id):
                    continue
            _emit(lang_id, capability, item, self._pack_dir)

    def _claim(self, extension: str, lang_id: str) -> bool:
        """Two packs claiming one extension is a user-resolvable configuration
        error, not something to settle silently by load order."""
        owner = self._owners.get(extension)
        if owner and owner != lang_id:
            sys.stderr.write(
                f"craftsman: extension '{extension}' claimed by both "
                f"'{owner}' and '{lang_id}' - disable one pack\n"
            )
            self.conflicts += 1
            return False
        self._owners[extension] = lang_id
        return True


def build(paths: list[str]) -> int:
    indexer = _Indexer()
    for manifest_path in paths:
        if os.path.isfile(manifest_path):
            indexer.index_manifest(manifest_path)
    return 1 if indexer.conflicts else 0


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: lang_registry.py <pack.yml> [<pack.yml> ...]\n")
        return 2
    return build(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
