#!/usr/bin/env python3
"""Build native host entry points from the shared publisher metadata."""
import argparse
import json
from pathlib import Path


def manifests(root: Path) -> dict:
    source = json.loads((root / '.claude-plugin/plugin.json').read_text())
    codex = {key: value for key, value in source.items() if key != 'userConfig'}
    codex.update(skills='./skills', hooks='./hooks/hooks.json')
    grok = {key: value for key, value in source.items() if key != 'userConfig'}
    grok['hooks'] = './hooks/hooks.json'
    marketplace = json.loads((root / '.claude-plugin/marketplace.json').read_text())
    for entry in marketplace['plugins']:
        entry['source'] = {'type': 'local', 'path': './'}
    codex_catalog = {
        'name': marketplace['name'],
        'interface': {'displayName': 'AI Craftsman Superpowers'},
        'plugins': [{
            'name': source['name'],
            'source': {'source': 'local', 'path': './'},
            'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
            'category': 'Developer tools',
        }],
    }
    return {'.codex-plugin/plugin.json': codex, '.grok-plugin/plugin.json': grok,
            '.grok-plugin/marketplace.json': marketplace,
            '.agents/plugins/marketplace.json': codex_catalog}


def artifacts(root: Path) -> dict[Path, bytes]:
    result = {root / name: (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()
              for name, value in manifests(root).items()}
    result.update({root / 'agents' / source.name: source.read_bytes()
                   for source in sorted(root.glob('packs/*/agents/*.md'))})
    return result


def matches(target: Path, content: bytes) -> bool:
    return not target.is_symlink() and target.is_file() and target.read_bytes() == content


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if (args.root / 'plugin.json').exists():
        print('Root plugin.json masks native Codex hooks on 0.155.1; remove this portable entry point explicitly')
        return 1
    drift = []
    for target, content in artifacts(args.root).items():
        if args.check and not matches(target, content):
            drift.append(str(target.relative_to(args.root)))
        if args.check:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            target.unlink()
        target.write_bytes(content)
    if drift:
        print('Native manifest drift: ' + ', '.join(drift))
        return 1
    print('Native manifests match' if args.check else 'Native manifests written')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
