"""Job state: one directory per job, one writer, and a table of legal moves.

`job.json` is written here and nowhere else. A stage changes only through
`Jobs.move`, which refuses anything `TRANSITIONS` does not list: the
orchestrating session cannot improvise a state, and a run that died resumes
from what the files say.
"""
from __future__ import annotations

import re
from pathlib import Path

from .adapters import forge_for, queue_for, render_issue
from .base import Refused, git, load_config, now, read_json, state_dir, write_atomically, write_json

TRANSITIONS = {
    'intake': {'needs-info', 'rejected', 'needs-human', 'design', 'spec', 'build'},
    'needs-info': {'intake', 'rejected'},
    'design': {'spec', 'needs-human'},
    'spec': {'build', 'needs-human'},
    'build': {'gate', 'needs-human'},
    'gate': {'review', 'build', 'needs-human'},
    'review': {'ready', 'build', 'needs-human'},
    'ready': {'build', 'gate', 'rejected'},
    'needs-human': {'build', 'rejected'},
}
RUNNING = ('intake', 'design', 'spec', 'build', 'gate', 'review')
WAITING = ('needs-info', 'needs-human', 'ready')
TERMINAL = ('merged', 'rejected', 'closed')
EXCLUDE_LINE = '/.craftsman-factory/'


def slug(title: str) -> str:
    words = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-').split('-')
    return '-'.join(words[:5])[:40].strip('-') or 'job'


