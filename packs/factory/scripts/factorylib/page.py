"""The factory's page: what waits on you, across every repository.

One self-contained HTML file in the plugin's data directory, rewritten after
every command. An open page reloads itself, so it is opened once and left
open. It is read-only on purpose: a button would need a local server
that writes job state, which is a second writer and an unauthenticated one.
A board: one column per step of the pipeline, a card per job. A card that
waits on a human keeps the column it stopped in and is marked. The detail of
a card, with the command to paste, opens in a side panel.

The data is embedded as JSON and rendered with `textContent` only: issue text
and review text are untrusted, and nothing they contain is ever parsed as HTML.
"""
from __future__ import annotations

import json
from pathlib import Path

from . import insight
from .base import (STATE_DIRNAME, Refused, data_dir, header_value, now, read_json, state_dir, write_atomically,
                   write_json)

ZONES = {'needs-info': 'questions', 'ready': 'review', 'needs-human': 'blocked',
         'merged': 'done', 'rejected': 'done', 'closed': 'done'}
FILE_ORDER = ('confidence.md', 'escalation.md', 'intake.md', 'design.md', 'spec.md', 'build.md')
FILE_LIMIT = 20000
REFRESH_RUNNING = 15  # seconds between two reloads of the open page while a job runs
REFRESH_IDLE = 60
COLUMNS = (('intake', 'Intake'), ('spec', 'Spec'), ('build', 'Build'), ('review', 'Review'),
           ('ready', 'To review'), ('done', 'Done'))
COLUMN_OF = {'intake': 'intake', 'needs-info': 'intake', 'design': 'spec', 'spec': 'spec', 'build': 'build',
             'gate': 'build', 'review': 'review', 'ready': 'ready', 'merged': 'done', 'rejected': 'done',
             'closed': 'done'}
ATTENTION = {'needs-info': 'question', 'needs-human': 'blocked', 'ready': 'review'}
DONE_SHOWN = 10


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


def _gate_failures(gate: dict) -> list[str]:
    """Why a round's gate failed, one short line per cause."""
    rules = gate.get('rules', {})
    causes = [f'{len(gate["protected"])} protected path(s) touched'] if gate.get('protected') else []
    if not rules.get('verdict', True):
        causes.append('the rules engine gave no verdict')
    if rules.get('blocking'):
        causes.append(f'{len(rules["blocking"])} blocking rule finding(s)')
    if gate.get('no_checks'):
        causes.append('no check configured')
    for check in gate.get('checks', []):
        if not check.get('passed'):
            causes.append(f'`{check["command"]}` ' + ('ran no test' if check.get('empty') else 'failed'))
    return causes


def _round(folder: Path) -> dict:
    """What one build round was judged: the gate's verdict, then each reviewer's."""
    gate = read_json(folder / 'checks.json', None)
    reviews = [{'name': path.stem[len('review-'):], 'passed': header_value(path, 'VERDICT').upper() == 'PASS'}
               for path in sorted(folder.glob('review-*.md')) if header_value(path, 'VERDICT')]
    return {'number': int(folder.name.rpartition('-')[2]), 'gate': None if gate is None else bool(gate.get('passed')),
            'failures': _gate_failures(gate or {}), 'reviews': reviews}


def _rounds(folder: Path) -> list[dict]:
    numbered = [path for path in folder.glob('round-*') if path.is_dir() and path.name.rpartition('-')[2].isdigit()]
    return sorted((_round(path) for path in numbered), key=lambda entry: entry['number'])


def _column(job: dict) -> str:
    """Where the card sits. A job that went to a human stays in the column it stopped in."""
    if job['stage'] != 'needs-human':
        return COLUMN_OF.get(job['stage'], 'intake')
    stopped = [entry.get('note', '').split(' -> ')[0] for entry in job.get('history', [])
               if entry.get('note', '').endswith('-> needs-human')]
    return COLUMN_OF.get(stopped[-1] if stopped else 'build', 'build')


