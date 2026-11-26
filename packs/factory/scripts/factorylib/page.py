"""The factory's page: what waits on you, across every repository.

One self-contained HTML file in the plugin's data directory, rewritten after
every command. An open page reloads itself, so it is opened once and left
open. It is read-only on purpose: a button would need a local server
that writes job state, which is a second writer and an unauthenticated one.
Each card carries the link to its pull request and the command to paste.

The data is embedded as JSON and rendered with `textContent` only: issue text
and review text are untrusted, and nothing they contain is ever parsed as HTML.
"""
from __future__ import annotations

import json
from pathlib import Path

from . import insight
from .base import STATE_DIRNAME, Refused, data_dir, now, read_json, state_dir, write_atomically, write_json

ZONES = {'needs-info': 'questions', 'ready': 'review', 'needs-human': 'blocked',
         'merged': 'done', 'rejected': 'done', 'closed': 'done'}
FILE_ORDER = ('confidence.md', 'escalation.md', 'intake.md', 'design.md', 'spec.md', 'build.md')
FILE_LIMIT = 20000
REFRESH_RUNNING = 15  # seconds between two reloads of the open page while a job runs
REFRESH_IDLE = 60


def _files(folder: Path) -> list[dict]:
    """Every markdown file of a job, the ones a human reads first on top."""
    paths = sorted(folder.rglob('*.md'), key=lambda path: (
        FILE_ORDER.index(path.name) if path.name in FILE_ORDER else len(FILE_ORDER), str(path)))
    return [{'name': str(path.relative_to(folder)), 'text': path.read_text(errors='replace')[:FILE_LIMIT]}
            for path in paths]


def _reason(folder: Path, job: dict) -> str:
    source = {'needs-human': 'escalation.md', 'ready': 'confidence.md'}.get(job['stage'])
    if job['stage'] == 'needs-info':
        asked = sorted(folder.glob('intake-*.md'))
        source = asked[-1].name if asked else None
    if not source or not (folder / source).is_file():
        return ''
    return (folder / source).read_text(errors='replace').partition('\n\n')[2][:1200]


def _commands(job: dict) -> list[str]:
    stage = job['stage']
    if stage == 'needs-info':
        return [f'/craftsman:factory answer {job["id"]}: <your answer>']
    if stage in ('ready', 'needs-human'):
        return [f'/craftsman:factory feedback {job["id"]}: <what to change>',
                f'/craftsman:factory reject {job["id"]}: <why>',
                f'cd {job["worktree"]}  # then /craftsman:workflow --from implement, to take over by hand']
    return []


def card(repo: Path, job: dict) -> dict:
    folder = state_dir(repo) / 'jobs' / job['id']
    intake = job.get('intake') or {}
    return {
        'id': job['id'], 'repo': repo.name, 'repo_path': str(repo), 'stage': job['stage'],
        'zone': ZONES.get(job['stage'], 'running'), 'title': job['issue_title'], 'issue': job['issue_ref'],
        'issue_url': job.get('issue_url', ''), 'pr_url': (job.get('pr') or {}).get('url', ''),
        'risk': intake.get('risk', ''), 'surfaces': intake.get('surfaces', []),
        'rounds': job.get('rounds_total', 0), 'confidence': job.get('confidence') or {},
        'stale': bool(job.get('stale')), 'cost': (job.get('cost') or {}).get('usd'),
        'updated_at': job.get('updated_at', ''), 'reason': _reason(folder, job),
        'commands': _commands(job), 'files': _files(folder),
    }


def write_index(repo: Path, jobs: list[dict]) -> None:
    write_json(state_dir(repo) / 'index.json', {'repo': str(repo), 'written_at': now(),
                                               'jobs': [card(repo, job) for job in jobs]})


def register(repo: Path) -> None:
    listing = data_dir() / 'repos.json'
    known = read_json(listing, []) or []
    if str(repo) not in known:
        write_json(listing, sorted({*known, str(repo)}))


def _learning(config: dict) -> dict:
    try:
        return {'levels': insight.levels(), 'proposals': insight.proposals(config),
                'recurring': insight.recurring(), 'feedback': insight.feedback_rows()}
    except Refused as error:
        return {'error': str(error)}


