"""Who reviews a job, and how closely a human should read the result.

Both are computed, never judged by a model. Routing reads the intake's risk
and surfaces and the languages of the diff. Confidence starts at 100 and loses
points for every reason a human should look closer; a reviewer may lower it
(`CONFIDENCE: medium|low` in its file) and nothing can raise it.

The weights are arbitrary until the learning loop has outcomes to compare them
with (`insight.py`): they live in the config so a calibration is a config
change a human approves, never a code change.
"""
from __future__ import annotations

from pathlib import Path

from . import registry
from .base import MARKER, header_value, routing

LEVELS = ('skim', 'standard', 'deep')
MAX_PACK_REVIEWERS = 2
NEVER_SKIM_SURFACES = ('security',)


def _reviewer(entry: dict, model: str) -> dict:
    return {'name': entry['name'], 'lens': entry['lens'], 'model': entry.get('model') or model}


def route(intake: dict, files: list[str], config: dict) -> list[dict]:
    """The reviewers of a job: one per language of the diff, one per surface."""
    table = routing()
    model = config['reviewer_models'].get(intake.get('risk', 'medium'), 'sonnet')
    packs = [pack for pack in registry.packs_of(files) if pack in table['packs']][:MAX_PACK_REVIEWERS]
    reviewers = [_reviewer(table['packs'][pack], model) for pack in packs]
    if not reviewers:
        reviewers.append(_reviewer(table['default'], model))
    for surface in intake.get('surfaces', []):
        if surface in table['surfaces']:
            reviewers.append(_reviewer(table['surfaces'][surface], model))
    unique = {reviewer['name']: reviewer for reviewer in reviewers}
    return list(unique.values())


def _diff_reasons(gate: dict, weights: dict) -> list[tuple]:
    reasons = []
    lines = gate.get('lines_changed', 0)
    if lines > 500:
        reasons.append((weights['diff_over_500_lines'], f'{lines} lines changed'))
    elif lines > 200:
        reasons.append((weights['diff_over_200_lines'], f'{lines} lines changed'))
    if len(gate.get('files', [])) > 10:
        reasons.append((weights['over_10_files'], f'{len(gate["files"])} files changed'))
    return reasons


def _test_reasons(gate: dict, weights: dict) -> list[tuple]:
    tests = gate.get('tests', {})
    reasons = []
    if tests.get('skips'):
        reasons.append((weights['test_skip_added'], f'{len(tests["skips"])} test skip marker(s) added'))
    if tests.get('deleted'):
        reasons.append((weights['test_file_deleted'], f'{len(tests["deleted"])} test file(s) deleted'))
    if tests.get('ignores'):
        reasons.append((weights['ignore_marker_added'], f'{len(tests["ignores"])} rule ignore marker(s) added'))
    if tests.get('source_changed') and not tests.get('test_changed'):
        reasons.append((weights['no_test_changed'], 'source changed and no test file did'))
    warnings = len(gate.get('rules', {}).get('warnings', []))
    if warnings:
        reasons.append((min(warnings * weights['ci_warning'], weights['ci_warning_cap']),
                        f'{warnings} rules-engine warning(s) left in the diff'))
    return reasons


def _intake_reasons(job: dict, weights: dict) -> list[tuple]:
    intake = job.get('intake') or {}
    reasons = []
    risk = intake.get('risk', 'medium')
    if f'risk_{risk}' in weights:
        reasons.append((weights[f'risk_{risk}'], f'{risk} risk'))
    for surface in intake.get('surfaces', []):
        if f'surface_{surface}' in weights:
            reasons.append((weights[f'surface_{surface}'], f'touches the {surface} surface'))
    if job.get('spec_source') == 'generated' and 'domain' in intake.get('surfaces', []):
        reasons.append((weights['spec_generated_on_domain'], 'the spec of a domain change was written by the factory'))
    return reasons


def _process_reasons(job: dict, reviews: dict, weights: dict) -> list[tuple]:
    reasons = []
    extra = job.get('rounds_total', job.get('round', 1)) - 1
    if extra > 0:
        reasons.append((extra * weights['extra_round'], f'{extra} extra build round(s)'))
    if job.get('resynced'):
        reasons.append((weights['resynced'], 'resynchronised with the base branch after delivery'))
    for name, review in sorted(reviews.items()):
        stated = review.get('confidence', 'high')
        if f'reviewer_{stated}' in weights:
            reasons.append((weights[f'reviewer_{stated}'], f'the {name} reviewer states {stated} confidence'))
    return reasons


def _level(score: int, thresholds: dict) -> str:
    if score >= thresholds['skim']:
        return 'skim'
    return 'standard' if score >= thresholds['standard'] else 'deep'


def confidence(job: dict, evidence: dict, config: dict) -> dict:
    """`evidence` is what the job produced: {'gate': the gate's result, 'reviews': read_reviews()}."""
    gate, reviews = evidence['gate'], evidence['reviews']
    settings = config['confidence']
    weights = settings['weights']
    reasons = (_intake_reasons(job, weights) + _diff_reasons(gate, weights)
               + _test_reasons(gate, weights) + _process_reasons(job, reviews, weights))
    score = max(0, 100 - sum(points for points, _ in reasons))
    level = _level(score, settings['thresholds'])
    tests = gate.get('tests', {})
    surfaces = (job.get('intake') or {}).get('surfaces', [])
    capped = (any(surface in NEVER_SKIM_SURFACES for surface in surfaces) or tests.get('skips')
              or tests.get('deleted') or tests.get('ignores'))
    if level == 'skim' and capped:
        level = 'standard'
        reasons.append((0, 'never a skim: security surface, a test skipped or deleted, or a rule ignored'))
    return {'score': score, 'level': level, 'reasons': reasons}


def read_reviews(round_dir: Path, reviewers: list[dict]) -> dict:
    """{reviewer name: {verdict, confidence}} for the reviews present in a round."""
    reviews = {}
    for reviewer in reviewers:
        path = round_dir / f'review-{reviewer["name"]}.md'
        verdict = header_value(path, 'VERDICT').upper()
        if verdict:
            reviews[reviewer['name']] = {'verdict': verdict,
                                         'confidence': header_value(path, 'CONFIDENCE').lower() or 'high'}
    return reviews


READING = {
    'skim': 'Read the summary and the acceptance evidence; open the diff where something surprises you.',
    'standard': 'Read the whole diff once, with the spec beside it.',
    'deep': 'Read the diff line by line, run it, and check every reason listed below.',
}


def render(job: dict, result: dict, label: str) -> str:
    lines = [f'CONFIDENCE: {result["score"]}', f'LEVEL: {result["level"]}', f'LABEL: {label}', '',
             '## Summary',
             f'- Confidence {result["score"]}/100, review depth: **{result["level"]}**',
             f'- {READING[result["level"]]}',
             f'- {job.get("rounds_total", job.get("round", 1))} build round(s), reviewers: '
             + (', '.join(reviewer['name'] for reviewer in job.get('reviewers', [])) or 'none'),
             '', '## Why']
    lines += [f'- -{points}: {text}' if points else f'- {text}' for points, text in result['reasons']] or ['- Nothing lowered it.']
    return '\n'.join(lines) + '\n'


def pull_request_comment(job: dict, result: dict, label: str) -> str:
    body = render(job, result, label).split('\n\n', 1)[1]
    return (f'{MARKER}\n**Craftsman factory: job `{job["id"]}` is ready for review** (`{label}`)\n\n{body}\n'
            'Merging this pull request is the approval. To ask for a change, comment here or tell the factory.\n'
            'The score is computed from the job\'s facts; a reviewer can lower it, nothing can raise it.\n')