def card(repo: Path, job: dict) -> dict:
    folder = state_dir(repo) / 'jobs' / job['id']
    intake = job.get('intake') or {}
    return {
        'id': job['id'], 'repo': repo.name, 'repo_path': str(repo), 'stage': job['stage'],
        'zone': ZONES.get(job['stage'], 'running'), 'title': job['issue_title'], 'issue': job['issue_ref'],
        'column': _column(job), 'attention': ATTENTION.get(job['stage'], ''),
        'finished_at': job.get('finished_at', ''),
        'issue_url': job.get('issue_url', ''), 'pr_url': (job.get('pr') or {}).get('url', ''),
        'risk': intake.get('risk', ''), 'surfaces': intake.get('surfaces', []),
        'rounds': job.get('rounds_total', 0), 'runs': _rounds(folder), 'confidence': job.get('confidence') or {},
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
               'thresholds': config['confidence']['thresholds'],
               'columns': [list(column) for column in COLUMNS], 'done_shown': DONE_SHOWN}
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
:root { --bg:#f6f5f2; --panel:#ffffff; --lane:#eeece7; --ink:#1d1c1a; --muted:#6b6862; --line:#dedbd4; --accent:#8a4b16;
  --skim:#2f6f4f; --standard:#8a6a12; --deep:#a33a2a; --running:#2c5f8a; --shade:rgba(20,18,16,0.35); }
@media (prefers-color-scheme: dark) { :root { --bg:#17161a; --panel:#211f24; --lane:#1c1b1f; --ink:#ebe8e2; --muted:#a09b93;
  --line:#37343b; --accent:#e0a36b; --skim:#6fc296; --standard:#dbb85a; --deep:#ef8a79; --running:#7fb4e0;
  --shade:rgba(0,0,0,0.55); } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, sans-serif; }
header { display:flex; align-items:center; gap:14px; flex-wrap:wrap; padding:16px 24px; border-bottom:1px solid var(--line); }
h1 { font-size:20px; margin:0; letter-spacing:-0.01em; }
h2 { font-size:13px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted); margin:28px 0 10px; }
.muted { color:var(--muted); font-size:13px; }
.spacer { flex:1; }
button, select { font:inherit; font-size:13px; color:var(--ink); background:var(--panel); border:1px solid var(--line);
  border-radius:999px; padding:4px 12px; cursor:pointer; }
button.mine { border-color:var(--accent); color:var(--accent); font-weight:600; }
button.mine[aria-pressed="true"] { background:var(--accent); color:var(--bg); }
button.mine:disabled { border-color:var(--line); color:var(--muted); font-weight:400; cursor:default; }
.board { display:flex; gap:12px; padding:16px 24px; overflow-x:auto; align-items:flex-start; }
.column { flex:0 0 250px; background:var(--lane); border:1px solid var(--line); border-radius:10px; padding:10px; }
.column h2 { margin:2px 4px 10px; display:flex; justify-content:space-between; }
.column h2 span { color:var(--ink); font-variant-numeric:tabular-nums; }
.card { background:var(--panel); border:1px solid var(--line); border-left:3px solid var(--line); border-radius:8px;
  padding:10px 12px; margin:0 0 8px; cursor:pointer; }
.card:hover, .card:focus-visible { border-color:var(--accent); outline:none; }
.card.question, .card.review { border-left-color:var(--accent); }
.card.blocked { border-left-color:var(--deep); }
.card h3 { margin:0 0 2px; font-size:14px; line-height:1.35; display:-webkit-box; -webkit-line-clamp:3;
  -webkit-box-orient:vertical; overflow:hidden; }