def build(config: dict) -> Path:
    """Rewrite the page from every registered repository's index."""
    cards = []
    for repo in read_json(data_dir() / 'repos.json', []) or []:
        index = read_json(Path(repo) / STATE_DIRNAME / 'index.json', {}) or {}
        cards += index.get('jobs', [])
    payload = {'written_at': now(), 'jobs': cards, 'learning': _learning(config),
               'thresholds': config['confidence']['thresholds']}
    embedded = json.dumps(payload, ensure_ascii=False).replace('<', '\\u003c')
    target = data_dir() / 'index.html'
    running = any(job['zone'] == 'running' for job in cards)
    payload_refresh = str(REFRESH_RUNNING if running else REFRESH_IDLE)
    write_atomically(target, TEMPLATE.replace('__REFRESH__', payload_refresh).replace('__DATA__', embedded))
    return target


TEMPLATE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Craftsman factory</title>
<style>
:root { --bg:#f6f5f2; --panel:#ffffff; --ink:#1d1c1a; --muted:#6b6862; --line:#dedbd4; --accent:#8a4b16;
  --skim:#2f6f4f; --standard:#8a6a12; --deep:#a33a2a; --running:#2c5f8a; }
@media (prefers-color-scheme: dark) { :root { --bg:#17161a; --panel:#211f24; --ink:#ebe8e2; --muted:#a09b93;
  --line:#37343b; --accent:#e0a36b; --skim:#6fc296; --standard:#dbb85a; --deep:#ef8a79; --running:#7fb4e0; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, sans-serif; }
header, main { max-width:1100px; margin:0 auto; padding:20px 24px; }
header { display:flex; align-items:baseline; gap:16px; flex-wrap:wrap; border-bottom:1px solid var(--line); }
h1 { font-size:20px; margin:0; letter-spacing:-0.01em; }
h2 { font-size:13px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted); margin:28px 0 10px; }
h2 span { color:var(--ink); }
.muted { color:var(--muted); font-size:13px; }
.yours { border-left:3px solid var(--accent); padding-left:16px; }
.card { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px 16px; margin:0 0 10px; }
.card h3 { margin:0 0 4px; font-size:16px; }
.row { display:flex; gap:8px; flex-wrap:wrap; align-items:center; font-size:13px; color:var(--muted); }
.chip { border:1px solid var(--line); border-radius:999px; padding:1px 9px; font-size:12px; color:var(--ink); }
.chip.skim { border-color:var(--skim); color:var(--skim); } .chip.standard { border-color:var(--standard); color:var(--standard); }
.chip.deep, .chip.stale { border-color:var(--deep); color:var(--deep); } .chip.running { border-color:var(--running); color:var(--running); }
a { color:var(--accent); }
pre { white-space:pre-wrap; overflow-wrap:anywhere; background:var(--bg); border:1px solid var(--line); border-radius:6px;
  padding:10px 12px; font:12.5px/1.5 ui-monospace, monospace; margin:8px 0 0; max-height:420px; overflow:auto; }
code { font:12.5px ui-monospace, monospace; display:block; background:var(--bg); border:1px solid var(--line);
  border-radius:6px; padding:6px 10px; margin-top:6px; user-select:all; overflow-wrap:anywhere; }
details { margin-top:8px; } summary { cursor:pointer; color:var(--muted); font-size:13px; }
table { border-collapse:collapse; width:100%; font-size:13px; } th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); }
td.n, th.n { text-align:right; font-variant-numeric:tabular-nums; }
.empty { color:var(--muted); font-size:13px; padding:4px 0 8px; }
</style>
</head>
<body>
<header><h1>Craftsman factory</h1><span class="muted" id="stamp"></span></header>
<main id="main"></main>
<script type="application/json" id="data">__DATA__</script>
<script>
const data = JSON.parse(document.getElementById('data').textContent);
const main = document.getElementById('main');
const el = (tag, text, cls) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text;
  if (cls) node.className = cls; return node; };
const link = (text, url) => { const a = el('a', text); a.href = url; a.target = '_blank'; a.rel = 'noopener'; return a; };
const safeUrl = (url) => /^https?:\\/\\//.test(url || '');
document.getElementById('stamp').textContent = 'written ' + data.written_at + ' · read-only · estimates, not a bill';

