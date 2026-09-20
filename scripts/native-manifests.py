#!/usr/bin/env python3
"""Build native host entry points from the shared publisher metadata."""
import argparse
import json
from pathlib import Path


def manifests(root: Path) -> dict:
    source = json.loads((root / '.claude-plugin/plugin.json').read_text())
    portable = {key: value for key, value in source.items() if key != 'userConfig'}
    portable['$schema'] = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
    portable['extensions'] = {'com.openai': {'hooks': './hooks/hooks.json'}}
    grok = {key: value for key, value in source.items() if key != 'userConfig'}
    grok['hooks'] = './hooks/hooks.json'
    marketplace = json.loads((root / '.claude-plugin/marketplace.json').read_text())
    for entry in marketplace['plugins']:
        entry['source'] = {'type': 'local', 'path': './'}
    codex = {
        'name': marketplace['name'],
        'interface': {'displayName': 'AI Craftsman Superpowers'},
        'plugins': [{
            'name': source['name'],
            'source': {'source': 'local', 'path': './'},
            'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
            'category': 'Developer tools',
        }],
    }
    return {'plugin.json': portable, '.grok-plugin/plugin.json': grok,
            '.grok-plugin/marketplace.json': marketplace,
            '.agents/plugins/marketplace.json': codex}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    drift = []
    for name, value in manifests(args.root).items():
        target = args.root / name
        content = json.dumps(value, indent=2, ensure_ascii=False) + '\n'
        if args.check:
            if not target.is_file() or target.read_text() != content:
                drift.append(name)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    if drift:
        print('Native manifest drift: ' + ', '.join(drift))
        return 1
    print('Native manifests match' if args.check else 'Native manifests written')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