.row { display:flex; gap:6px; flex-wrap:wrap; align-items:center; font-size:12px; color:var(--muted); margin-top:6px; }
.chip { border:1px solid var(--line); border-radius:999px; padding:0 8px; font-size:11.5px; color:var(--ink); white-space:nowrap; }
.chip.skim { border-color:var(--skim); color:var(--skim); } .chip.standard { border-color:var(--standard); color:var(--standard); }
.chip.deep, .chip.stale, .chip.blocked { border-color:var(--deep); color:var(--deep); }
.chip.running { border-color:var(--running); color:var(--running); }
.chip.question, .chip.review { border-color:var(--accent); color:var(--accent); font-weight:600; }
.runs { margin-top:8px; border-top:1px solid var(--line); padding-top:6px; font-size:12px; }
.run { display:flex; gap:6px; flex-wrap:wrap; align-items:baseline; color:var(--muted); }
.run b { color:var(--ink); font-weight:600; min-width:22px; }
.ok { color:var(--skim); white-space:nowrap; } .ko { color:var(--deep); white-space:nowrap; font-weight:600; }
.wait { color:var(--running); white-space:nowrap; }
.why { color:var(--muted); font-size:12px; margin:0 0 4px 28px; }
a { color:var(--accent); }
.empty { color:var(--muted); font-size:13px; padding:2px 4px 6px; }
.more { width:100%; border-radius:8px; color:var(--muted); }
.shade { position:fixed; inset:0; background:var(--shade); display:none; }
.shade.open { display:block; }
aside { position:fixed; top:0; right:0; bottom:0; width:min(560px, 100%); background:var(--panel);
  border-left:1px solid var(--line); padding:18px 20px; overflow:auto; display:none; }
aside.open { display:block; }
aside h3 { margin:0 40px 6px 0; font-size:18px; line-height:1.3; }
aside .close { position:absolute; top:14px; right:16px; }
aside h4 { font-size:12px; text-transform:uppercase; letter-spacing:0.08em; color:var(--muted); margin:18px 0 6px; }
pre { white-space:pre-wrap; overflow-wrap:anywhere; background:var(--bg); border:1px solid var(--line); border-radius:6px;
  padding:10px 12px; font:12.5px/1.5 ui-monospace, monospace; margin:6px 0 0; max-height:420px; overflow:auto; }
code { font:12.5px ui-monospace, monospace; display:block; background:var(--bg); border:1px solid var(--line);
  border-radius:6px; padding:6px 10px; margin-top:6px; user-select:all; overflow-wrap:anywhere; }
details { margin-top:6px; } summary { cursor:pointer; color:var(--muted); font-size:13px; }
main { max-width:1100px; padding:0 24px 32px; }
table { border-collapse:collapse; width:100%; font-size:13px; } th, td { text-align:left; padding:6px 10px; border-bottom:1px solid var(--line); }
td.n, th.n { text-align:right; font-variant-numeric:tabular-nums; }
main .note { background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:10px 14px; margin:8px 0; }
@media (max-width: 640px) { header, .board { padding-left:16px; padding-right:16px; } main { padding:0 16px 24px; }
  .column { flex-basis:82vw; } }
</style>
</head>
<body>
<header><h1>Craftsman factory</h1><span class="muted" id="stamp"></span><span class="spacer"></span>
<select id="repo" aria-label="Repository" hidden></select><button class="mine" id="mine" aria-pressed="false"></button></header>
<div class="board" id="board"></div>
<main id="main"></main>
<div class="shade" id="shade"></div>
<aside id="panel" aria-label="Job detail"></aside>
<script type="application/json" id="data">__DATA__</script>
<script>
const data = JSON.parse(document.getElementById('data').textContent);
const board = document.getElementById('board');
const main = document.getElementById('main');
const panel = document.getElementById('panel');
const shade = document.getElementById('shade');
const mine = document.getElementById('mine');
const repoSelect = document.getElementById('repo');
const el = (tag, text, cls) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text;
  if (cls) node.className = cls; return node; };
const link = (text, url) => { const a = el('a', text); a.href = url; a.target = '_blank'; a.rel = 'noopener';
  a.addEventListener('click', (event) => event.stopPropagation()); return a; };
const safeUrl = (url) => String(url || '').startsWith('https://') || String(url || '').startsWith('http://');
const ATTENTION = { question: 'question for you', blocked: 'blocked', review: 'to review' };
const remembered = (key) => { try { return sessionStorage.getItem(key) || ''; } catch (error) { return ''; } };
const remember = (key, value) => { try { sessionStorage.setItem(key, value); } catch (error) { /* a private window */ } };
const view = { mine: remembered('mine') === '1', repo: remembered('repo'), allDone: false };
document.getElementById('stamp').textContent = 'written ' + data.written_at + ' · read-only · estimates, not a bill';