function card(job) {
  const box = el('div', undefined, 'card');
  box.append(el('h3', job.title));
  const row = el('div', undefined, 'row');
  row.append(el('span', job.repo + ' · ' + job.id + ' · issue ' + job.issue));
  if (job.confidence && job.confidence.level) row.append(el('span', job.confidence.label + ' · ' + job.confidence.score, 'chip ' + job.confidence.level));
  if (job.zone === 'running') row.append(el('span', job.stage, 'chip running'));
  if (job.zone === 'done') row.append(el('span', job.stage, 'chip'));
  if (job.stale) row.append(el('span', 'behind its base', 'chip stale'));
  if (job.risk) row.append(el('span', job.risk + ' risk', 'chip'));
  (job.surfaces || []).forEach((surface) => row.append(el('span', surface, 'chip')));
  if (job.rounds) row.append(el('span', job.rounds + ' round' + (job.rounds > 1 ? 's' : '')));
  if (typeof job.cost === 'number') row.append(el('span', '~$' + job.cost.toFixed(2)));
  if (safeUrl(job.pr_url)) row.append(link('pull request', job.pr_url));
  if (safeUrl(job.issue_url)) row.append(link('issue', job.issue_url));
  box.append(row);
  if (job.reason && job.zone !== 'done' && job.zone !== 'running') box.append(el('pre', job.reason));
  (job.commands || []).forEach((command) => box.append(el('code', command)));
  if (job.files && job.files.length) {
    const details = el('details'); details.append(el('summary', job.files.length + ' file(s) this job wrote'));
    job.files.forEach((file) => { const inner = el('details'); inner.append(el('summary', file.name)); inner.append(el('pre', file.text)); details.append(inner); });
    box.append(details);
  }
  return box;
}

function zone(title, key, emptyText, parent) {
  const jobs = data.jobs.filter((job) => job.zone === key);
  const heading = el('h2', title + ' '); heading.append(el('span', String(jobs.length))); parent.append(heading);
  if (!jobs.length) parent.append(el('div', emptyText, 'empty'));
  jobs.sort((a, b) => ((a.confidence || {}).score || 0) - ((b.confidence || {}).score || 0)).forEach((job) => parent.append(card(job)));
}

function table(headers, rows) {
  const node = el('table'); const head = el('tr');
  headers.forEach((header) => head.append(el('th', header.replace(/^#/, ''), header.startsWith('#') ? 'n' : '')));
  node.append(head);
  rows.forEach((cells) => { const tr = el('tr'); cells.forEach((cell, index) => tr.append(el('td', String(cell), headers[index].startsWith('#') ? 'n' : ''))); node.append(tr); });
  return node;
}

const yours = el('section', undefined, 'yours');
zone('Questions for you', 'questions', 'No job is waiting for an answer.', yours);
zone('To review, lowest confidence first', 'review', 'No pull request is waiting for you.', yours);
zone('Blocked', 'blocked', 'Nothing is blocked.', yours);
main.append(yours);
zone('Running', 'running', 'Nothing is running.', main);

const learning = data.learning || {};
main.append(el('h2', 'What the factory learned'));
if (learning.error) main.append(el('div', 'Not available: ' + learning.error, 'empty'));
else {
  const levels = learning.levels || {};
  const rows = ['skim', 'standard', 'deep'].filter((level) => levels[level]).map((level) =>
    [level, levels[level].delivered, levels[level].corrected, Math.round(100 * levels[level].corrected / levels[level].delivered) + '%']);
  if (rows.length) main.append(table(['Review depth', '#Closed or merged', '#Corrected by a human', '#Rate'], rows));
  else main.append(el('div', 'No delivered job has been merged or closed yet: nothing to compare the confidence score with.', 'empty'));
  (learning.proposals || []).forEach((proposal) => main.append(el('div',
    'Proposed, not applied: ' + proposal.threshold + ' threshold ' + proposal.from + ' → ' + proposal.to + ' (' + proposal.reason + '). Edit confidence.thresholds in .craftsman-factory/config.json to accept.', 'card')));
  if ((learning.recurring || []).length) main.append(table(['Recurring human remark', '#Jobs', '#Remarks'],
    learning.recurring.map((entry) => [entry.classification, entry.jobs, entry.remarks])));
  if ((learning.feedback || []).length) {
    const details = el('details'); details.append(el('summary', 'Latest human remarks (' + learning.feedback.length + ')'));
    details.append(table(['Job', 'Kind', 'Class', 'Remark'], learning.feedback.map((entry) =>
      [entry.job, entry.kind + (entry.path ? ' ' + entry.path : ''), entry.classification || 'unclassified', entry.body])));
    main.append(details);
  }
}
zone('Done', 'done', 'No job has finished yet.', main);

// The file is rewritten after every factory command: reload it, unless the reader has something open or selected.
const reading = () => document.querySelector('details[open]') || String(window.getSelection());
setInterval(() => { if (!document.hidden && !reading()) location.reload(); }, __REFRESH__ * 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden && !reading()) location.reload(); });
</script>
</body>
</html>
'''
