"""The pipeline: what happens next to a job.

`Pipeline.step` does every deterministic thing it can, then stops at the first
thing only a model or a human can do and says which. The orchestrating session
is a dispatcher: it runs `step`, spawns what the SPAWN lines name, and runs
`step` again when an agent returns. It decides nothing.

    intake -> [design] -> spec -> build -> gate -> review -> ready
                                    ^--------'--------'

Output lines, tab-separated:

    STATE  <job> <stage> <note>              a transition that just happened
    SPAWN  <job> <agent> <model> <name> <prompt>
    RUNNING <job> <stage> <agents>           nothing to do until those agents return
    WAIT   <job> <stage> <reason>            a human or an author must act
    DONE   <job> <stage>
"""
from __future__ import annotations

from pathlib import Path

from . import gate, scoring
from .base import MARKER, PACK_ROOT, PLUGIN_ROOT, Refused, body_after_header, first_line, git, header_value, \
    now, read_json, run, run_long, run_with_input, write_atomically
from .jobs import Jobs, TERMINAL

AGENT_PREFIX = 'craftsman:factory-'
BUILD_REFUSALS_ALLOWED = 1
SPAWN_ATTEMPTS = 2
DECISIONS = {'ACCEPT', 'NEEDS-INFO', 'REJECT', 'ESCALATE'}


class Delivery:
    """Getting a built branch to the forge: the push and the pull request are the script's, never the builder's."""

    def __init__(self, jobs: Jobs) -> None:
        self.jobs = jobs

    def deliver(self, job: dict) -> str:
        """Push the branch and open its pull request; '' or why it cannot be delivered."""
        worktree = job['worktree']
        if git(worktree, 'status', '--porcelain').strip():
            return 'the worktree has uncommitted changes; commit them or remove them.'
        if not git(worktree, 'rev-list', '--count', f'origin/{job["base"]}..HEAD').strip().lstrip('0'):
            return 'the branch has no commit of its own.'
        pushed = run(['git', 'push', '-u', 'origin', job['branch']], cwd=worktree, check=False)
        if pushed.returncode != 0:
            return (f'git push was refused ({pushed.stderr.strip()[:200]}). Never rewrite history on the job '
                    'branch: add commits on top of what is there.')
        return self._ensure_pull_request(job)

    def _ensure_pull_request(self, job: dict) -> str:
        existing = self.jobs.forge.pull_request(job['branch'])
        if existing is None:
            title = self._spec_title(job)
            body = f'{self.jobs.queue.closing_line(job["issue_ref"])}\n\n{MARKER}\nBuilt by the craftsman factory, job `{job["id"]}`.\n'
            created = run_with_input(['gh', 'pr', 'create', '--draft', '--base', job['base'], '--head', job['branch'],
                                      '--title', title, '--body-file', '-'], self.jobs.repo, body)
            existing = self.jobs.forge.pull_request(job['branch'])
            if existing is None:
                return f'the pull request could not be opened: {created.stdout.strip()[:200]}'
        job['pr'] = {'number': existing['number'], 'url': existing.get('url', '')}
        return ''

    def _spec_title(self, job: dict) -> str:
        for line in (self.jobs.folder(job) / 'spec.md').read_text().splitlines():
            if line.startswith('# '):
                return line[2:].strip()[:120]
        return job['issue_title'][:120]