function chips(job) {
  const row = el('div', undefined, 'row');
  if (job.attention && job.attention !== 'review') row.append(el('span', ATTENTION[job.attention], 'chip ' + job.attention));
  else if (job.stage !== 'ready') row.append(el('span', job.stage, 'chip' + (job.zone === 'running' ? ' running' : '')));
  if (job.confidence && job.confidence.level) row.append(el('span', job.confidence.label + ' · ' + job.confidence.score, 'chip ' + job.confidence.level));
  if (job.stale) row.append(el('span', 'behind its base', 'chip stale'));
  if (job.rounds) row.append(el('span', job.rounds + (job.rounds > 1 ? ' rounds' : ' round'), 'chip'));
  if (job.risk) row.append(el('span', job.risk + ' risk', 'chip'));
  if (typeof job.cost === 'number') row.append(el('span', '~$' + job.cost.toFixed(2)));
  return row;
}

const mark = (label, passed) => el('span', (passed ? '✓ ' : '✗ ') + label, passed ? 'ok' : 'ko');

// One line per build round: what the gate said, then each reviewer. A word and a sign, never colour alone.
function runs(job, detailed) {
  const box = el('div', undefined, 'runs');
  (job.runs || []).forEach((run) => {
    const line = el('div', undefined, 'run');
    line.append(el('b', 'R' + run.number));
    line.append(run.gate === null ? el('span', '… building', 'wait') : mark('gate', run.gate));
    run.reviews.forEach((review) => line.append(mark(review.name, review.passed)));
    if (run.gate && !run.reviews.length && job.stage === 'review') line.append(el('span', '… review', 'wait'));
    box.append(line);
    if (detailed) run.failures.forEach((failure) => box.append(el('div', failure, 'why')));
  });
  return box;
}

function links(job) {
  const row = el('div', undefined, 'row');
  row.append(el('span', job.repo + ' · ' + job.issue));
  if (safeUrl(job.issue_url)) row.append(link('issue', job.issue_url));
  if (safeUrl(job.pr_url)) row.append(link('pull request', job.pr_url));
  return row;
}

function card(job) {
  const box = el('div', undefined, 'card' + (job.attention ? ' ' + job.attention : ''));
  box.tabIndex = 0; box.setAttribute('role', 'button');
  box.append(el('h3', job.title), links(job), chips(job));
  if ((job.runs || []).length) box.append(runs(job, false));
  box.addEventListener('click', () => openPanel(job));
  box.addEventListener('keydown', (event) => { if (event.key === 'Enter') openPanel(job); });
  return box;
}

function openPanel(job) {
  panel.replaceChildren();
  const close = el('button', 'Close', 'close'); close.addEventListener('click', closePanel);
  panel.append(close, el('h3', job.title), links(job), chips(job));
  (job.surfaces || []).length && panel.append(el('div', 'Surfaces: ' + job.surfaces.join(', '), 'muted'));
  panel.append(el('div', job.id + ' · ' + job.stage + (job.updated_at ? ' · updated ' + job.updated_at : ''), 'muted'));
  if ((job.runs || []).length) { panel.append(el('h4', 'Build rounds')); panel.append(runs(job, true)); }
  if (job.reason) { panel.append(el('h4', job.attention === 'question' ? 'Questions' : 'Why')); panel.append(el('pre', job.reason)); }
  if ((job.commands || []).length) { panel.append(el('h4', 'What you can do')); job.commands.forEach((command) => panel.append(el('code', command))); }
  if ((job.files || []).length) {
    panel.append(el('h4', 'Files this job wrote'));
    job.files.forEach((file) => { const inner = el('details'); inner.append(el('summary', file.name), el('pre', file.text)); panel.append(inner); });
  }
  panel.classList.add('open'); shade.classList.add('open'); close.focus();
}
function closePanel() { panel.classList.remove('open'); shade.classList.remove('open'); }
shade.addEventListener('click', closePanel);
document.addEventListener('keydown', (event) => { if (event.key === 'Escape') closePanel(); });