class Jobs:
    def __init__(self, repo: Path) -> None:
        self.repo = repo
        self.config = load_config(repo)
        self.root = state_dir(repo)
        self.jobs_dir = self.root / 'jobs'
        self._queue = None
        self._forge = None

    @property
    def queue(self) -> object:
        if self._queue is None:
            self._queue = queue_for(self.repo, self.config)
        return self._queue

    @property
    def forge(self) -> object:
        if self._forge is None:
            self._forge = forge_for(self.repo, self.config)
        return self._forge

    @property
    def base(self) -> str:
        return self.config['forge']['base_branch']

    def folder(self, job: dict) -> Path:
        return self.jobs_dir / job['id']

    def round_dir(self, job: dict) -> Path:
        return self.folder(job) / f'round-{job["round"]}'

    def all(self) -> list[dict]:
        if not self.jobs_dir.is_dir():
            return []
        loaded = (read_json(path / 'job.json') for path in sorted(self.jobs_dir.iterdir()))
        return [job for job in loaded if isinstance(job, dict)]

    def resolve(self, reference: str) -> dict:
        """A job by its id, or by the reference of its issue."""
        matches = [job for job in self.all() if reference in (job['id'], job['issue_ref'])]
        if not matches:
            raise Refused(f'no job matches {reference!r}')
        return matches[-1]

    def save(self, job: dict) -> None:
        job['updated_at'] = now()
        write_json(self.folder(job) / 'job.json', job)

    def note(self, job: dict, text: str) -> None:
        job.setdefault('history', []).append({'at': now(), 'stage': job['stage'], 'note': text})

    def move(self, job: dict, target: str) -> None:
        """The only place a stage changes."""
        current = job['stage']
        if target not in TRANSITIONS.get(current, ()):
            raise Refused(f'{job["id"]}: {current} -> {target} is not a legal move')
        job['stage'] = target
        job['spawned'] = {}
        self.note(job, f'{current} -> {target}')
        self.save(job)

    def finish(self, job: dict, outcome: str) -> None:
        """merged, rejected or closed: reachable from any unfinished stage."""
        if outcome not in TERMINAL:
            raise Refused(f'{outcome!r} is not a way for a job to end')
        self.note(job, f'{job["stage"]} -> {outcome}')
        job['stage'] = outcome
        job['spawned'] = {}
        job['finished_at'] = now()
        self.save(job)
        self.drop_worktree(job)

    def free_slots(self) -> int:
        running = sum(1 for job in self.all() if job['stage'] in RUNNING)
        return max(0, int(self.config['concurrency']) - running)

    def _next_id(self, title: str) -> str:
        numbers = [int(job['id'].split('-')[0]) for job in self.all() if job['id'].split('-')[0].isdigit()]
        return f'{max(numbers, default=0) + 1:03d}-{slug(title)}'

    def create(self, reference: str) -> dict:
        open_jobs = [job for job in self.all() if job['issue_ref'] == reference and job['stage'] not in TERMINAL]
        if open_jobs:
            raise Refused(f'issue {reference} already has job {open_jobs[0]["id"]} in stage {open_jobs[0]["stage"]}')
        if self.free_slots() < 1:
            raise Refused(f'no free slot: {self.config["concurrency"]} job(s) already running')
        issue = self.queue.fetch(reference)
        label = self.config['queue']['label']
        if label not in issue['labels']:
            raise Refused(f'issue {reference} does not carry the `{label}` label: the label is the trust boundary')
        if issue.get('state') == 'closed':
            raise Refused(f'issue {reference} is closed')
        identifier = self._next_id(issue['title'])
        job = {
            'id': identifier, 'issue_ref': issue['ref'], 'issue_title': issue['title'],
            'issue_url': issue.get('url', ''), 'queue': self.queue.kind, 'stage': 'intake',
            'round': 0, 'round_budget_end': 0, 'rounds_total': 0, 'branch': f'factory/{identifier}',
            'worktree': str(self.root / 'worktrees' / identifier), 'base': self.base, 'pr': None,
            'intake': None, 'spec_source': '', 'reviewers': [], 'spawned': {}, 'history': [],
            'created_at': now(),
        }
        self.write_issue(job, issue)
        self.note(job, 'created')
        self.save(job)
        return job

    def write_issue(self, job: dict, issue: dict) -> None:
        write_atomically(self.folder(job) / 'issue.md', render_issue(issue, self.queue.operator()))

    def ensure_excluded(self) -> None:
        """Keep the factory's directory out of `git status` without committing anything."""
        common = git(self.repo, 'rev-parse', '--path-format=absolute', '--git-common-dir').strip()
        exclude = Path(common) / 'info' / 'exclude'
        current = exclude.read_text() if exclude.is_file() else ''
        if EXCLUDE_LINE in current.splitlines():
            return
        exclude.parent.mkdir(parents=True, exist_ok=True)
        exclude.write_text(current + ('' if current.endswith('\n') or not current else '\n') + EXCLUDE_LINE + '\n')

    def ensure_worktree(self, job: dict) -> None:
        if Path(job['worktree']).is_dir():
            return
        self.ensure_excluded()
        git(self.repo, 'fetch', 'origin', self.base)
        existing = git(self.repo, 'branch', '--list', job['branch']).strip()
        arguments = [job['worktree'], job['branch']] if existing else \
            [job['worktree'], '-b', job['branch'], f'origin/{self.base}']
        git(self.repo, 'worktree', 'add', *arguments)

    def drop_worktree(self, job: dict) -> None:
        if Path(job['worktree']).is_dir():
            git(self.repo, 'worktree', 'remove', '--force', job['worktree'], check=False)
        git(self.repo, 'worktree', 'prune', check=False)

    def take_remote_commits(self, job: dict) -> None:
        """Bring in what a human pushed on the job branch, and remember it was theirs.

        A reviewer who fixes something on the pull request and then asks for
        more would otherwise see the next push refused, or their commits
        counted as the factory's when the outcome is measured.
        """
        worktree, remote = job['worktree'], f'origin/{job["branch"]}'
        if not Path(worktree).is_dir():
            return
        git(self.repo, 'fetch', 'origin', job['branch'], check=False)
        theirs = git(worktree, 'rev-list', f'HEAD..{remote}', check=False).split()
        if not theirs:
            return
        job['human_shas'] = sorted({*job.get('human_shas', []), *theirs})
        git(worktree, 'merge', '--ff-only', remote, check=False)

    def start_round(self, job: dict, fresh_budget: bool = False) -> None:
        """The next build round, or a refusal when the budget is spent."""
        following = job['round'] + 1
        if fresh_budget or not job['round_budget_end']:
            job['round_budget_end'] = following + int(self.config['max_rounds']) - 1
        if following > job['round_budget_end']:
            raise Refused(f'{job["id"]} has used its {self.config["max_rounds"]} build round(s)')
        job['round'] = following
        job['rounds_total'] = job.get('rounds_total', 0) + 1
        self.round_dir(job).mkdir(parents=True, exist_ok=True)

    def next_numbered(self, job: dict, stem: str) -> Path:
        """feedback-1.md, feedback-2.md, ...: the first name not taken."""
        number = 1
        while (self.folder(job) / f'{stem}-{number}.md').exists():
            number += 1
        return self.folder(job) / f'{stem}-{number}.md'
