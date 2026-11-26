"""craftsman-factory - the deterministic spine of the craftsman factory.

Usage:
  craftsman-factory init [--queue github|linear] [--team KEY]
                                     observe the repository, write the config, create the labels
  craftsman-factory queue            what to do with each labelled issue and each open job
  craftsman-factory create <issue>   a new job for a labelled issue; prints the job id
  craftsman-factory step <job> [--returned <agent name>] [--resume]
                                     advance a job as far as scripts can; prints SPAWN/WAIT/DONE lines.
                                     --returned names the agent that just came back; --resume forgets
                                     which agents a dead session had started
  craftsman-factory resync <job>     merge the base into a delivered branch and judge it again
  craftsman-factory feedback <job>   a human's feedback on stdin; starts a new build round
  craftsman-factory answer <job>     a human's answer on stdin; posted on the issue
  craftsman-factory reject <job>     a human's reason on stdin; closes the job and its pull request
  craftsman-factory check            run the gate on the current worktree, write nothing
  craftsman-factory summary [<job>...]
  craftsman-factory learn [--classify]
                                     outcomes, calibration proposals; --classify spends one Haiku call
  craftsman-factory page [--open]    rewrite the page; print its path

<job> is a job id (004-dark-mode) or the reference of its issue (12, LIN-34).
Every state change happens here. The orchestrating session spawns agents and
runs these commands; it never edits a job file.
"""
from __future__ import annotations

import os
import shutil
import sys
import webbrowser
from pathlib import Path

from . import gate, insight, page, registry
from .base import MARKER, STATE_DIRNAME, Refused, git, load_config, repo_root, state_dir, write_atomically, write_json
from .jobs import RUNNING, TERMINAL, Jobs
from .pipeline import Pipeline, Resync

STALE_STATES = ('BEHIND', 'DIRTY')


# -- init -------------------------------------------------------------------

def _runnable(command: str, repo: Path) -> bool:
    program = command.split()[0]
    return (repo / program).is_file() or shutil.which(program) is not None


def _detected_checks(repo: Path) -> list[str]:
    """One test command per language the repository holds, taken from the packs' manifests."""
    markers = registry.capability_by_language('entry_markers')
    commands = registry.capability_by_language('test_commands')
    found = []
    for language, candidates in commands.items():
        if not any((repo / marker).exists() for marker in markers.get(language, [])):
            continue
        runnable = [command for command in candidates if _runnable(command, repo)]
        found += runnable[:1]
    return list(dict.fromkeys(found))