const score = (job) => (job.confidence || {}).score || 0;
const order = {
  ready: (a, b) => score(a) - score(b),
  done: (a, b) => String(b.finished_at || b.updated_at).localeCompare(String(a.finished_at || a.updated_at)),
  other: (a, b) => (b.attention ? 1 : 0) - (a.attention ? 1 : 0) || String(a.updated_at).localeCompare(String(b.updated_at)),
};

function column(key, title, jobs) {
  const lane = el('section', undefined, 'column');
  const heading = el('h2', title); heading.append(el('span', String(jobs.length))); lane.append(heading);
  jobs.sort(order[key] || order.other);
  const shown = key === 'done' && !view.allDone ? jobs.slice(0, data.done_shown) : jobs;
  shown.forEach((job) => lane.append(card(job)));
  if (!jobs.length) lane.append(el('div', '—', 'empty'));
  if (shown.length < jobs.length) {
    const more = el('button', 'Show all ' + jobs.length, 'more');
    more.addEventListener('click', () => { view.allDone = true; render(); }); lane.append(more);
  }
  return lane;
}

function render() {
  const inRepo = data.jobs.filter((job) => !view.repo || job.repo_path === view.repo);
  const waiting = inRepo.filter((job) => job.attention).length;
  if (!waiting) view.mine = false;
  mine.textContent = waiting ? waiting + ' waiting on you' : 'Nothing waits on you';
  mine.disabled = !waiting; mine.setAttribute('aria-pressed', String(view.mine));
  const visible = inRepo.filter((job) => !view.mine || job.attention);
  board.replaceChildren(...data.columns.map(([key, title]) => column(key, title, visible.filter((job) => job.column === key))));
}
mine.addEventListener('click', () => { view.mine = !view.mine; remember('mine', view.mine ? '1' : ''); render(); });

const repos = [...new Map(data.jobs.map((job) => [job.repo_path, job.repo])).entries()];
if (repos.length > 1) {
  repoSelect.hidden = false;
  repoSelect.append(new Option('All repositories', ''), ...repos.map(([path, name]) => new Option(name, path)));
  repoSelect.value = repos.some(([path]) => path === view.repo) ? view.repo : '';
  repoSelect.addEventListener('change', () => { view.repo = repoSelect.value; remember('repo', view.repo); render(); });
}
if (!repos.some(([path]) => path === view.repo)) view.repo = '';
render();

function table(headers, rows) {
  const node = el('table'); const head = el('tr');
  headers.forEach((header) => head.append(el('th', header.replace('#', ''), header.startsWith('#') ? 'n' : '')));
  node.append(head);
  rows.forEach((cells) => { const tr = el('tr'); cells.forEach((cell, index) => tr.append(el('td', String(cell), headers[index].startsWith('#') ? 'n' : ''))); node.append(tr); });
  return node;
}

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
    'Proposed, not applied: ' + proposal.threshold + ' threshold ' + proposal.from + ' → ' + proposal.to + ' (' + proposal.reason + '). Edit confidence.thresholds in .craftsman-factory/config.json to accept.', 'note')));
  if ((learning.recurring || []).length) main.append(table(['Recurring human remark', '#Jobs', '#Remarks'],
    learning.recurring.map((entry) => [entry.classification, entry.jobs, entry.remarks])));
  if ((learning.feedback || []).length) {
    const details = el('details'); details.append(el('summary', 'Latest human remarks (' + learning.feedback.length + ')'));
    details.append(table(['Job', 'Kind', 'Class', 'Remark'], learning.feedback.map((entry) =>
      [entry.job, entry.kind + (entry.path ? ' ' + entry.path : ''), entry.classification || 'unclassified', entry.body])));
    main.append(details);
  }
}

// The file is rewritten after every factory command: reload it, unless the reader has something open or selected.
const reading = () => panel.classList.contains('open') || document.querySelector('details[open]') || String(window.getSelection());
setInterval(() => { if (!document.hidden && !reading()) location.reload(); }, __REFRESH__ * 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden && !reading()) location.reload(); });
</script>
</body>
</html>
'''