class Pipeline:
    def __init__(self, jobs: Jobs) -> None:
        self.jobs = jobs
        self.lines: list[str] = []

    # -- output ------------------------------------------------------------

    def _say(self, kind: str, fields: list) -> None:
        self.lines.append('\t'.join([kind, *[str(field).replace('\t', ' ').replace('\n', ' ') for field in fields]]))

    def state(self, job: dict, note: str) -> None:
        self._say('STATE', [job['id'], job['stage'], note])

    def _wait(self, job: dict, reason: str) -> None:
        self._say('WAIT', [job['id'], job['stage'], reason])

    def header(self, job: dict) -> str:
        return (f'Job: {job["id"]}. Job folder: {self.jobs.folder(job)}/. Main checkout: {self.jobs.repo}. '
                f'Worktree: {job["worktree"]}. Branch: {job["branch"]}. Base: origin/{job["base"]}. '
                f'Issue: {job["issue_ref"]}.')

    def _spawn(self, job: dict, request: dict) -> bool:
        """Ask for an agent, once per run of it.

        While the agent runs, a second `step` asks for nothing. When it returned
        without its deliverable it is asked once more, then the job goes to a
        human. Returns True when the job was escalated, False otherwise.
        """
        key = request['key']
        name = f'{request["agent"]}-{job["id"]}' + request.get('suffix', '')
        previous = job.setdefault('spawned', {}).get(key)
        if previous and not previous.get('returned'):
            return False
        attempts = (previous or {}).get('attempts', 0) + 1
        if attempts > SPAWN_ATTEMPTS:
            return self._escalate(job, f'The {name} agent returned {SPAWN_ATTEMPTS} times without its deliverable.')
        job['spawned'][key] = {'at': now(), 'name': name, 'attempts': attempts}
        self.jobs.save(job)
        again = ' Your previous run ended without its deliverable: write it before anything else.' if attempts > 1 else ''
        self._say('SPAWN', [job['id'], AGENT_PREFIX + request['agent'], request.get('model', '-'), name,
                            f'{self.header(job)} {request["mission"]}{again}'])
        return False

    # -- entry point -------------------------------------------------------

    def step(self, job: dict, returned: str = '') -> list[str]:
        """Advance until an agent or a human is needed. `returned` names the agent that just came back."""
        for spawn in job.get('spawned', {}).values():
            if spawn.get('name') == returned:
                spawn['returned'] = True
        before = len(self.lines)
        for _ in range(12):
            handler = getattr(self, '_at_' + job['stage'].replace('-', '_'), None)
            if job['stage'] in TERMINAL or handler is None:
                self._say('DONE', [job['id'], job['stage']])
                break
            if not handler(job):
                break
        if len(self.lines) == before:
            running = sorted(spawn['name'] for spawn in job.get('spawned', {}).values() if not spawn.get('returned'))
            self._say('RUNNING', [job['id'], job['stage'], 'still running: ' + (', '.join(running) or 'nothing')])
        return self.lines

    def _escalate(self, job: dict, reason: str) -> bool:
        """Hand the job to a human, with the reason where they will read it."""
        write_atomically(self.jobs.folder(job) / 'escalation.md', f'ESCALATED: {now()}\n\n## Summary\n- {reason}\n')
        self.jobs.move(job, 'needs-human')
        self.jobs.queue.add_label(job['issue_ref'], self.jobs.config['queue']['needs_human_label'])
        message = f'{MARKER}\n**Craftsman factory: job `{job["id"]}` needs a human.**\n\n{reason}\n'
        if job.get('pr'):
            self.jobs.forge.comment(job['pr']['number'], message)
        else:
            self.jobs.queue.comment(job['issue_ref'], message)
        self.state(job, reason)
        return True

    # -- intake ------------------------------------------------------------

    def _at_intake(self, job: dict) -> bool:
        intake_file = self.jobs.folder(job) / 'intake.md'
        decision = header_value(intake_file, 'DECISION').upper()
        if decision not in DECISIONS:
            return self._spawn(job, {'key': 'intake', 'agent': 'intake',
                              'mission': 'Decide whether this issue is worth building and at what scope.'})
        job['intake'] = {
            'decision': decision, 'risk': header_value(intake_file, 'RISK').lower() or 'medium',
            'surfaces': [surface.strip().lower() for surface in header_value(intake_file, 'SURFACES').split(',')
                         if surface.strip().lower() not in ('', 'none')],
            'rescoped': header_value(intake_file, 'RESCOPED').lower() == 'yes',
            'spec': header_value(intake_file, 'SPEC').lower() or 'needed',
        }
        return getattr(self, '_intake_' + decision.lower().replace('-', '_'))(job, intake_file)

    def _intake_comment(self, job: dict, intake_file: Path) -> None:
        self.jobs.queue.comment(job['issue_ref'], f'{MARKER}\n{body_after_header(intake_file)}\n')

    def _intake_needs_info(self, job: dict, intake_file: Path) -> bool:
        self._intake_comment(job, intake_file)
        self.jobs.queue.add_label(job['issue_ref'], self.jobs.config['queue']['needs_info_label'])
        intake_file.rename(self.jobs.next_numbered(job, 'intake'))
        job['asked_at'] = now()
        self.jobs.move(job, 'needs-info')
        self.state(job, 'questions posted on the issue')
        return True

    def _intake_reject(self, job: dict, intake_file: Path) -> bool:
        self._intake_comment(job, intake_file)
        self.jobs.queue.remove_label(job['issue_ref'], self.jobs.config['queue']['label'])
        self.jobs.finish(job, 'rejected')
        self.state(job, 'rejected at intake')
        return True

    def _intake_escalate(self, job: dict, intake_file: Path) -> bool:
        return self._escalate(job, body_after_header(intake_file))

    def _intake_accept(self, job: dict, intake_file: Path) -> bool:
        self._intake_comment(job, intake_file)
        self.jobs.ensure_worktree(job)
        if job['intake']['spec'] == 'provided':
            return self._adopt_spec(job)
        self.jobs.move(job, 'design' if 'domain' in job['intake']['surfaces'] else 'spec')
        self.state(job, f'accepted, {job["intake"]["risk"]} risk')
        return True

    def _adopt_spec(self, job: dict) -> bool:
        """The issue carries its own spec: it is the spec, word for word."""
        issue = (self.jobs.folder(job) / 'issue.md').read_text()
        write_atomically(self.jobs.folder(job) / 'spec.md',
                         f'SOURCE: human\n\n## Summary\n- The specification is the issue itself, written by a human.\n\n{issue}')
        job['spec_source'] = 'human'
        self.jobs.move(job, 'spec')
        self.state(job, 'accepted, the issue is the spec')
        return True

    def _at_needs_info(self, job: dict) -> bool:
        issue = self.jobs.queue.fetch(job['issue_ref'])
        trusted = {issue.get('author', ''), self.jobs.queue.operator()} - {''}
        replies = [comment for comment in issue['comments']
                   if comment['author'] in trusted and MARKER not in comment['body']
                   and comment.get('created', '') > job.get('asked_at', '')]
        if not replies:
            self._wait(job, 'the author has not answered the questions on the issue')
            return False
        if self.jobs.free_slots() < 1:
            self._wait(job, 'answered, waiting for a free slot')
            return False
        self.jobs.write_issue(job, issue)
        self.jobs.queue.remove_label(job['issue_ref'], self.jobs.config['queue']['needs_info_label'])
        self.jobs.move(job, 'intake')
        self.state(job, 'the author answered')
        return True

    # -- design and spec ---------------------------------------------------

    def _at_design(self, job: dict) -> bool:
        if not (self.jobs.folder(job) / 'design.md').is_file():
            lens = PLUGIN_ROOT / scoring.routing()['surfaces']['domain']['lens']
            return self._spawn(job, {'key': 'design', 'agent': 'spec-writer', 'suffix': '-design',
                              'mission': f'Mode: design. Model the domain change and write design.md. Lens: {lens}.'})
        self.jobs.move(job, 'spec')
        self.state(job, 'design written')
        return True

    def _at_spec(self, job: dict) -> bool:
        if not (self.jobs.folder(job) / 'spec.md').is_file():
            return self._spawn(job, {'key': 'spec', 'agent': 'spec-writer', 'mission': 'Mode: spec. Write spec.md.'})
        job['spec_source'] = job.get('spec_source') or 'generated'
        failure = self._prepare_worktree(job)
        if failure:
            return self._escalate(job, failure)
        self.jobs.start_round(job)
        self.jobs.move(job, 'build')
        self.state(job, 'spec ready, build round 1')
        return True

    def _prepare_worktree(self, job: dict) -> str:
        """Run the configured setup commands; '' when the checkout is ready."""
        for command in self.jobs.config['setup']:
            result = run_long(['bash', '-c', command], job['worktree'], self.jobs.config['check_timeout_seconds'])
            if result.returncode != 0:
                tail = ' / '.join((result.stdout + result.stderr).strip().splitlines()[-3:])
                return f'Setup command `{command}` failed in the worktree (exit {result.returncode}): {tail}'
        return ''

    # -- build -------------------------------------------------------------

    def _build_mission(self, job: dict) -> str:
        folder, previous = self.jobs.folder(job), job['round'] - 1
        reason = f'Build round {job["round"]}.'
        if job.get('build_refusal'):
            return f'{reason} The factory refused your delivery: {job["build_refusal"]} Fix that, then rewrite build.md.'
        if job.get('feedback_file'):
            return f'{reason} A human gave feedback: read {job["feedback_file"]} first, it outranks the reviews.'
        if (folder / f'round-{previous}' / 'checks.md').is_file() and \
                first_line(folder / f'round-{previous}' / 'checks.md') == 'GATE: FAIL':
            return f'{reason} The gate failed: read round-{previous}/checks.md and checks.log, and fix what it names.'
        if previous >= 1:
            return f'{reason} Reviewers asked for changes: address every VERDICT: CHANGES in round-{previous}/.'
        return reason

    def _at_build(self, job: dict) -> bool:
        build_file = self.jobs.folder(job) / 'build.md'
        if header_value(build_file, 'ROUND') != str(job['round']):
            self.jobs.take_remote_commits(job)
            return self._spawn(job, {'key': f'build-{job["round"]}-{job.get("build_refusals", 0)}', 'agent': 'builder',
                              'mission': self._build_mission(job)})
        if first_line(build_file) != 'STATUS: READY':
            return self._escalate(job, 'The builder is blocked: ' + (body_after_header(build_file)[:600] or 'see build.md'))
        refusal = Delivery(self.jobs).deliver(job)
        if not refusal:
            job.pop('feedback_file', None)
            job.pop('build_refusal', None)
            job['build_refusals'] = 0
            self.jobs.move(job, 'gate')
            self.state(job, f'round {job["round"]} built and pushed')
            return True
        return self._refuse_build(job, refusal)

    def _refuse_build(self, job: dict, refusal: str) -> bool:
        """Send the delivery back once, with the reason; a second refusal is a human's."""
        job['build_refusals'] = job.get('build_refusals', 0) + 1
        if job['build_refusals'] > BUILD_REFUSALS_ALLOWED:
            return self._escalate(job, f'The build could not be delivered twice: {refusal}')
        job['build_refusal'] = refusal
        write_atomically(self.jobs.folder(job) / 'build.md', f'STATUS: REFUSED\nROUND: 0\n\n## Summary\n- {refusal}\n')
        self.jobs.save(job)
        return True

    # -- gate --------------------------------------------------------------

    def _at_gate(self, job: dict) -> bool:
        git(self.jobs.repo, 'fetch', 'origin', job['base'])
        result = gate.evaluate(job['worktree'], self.jobs.config)
        round_dir = self.jobs.round_dir(job)
        gate.write(result, round_dir)
        job['gate'] = {'passed': result['passed'], 'signature': result['signature'], 'round': job['round']}
        if result['passed']:
            job['reviewers'] = scoring.route(job['intake'] or {}, result['files'], self.jobs.config)
            self.jobs.move(job, 'review')
            self.state(job, 'gate PASS, reviewers: ' + ', '.join(reviewer['name'] for reviewer in job['reviewers']))
            return True
        return self._another_round(job, self._stuck(job, result) or 'gate FAIL')

    def _stuck(self, job: dict, result: dict) -> str:
        """Two rounds failing the same way: another one would spend, not progress."""
        previous = read_json(self.jobs.folder(job) / f'round-{job["round"] - 1}' / 'checks.json', {}) or {}
        if result['signature'] and previous.get('signature') == result['signature']:
            return 'no progress'
        return ''

    def _another_round(self, job: dict, why: str) -> bool:
        if why == 'no progress':
            return self._escalate(job, f'Round {job["round"]} failed the gate exactly as round {job["round"] - 1} did: '
                                       'see checks.md. Another round would spend without progress.')
        try:
            self.jobs.start_round(job)
        except Refused as budget:
            return self._escalate(job, f'{budget}; the last one ended on: {why}.')
        self.jobs.move(job, 'build')
        self.state(job, f'{why}, build round {job["round"]}')
        return True

    # -- review ------------------------------------------------------------

    def _at_review(self, job: dict) -> bool:
        round_dir = self.jobs.round_dir(job)
        reviews = scoring.read_reviews(round_dir, job['reviewers'])
        missing = [reviewer for reviewer in job['reviewers'] if reviewer['name'] not in reviews]
        for reviewer in missing:
            if self._spawn(job, self._review_request(job, reviewer)):
                return True
        if missing:
            return False
        if all(review['verdict'] == 'PASS' for review in reviews.values()):
            return self._make_ready(job, reviews)
        return self._another_round(job, 'reviewers asked for changes')

    def _review_request(self, job: dict, reviewer: dict) -> dict:
        target = self.jobs.round_dir(job) / f'review-{reviewer["name"]}.md'
        return {'key': f'review-{job["round"]}-{reviewer["name"]}', 'agent': 'reviewer', 'model': reviewer['model'],
                'suffix': f'-{reviewer["name"]}',
                'mission': f'Review round {job["round"]} as the {reviewer["name"]} reviewer. '
                           f'Lens: {PLUGIN_ROOT / reviewer["lens"]}. Write {target}.'}

    def _make_ready(self, job: dict, reviews: dict) -> bool:
        gate_result = read_json(self.jobs.round_dir(job) / 'checks.json', {}) or {}
        result = scoring.confidence(job, {'gate': gate_result, 'reviews': reviews}, self.jobs.config)
        label = self.jobs.config['review_labels'][result['level']]
        write_atomically(self.jobs.folder(job) / 'confidence.md', scoring.render(job, result, label))
        number = job['pr']['number']
        self.jobs.forge.mark_ready(number)
        self.jobs.forge.set_review_label(number, label)
        self.jobs.forge.comment(number, scoring.pull_request_comment(job, result, label))
        job['confidence'] = {'score': result['score'], 'level': result['level'], 'label': label}
        job['delivered_at'] = now()
        job['delivered_sha'] = git(job['worktree'], 'rev-parse', 'HEAD').strip()
        on_branch = git(job['worktree'], 'rev-list', f'origin/{job["base"]}..HEAD').split()
        job['factory_shas'] = [sha for sha in on_branch if sha not in job.get('human_shas', [])]
        self.jobs.move(job, 'ready')
        self.state(job, f'ready for review, confidence {result["score"]} ({result["level"]})')
        return True

    # -- waiting on a human ------------------------------------------------

    def _at_ready(self, job: dict) -> bool:
        confidence = job.get('confidence', {})
        self._wait(job, f'pull request {(job.get("pr") or {}).get("url", "")} awaits your review ({confidence.get("label", "")})')
        return False

    def _at_needs_human(self, job: dict) -> bool:
        summary = body_after_header(self.jobs.folder(job) / 'escalation.md') \
            if (self.jobs.folder(job) / 'escalation.md').is_file() else ''
        reason = ' '.join(line.lstrip('- ') for line in summary.splitlines() if line and not line.startswith('#'))
        self._wait(job, reason[:300] or 'a human decision is needed')
        return False