def _default_branch(repo: Path) -> str:
    head = git(repo, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD', check=False).strip()
    return head.split('/', 1)[1] if '/' in head else 'main'


def _option(arguments: list[str], name: str) -> str:
    return arguments[arguments.index(name) + 1] if name in arguments and arguments.index(name) + 1 < len(arguments) else ''


def command_init(repo: Path, arguments: list[str]) -> int:
    target = state_dir(repo) / 'config.json'
    kind = _option(arguments, '--queue') or 'github'
    if kind not in ('github', 'linear'):
        raise Refused('--queue takes github or linear')
    if not target.is_file():
        transport = 'api' if os.environ.get('LINEAR_API_KEY') else 'mcp'
        write_json(target, {
            'queue': {'kind': kind, 'linear': {'team': _option(arguments, '--team'), 'transport': transport}},
            'forge': {'base_branch': _default_branch(repo)},
            'checks': _detected_checks(repo), 'setup': [],
        })
    jobs = Jobs(repo)
    jobs.ensure_excluded()
    settings = jobs.config['queue']
    jobs.queue.ensure_labels([settings['label'], settings['needs_info_label'], settings['needs_human_label']])
    jobs.forge.ensure_labels()
    page.register(repo)
    print(f'config: {target}')
    print(f'queue: {settings["kind"]}' + (f' ({settings["linear"]["transport"]})' if settings['kind'] == 'linear' else ''))
    print(f'base branch: {jobs.base}')
    print('checks: ' + (' ; '.join(jobs.config['checks']) or 'NONE - the gate fails every job until `checks` is filled'))
    print('setup: ' + (' ; '.join(jobs.config['setup']) or 'none (add the commands a fresh checkout needs)'))
    return 0


# -- measures ---------------------------------------------------------------

def _measure(jobs: Jobs, job: dict) -> None:
    """Cost and outcome of a job. A measure that fails never fails the command."""
    try:
        job['cost'] = insight.cost(jobs.folder(job), jobs.config)
        measured = {}
        if job.get('pr') and job.get('delivered_at'):
            feedback = [path for path in jobs.folder(job).glob('feedback-*.md')
                        if not path.read_text().startswith('SOURCE: factory')]
            measured = insight.outcome(job, jobs.forge.activity(job['pr']['number']), len(feedback))
        if job['stage'] in TERMINAL:
            measured['outcome'] = job['stage']
        insight.record(jobs.repo, job, measured)
    except Refused as error:
        job['measure_error'] = str(error)
    jobs.save(job)


def _refresh(jobs: Jobs, job: dict) -> None:
    """Follow what happened to the job's pull request since the last run."""
    pull = jobs.forge.pull_request(job['branch']) if job.get('pr') else None
    if pull is None:
        return
    state = pull.get('state', '')
    if state in ('MERGED', 'CLOSED'):
        _measure(jobs, job)
        jobs.queue.remove_label(job['issue_ref'], jobs.config['queue']['label'])
        jobs.queue.remove_label(job['issue_ref'], jobs.config['queue']['needs_human_label'])
        jobs.finish(job, 'merged' if state == 'MERGED' else 'closed')
        _measure(jobs, job)
        return
    job['stale'] = job['stage'] == 'ready' and pull.get('mergeStateStatus') in STALE_STATES
    jobs.save(job)
    if job['stage'] == 'ready':
        _measure(jobs, job)


# -- queue ------------------------------------------------------------------

def _job_line(job: dict) -> str:
    if job['stage'] in RUNNING:
        return f'resume\t{job["issue_ref"]}\t{job["id"]}\t{job["stage"]}\trun `step {job["id"]} --resume`'
    if job.get('stale'):
        return f'resync\t{job["issue_ref"]}\t{job["id"]}\t{job["stage"]}\tthe base moved: run `resync {job["id"]}`'
    if job['stage'] == 'needs-info':
        return f'check\t{job["issue_ref"]}\t{job["id"]}\t{job["stage"]}\trun `step {job["id"]}` to see whether the author answered'
    return f'wait\t{job["issue_ref"]}\t{job["id"]}\t{job["stage"]}\twaits on a human'


def command_queue(jobs: Jobs) -> int:
    for job in jobs.all():
        if job['stage'] not in TERMINAL:
            _refresh(jobs, job)
    open_jobs = [job for job in jobs.all() if job['stage'] not in TERMINAL]
    taken = {job['issue_ref'] for job in open_jobs}
    for job in open_jobs:
        print(_job_line(job))
    slots = jobs.free_slots()
    for issue in jobs.queue.list_open(jobs.config['queue']['label']):
        if issue['ref'] in taken:
            continue
        action = 'new' if slots > 0 else 'hold'
        slots -= 1
        note = f'run `create {issue["ref"]}`' if action == 'new' else 'no free slot'
        print(f'{action}\t{issue["ref"]}\t-\t-\t{note}: {issue["title"]}')
    return 0


# -- one job ----------------------------------------------------------------

def command_step(jobs: Jobs, arguments: list[str]) -> int:
    job = jobs.resolve(arguments[0])
    if '--resume' in arguments:
        job['spawned'] = {}
        jobs.save(job)
    lines = Pipeline(jobs).step(job, _option(arguments, '--returned'))
    print('\n'.join(lines))
    if job['stage'] not in RUNNING:
        _measure(jobs, job)
    return 0


def command_resync(jobs: Jobs, arguments: list[str]) -> int:
    job = jobs.resolve(arguments[0])
    job['stale'] = False
    print('\n'.join(Resync(Pipeline(jobs)).run(job)))
    return 0


def _stdin_text(what: str) -> str:
    text = sys.stdin.read().strip()
    if not text:
        raise Refused(f'{what} is read from stdin and stdin was empty')
    return text


def command_feedback(jobs: Jobs, arguments: list[str]) -> int:
    job = jobs.resolve(arguments[0])
    if job['stage'] not in ('ready', 'needs-human'):
        raise Refused(f'{job["id"]} is in stage {job["stage"]}: feedback goes to a delivered or an escalated job')
    target = jobs.next_numbered(job, 'feedback')
    write_atomically(target, f'SOURCE: human\n\n## Summary\n- Feedback from the human who reviews this job.\n\n{_stdin_text("feedback")}\n')
    job['feedback_file'] = str(target)
    jobs.ensure_worktree(job)
    jobs.start_round(job, fresh_budget=True)
    jobs.queue.remove_label(job['issue_ref'], jobs.config['queue']['needs_human_label'])
    jobs.move(job, 'build')
    print('\n'.join(Pipeline(jobs).step(job)))
    return 0


def command_answer(jobs: Jobs, arguments: list[str]) -> int:
    job = jobs.resolve(arguments[0])
    if job['stage'] != 'needs-info':
        raise Refused(f'{job["id"]} is in stage {job["stage"]}: it asked no question')
    jobs.queue.comment(job['issue_ref'], _stdin_text('the answer'))
    print('\n'.join(Pipeline(jobs).step(job)))
    return 0


def command_reject(jobs: Jobs, arguments: list[str]) -> int:
    job = jobs.resolve(arguments[0])
    if job['stage'] in TERMINAL:
        raise Refused(f'{job["id"]} already ended as {job["stage"]}')
    reason = _stdin_text('the reason')
    write_atomically(jobs.folder(job) / 'rejection.md', f'REJECTED: by a human\n\n## Summary\n- {reason}\n')
    jobs.queue.comment(job['issue_ref'], f'{MARKER}\n**Craftsman factory: job `{job["id"]}` was dropped.**\n\n{reason}\n')
    settings = jobs.config['queue']
    for label in (settings['label'], settings['needs_info_label'], settings['needs_human_label']):
        jobs.queue.remove_label(job['issue_ref'], label)
    if job.get('pr'):
        jobs.forge.close(job['pr']['number'])
    jobs.finish(job, 'rejected')
    _measure(jobs, job)
    print(f'DONE\t{job["id"]}\trejected')
    return 0


def command_create(jobs: Jobs, arguments: list[str]) -> int:
    print(jobs.create(arguments[0])['id'])
    return 0


def command_check(repo: Path) -> int:
    worktree = git(os.getcwd(), 'rev-parse', '--show-toplevel').strip()
    config = load_config(repo)
    git(repo, 'fetch', 'origin', config['forge']['base_branch'])
    result = gate.evaluate(worktree, config)
    print(gate.render(result))
    return 0 if result['passed'] else 1


def command_summary(jobs: Jobs, arguments: list[str]) -> int:
    selected = [jobs.resolve(reference) for reference in arguments] or jobs.all()
    print('job\tissue\tstage\trounds\tconfidence\tcost\tpull request')
    for job in selected:
        confidence = job.get('confidence') or {}
        cost = (job.get('cost') or {}).get('usd')
        print('\t'.join([job['id'], job['issue_ref'], job['stage'], str(job.get('rounds_total', 0)),
                         f'{confidence.get("score", "-")} {confidence.get("level", "")}'.strip(),
                         f'~${cost:.2f}' if isinstance(cost, (int, float)) else '-',
                         (job.get('pr') or {}).get('url', '-')]))
    return 0


def command_learn(jobs: Jobs, arguments: list[str]) -> int:
    if '--classify' in arguments:
        print(f'classified {insight.classify()} human remark(s)')
    for level, counts in sorted(insight.levels().items()):
        print(f'{level}\t{counts["delivered"]} closed or merged\t{counts["corrected"]} corrected by a human')
    for proposal in insight.proposals(jobs.config):
        print(f'PROPOSAL\t{proposal["threshold"]} threshold {proposal["from"]} -> {proposal["to"]}\t{proposal["reason"]}')
    for entry in insight.recurring():
        print(f'RECURRING\t{entry["classification"]}\t{entry["jobs"]} job(s), {entry["remarks"]} remark(s)')
    return 0


def command_page(jobs: Jobs, arguments: list[str]) -> int:
    target = _publish(jobs)
    print(target)
    if '--open' in arguments:
        webbrowser.open(f'file://{target}')
    return 0


def _publish(jobs: Jobs) -> Path:
    page.register(jobs.repo)
    page.write_index(jobs.repo, jobs.all())
    return page.build(jobs.config)


COMMANDS = {'queue': command_queue, 'create': command_create, 'step': command_step, 'resync': command_resync,
            'feedback': command_feedback, 'answer': command_answer, 'reject': command_reject,
            'summary': command_summary, 'learn': command_learn, 'page': command_page}
NEEDS_JOB = ('create', 'step', 'resync', 'feedback', 'answer', 'reject')


def _dispatch(name: str, arguments: list[str]) -> int:
    repo = repo_root()
    if name == 'init':
        code = command_init(repo, arguments)
        _publish(Jobs(repo))
        return code
    if name == 'check':
        return command_check(repo)
    if name in NEEDS_JOB and not arguments:
        raise Refused(f'`{name}` needs a job id or an issue reference')
    if not (state_dir(repo) / 'config.json').is_file():
        raise Refused(f'no {STATE_DIRNAME}/config.json in {repo}: run `craftsman-factory init` first')
    jobs = Jobs(repo)
    handler = COMMANDS[name]
    code = handler(jobs) if name == 'queue' else handler(jobs, arguments)
    if name != 'page':
        _publish(jobs)
    return code


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ('-h', '--help', 'help') or argv[0] not in (*COMMANDS, 'init', 'check'):
        print(__doc__.strip())
        return 0 if argv and argv[0] in ('-h', '--help', 'help') else 2
    try:
        return _dispatch(argv[0], argv[1:])
    except Refused as refusal:
        print(f'factory: {refusal}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