class Resync:
    """A delivered branch fell behind its base: merge the base in and judge it again."""

    def __init__(self, pipeline: Pipeline) -> None:
        self.pipeline = pipeline

    def run(self, job: dict) -> list[str]:
        """A delivered branch fell behind its base: merge the base in and judge it again."""
        if job['stage'] != 'ready':
            raise Refused(f'{job["id"]} is in stage {job["stage"]}; only a delivered job is resynchronised')
        self.pipeline.jobs.ensure_worktree(job)
        git(self.pipeline.jobs.repo, 'fetch', 'origin', job['base'])
        merged = run(['git', 'merge', '--no-edit', f'origin/{job["base"]}'], cwd=job['worktree'], check=False)
        job['resynced'] = True
        if merged.returncode != 0:
            run(['git', 'merge', '--abort'], cwd=job['worktree'], check=False)
            return self._conflict(job)
        run(['git', 'push', '-u', 'origin', job['branch']], cwd=job['worktree'])
        self.pipeline.jobs.start_round(job, fresh_budget=True)
        self.pipeline.jobs.move(job, 'gate')
        self.pipeline.state(job, f'resynchronised with origin/{job["base"]}, judging again')
        return self.pipeline.step(job)

    def _conflict(self, job: dict) -> list[str]:
        feedback = self.pipeline.jobs.next_numbered(job, 'feedback')
        write_atomically(feedback, f'SOURCE: factory\n\n## Summary\n- origin/{job["base"]} moved and merging it into '
                                   'this branch conflicts.\n- Merge it, resolve the conflicts without reformatting, '
                                   'and keep both sides\' intent.\n')
        job['feedback_file'] = str(feedback)
        self.pipeline.jobs.start_round(job, fresh_budget=True)
        self.pipeline.jobs.move(job, 'build')
        self.pipeline.state(job, f'origin/{job["base"]} conflicts with the branch, build round {job["round"]}')
        return self.pipeline.step(job)
