// The craftsman cockpit (ADR-0031). The mod holds no verdict and no SQL: it
// reads what the core keeps through bin/craftsman-helper and carries the
// person's press back to it. It registers no tool, so only a person can
// approve an instinct (ADR-0020).
//
// Three surfaces: a band above the prompt with the session's quality state, a
// line under each answer that changed it, and the /instincts review pane.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, ProcessRunResult, Register } from 'claude-code'

import type { CockpitCandidate, CockpitPulse, CockpitQueue, CockpitView } from './types'

const PANE = 'instincts'
const view = atom({ plugin: 'craftsman', key: 'view' } as const, { kind: 'loading' } as CockpitView)
// The id of the candidate whose skill preview is open; 0 for none.
const preview = atom({ plugin: 'craftsman', key: 'preview' } as const, 0)
// The session's state as the core last answered it, and as it stood when the
// current turn began: the turn's receipt is the difference.
const pulse = atom({ plugin: 'craftsman', key: 'pulse' } as const, null as CockpitPulse | null)
const turnStart = atom({ plugin: 'craftsman', key: 'turnStart' } as const, null as CockpitPulse | null)

// The tools whose PostToolUse the craftsman hooks judge (hooks/hooks.json).
const WRITING_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'Bash'])

type Helper = { argv0: string; env: Record<string, string> }
type Located = { helper: Helper } | { tried: string[] }
type Answer = { ran: ProcessRunResult; argv0: string } | { missing: string[] } | { error: string }

// The module ships in the craftsman plugin, so the core is this plugin's own
// root: nothing to look up, nothing to guess. The session binding the hooks
// write still names the data directory they use for this session.
async function locate($: EngineInterface): Promise<Located> {
  const argv0 = `${$.plugin.root}/bin/craftsman-helper`
  if (!(await $.fs.exists(argv0))) return { tried: [`plugin root: ${argv0}`] }
  return { helper: { argv0, env: await sessionEnv($) } }
}

async function sessionEnv($: EngineInterface): Promise<Record<string, string>> {
  const session = await $.session.id()
  if (session === '') return {}
  const env: Record<string, string> = { CRAFTSMAN_SESSION_ID: session, CRAFTSMAN_SESSION_HOST: 'claude-code' }
  const home = await $.env.get('HOME')
  const data = home === undefined ? undefined : await boundData($, `${home}/.claude/craftsman/sessions/${session}.json`, session)
  return data === undefined ? env : { ...env, CRAFTSMAN_PLUGIN_DATA: data }
}

async function boundData($: EngineInterface, path: string, session: string): Promise<string | undefined> {
  if (!(await $.fs.exists(path))) return undefined
  try {
    const parsed: unknown = JSON.parse(String(await $.fs.read(path)))
    if (typeof parsed !== 'object' || parsed === null) return undefined
    const { host, session_id: id, data } = parsed as Record<string, unknown>
    return host === 'claude-code' && id === session && typeof data === 'string' ? data : undefined
  } catch {
    return undefined
  }
}

async function helper($: EngineInterface, args: string[]): Promise<Answer> {
  const located = await locate($)
  if ('tried' in located) return { missing: located.tried }
  const ran = await $.process.run([located.helper.argv0, ...args], { env: located.helper.env })

  return { ran, argv0: located.helper.argv0 }
}

function firstLine(text: string): string {
  return text.trim().split('\n')[0] ?? ''
}

function basename(path: string): string {
  return path.split('/').pop() ?? path
}

function counted(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? '' : 's'}`
}

// --- The session's pulse -------------------------------------------------------

function parsePulse(stdout: string): CockpitPulse | null {
  try {
    const parsed = JSON.parse(stdout) as CockpitPulse
    return typeof parsed.writes === 'number' && Array.isArray(parsed.open) && typeof parsed.tests === 'object' ? parsed : null
  } catch {
    return null
  }
}

async function refreshPulse($: EngineInterface): Promise<CockpitPulse | null> {
  const answer = await helper($, ['session', 'status']).catch((error: unknown) => ({ error: String(error) }))
  const current = 'ran' in answer && answer.ran.exitCode === 0 ? parsePulse(answer.ran.stdout) : null
  await update($, pulse, () => current)
  return current
}

// Silent until the session has something to say: no write, no open block and
// no test run is an empty line that would only take a row.
function worthShowing(current: CockpitPulse | null): current is CockpitPulse {
  return current !== null && (current.writes > 0 || current.open.length > 0 || current.tests.verdict !== 'not-run')
}

type Segment = { text: string; color?: string; dim?: boolean }

function openSegment(current: CockpitPulse): Segment | undefined {
  if (current.open.length === 0) return undefined
  const named = current.open.slice(0, 2).map(block => `${block.rules.join(',')} ${basename(block.file)}`)
  const more = current.open.length > 2 ? ` +${current.open.length - 2}` : ''
  return { text: `${current.open.length} open: ${named.join(', ')}${more}`, color: 'red' }
}

function testsSegment(current: CockpitPulse): Segment {
  const { verdict, red_runs: red } = current.tests
  if (verdict === 'red') return { text: `tests red: ${red.join(', ')}`, color: 'red' }
  if (verdict === 'verified') return { text: 'tests verified', color: 'green' }
  if (verdict === 'empty') return { text: 'last test run tested nothing', color: 'yellow' }
  if (verdict === 'unverified') return { text: 'tests not verified', color: 'yellow' }
  return current.writes > 0 ? { text: 'tests not run', color: 'yellow' } : { text: 'tests not run', dim: true }
}

function bandSegments(current: CockpitPulse): Segment[] {
  const warned = current.warned > 0 ? { text: counted(current.warned, 'warning'), color: 'yellow' } : undefined
  return [
    { text: `${counted(current.writes, 'write')} in ${counted(current.files, 'file')}`, dim: true },
    openSegment(current),
    warned,
    testsSegment(current),
  ].filter((segment): segment is Segment => segment !== undefined)
}

// What this turn changed, in one line; empty when it changed nothing the
// gate measures, so a turn that only read or talked leaves no receipt.
function receipt(before: CockpitPulse, after: CockpitPulse): string {
  const writes = after.writes - before.writes
  const blocked = after.blocked - before.blocked
  const warned = after.warned - before.warned
  const verdictMoved = after.tests.verdict !== before.tests.verdict
  if (writes <= 0 && blocked <= 0 && warned <= 0 && !verdictMoved) return ''
  const open = openSegment(after)
  return [
    `craftsman: ${counted(Math.max(writes, 0), 'write')}, ${Math.max(blocked, 0)} blocked, ${counted(Math.max(warned, 0), 'warning')}`,
    open?.text ?? 'nothing open',
    testsSegment(after).text,
  ].join(' · ')
}

// --- The instinct review pane --------------------------------------------------

async function refresh($: EngineInterface, notice: string): Promise<void> {
  // The same directory approve writes to, so the preview names the file it will be.
  const skillsDir = `${await $.session.cwd()}/.claude/skills`
  const answer = await helper($, ['instincts', 'review', skillsDir]).catch((error: unknown) => ({ error: String(error) }))
  await update($, view, (): CockpitView => toView(answer, notice))
}

function toView(answer: Answer, notice: string): CockpitView {
  if ('error' in answer) return { kind: 'failed', message: answer.error }
  if ('missing' in answer) return { kind: 'missing', tried: answer.missing }
  const { exitCode, stdout, stderr } = answer.ran
  const queue = exitCode === 0 ? parseQueue(stdout) : undefined
  return queue === undefined
    ? { kind: 'failed', message: `${answer.argv0}: ${firstLine(stderr) || `instincts review exited ${exitCode}`}` }
    : { kind: 'ready', queue, notice }
}

function parseQueue(stdout: string): CockpitQueue | undefined {
  try {
    const parsed = JSON.parse(stdout) as CockpitQueue
    return Array.isArray(parsed.candidates) && Array.isArray(parsed.approved) ? parsed : undefined
  } catch {
    return undefined
  }
}

// A press is the person's gesture: the id comes from the queue this pane drew,
// and the skill goes where /craftsman:metrics puts it, under the session's cwd.
async function decide($: EngineInterface, verb: 'approve' | 'reject', candidate: CockpitCandidate) {
  const args = verb === 'approve'
    ? ['instincts', 'approve', String(candidate.id), `${await $.session.cwd()}/.claude/skills`]
    : ['instincts', 'reject', String(candidate.id)]
  const answer = await helper($, args).catch((error: unknown) => ({ error: String(error) }))
  const notice = 'error' in answer
    ? `${verb} ${candidate.rule} failed: ${answer.error}`
    : 'missing' in answer
      ? `${verb} ${candidate.rule}: craftsman-helper not found`
      : answer.ran.exitCode === 0
        ? firstLine(answer.ran.stdout)
        : `${verb} ${candidate.rule} failed (${answer.argv0}): ${firstLine(answer.ran.stderr)}`
  await refresh($, notice)
}

// What a severity does to a write, in the words a reviewer decides on.
const SEVERITY_EFFECT: Record<string, string> = {
  block: 'blocks the write',
  warn: 'advisory: reported, never blocks',
  ignore: 'switched off',
}

function origin(candidate: CockpitCandidate): string {
  const owner = candidate.rule_owner === '' ? 'unknown pack' : candidate.rule_owner === 'core' ? 'core rules' : `${candidate.rule_owner} pack`
  const effect = SEVERITY_EFFECT[candidate.default_severity] ?? 'severity unknown'
  return `${owner} · ${candidate.rule_group || 'no group'} · default ${candidate.default_severity || '?'} (${effect})`
}

function acceptance(candidate: CockpitCandidate): string {
  const total = candidate.fixed + candidate.rejected
  const rate = total === 0 ? 0 : Math.round((100 * candidate.fixed) / total)
  return `Accepted ${candidate.fixed} of ${total} times (${rate}%). Refused ${candidate.rejected}: ` +
    `${candidate.ignored} craftsman-ignore, ${candidate.scoped} relaxed by config.`
}

// Below four fixes in five, the refusals are part of the decision.
function isContested(candidate: CockpitCandidate): boolean {
  return candidate.rejected * 5 > candidate.fixed + candidate.rejected
}

function standing(candidate: CockpitCandidate): string {
  const last = candidate.last_fixed === '' ? 'never recorded' : candidate.last_fixed.slice(0, 10)
  return `Last fixed ${last} · ${candidate.files} files · confidence ${candidate.confidence.toFixed(2)} ` +
    '(lower bound of the acceptance rate: an order, not a bar)'
}

// The elements a render hook draws with, resolved for the app drawing it.
type Elements = ReturnType<EngineInterface['ui']['resolve']>

function drawBand({ Box, Text }: Elements, current: CockpitPulse, theirs: unknown) {
  return (
    <Box flexDirection="column">
      <Text>
        <Text bold>craftsman</Text>
        {bandSegments(current).map(segment => (
          <Text color={segment.color} dimColor={segment.dim === true}> · {segment.text}</Text>
        ))}
      </Text>
      {theirs}
    </Box>
  )
}

type Card = { ui: Elements; candidate: CockpitCandidate; opened: number }

// $ goes apart: the mods API refuses it inside an object.
function drawCandidate($: EngineInterface, { ui: { Box, Text, Button }, candidate, opened }: Card) {
  return (
    <Box key={`candidate-${candidate.id}`} flexDirection="column" marginTop={1}>
      <Text>
        <Text bold>{candidate.rule}</Text>{candidate.rule_text !== '' ? ` · ${candidate.rule_text}` : ''}
      </Text>
      <Text dimColor>{origin(candidate)}</Text>
      <Text>{acceptance(candidate)}</Text>
      <Text dimColor>{standing(candidate)}</Text>
      {candidate.summary !== '' && <Text dimColor>Recorded fix: {candidate.summary}</Text>}
      <Text dimColor>Fixed in:</Text>
      {candidate.evidence.map(item => (
        <Text dimColor>  {item.file}{item.context !== '' ? `: ${item.context}` : ''}</Text>
      ))}
      <Text>Approve: writes {candidate.skill_path}; Claude then loads it as background knowledge and applies the fix before the gate flags it.</Text>
      <Text>Reject: no skill; the candidate stays hidden until new fixes build up. The rule itself keeps running either way.</Text>
      {isContested(candidate) && <Text color="yellow">About one refusal in {Math.round((candidate.fixed + candidate.rejected) / Math.max(1, candidate.rejected))}: if those were legitimate exceptions, Approve; if the rule misfits this codebase, Reject and relax it in .craft-rules.yml.</Text>}
      <Box flexDirection="row" gap={1}>
        <Button key={`approve-${candidate.id}`} variant="primary" onPress={() => decide($, 'approve', candidate)}>
          Approve
        </Button>
        <Button key={`reject-${candidate.id}`} onPress={() => decide($, 'reject', candidate)}>
          Reject
        </Button>
        <Button key={`skill-${candidate.id}`} onPress={() => update($, preview, open => (open === candidate.id ? 0 : candidate.id))}>
          {opened === candidate.id ? 'Hide skill' : 'Show skill'}
        </Button>
      </Box>
      {opened === candidate.id && (
        <Box flexDirection="column" borderStyle="single" paddingX={1}>
          {candidate.skill_preview.split('\n').map(line => <Text dimColor>{line === '' ? ' ' : line}</Text>)}
        </Box>
      )}
    </Box>
  )
}

async function drawPane($: EngineInterface, ui: Elements) {
  const { Box, Text, Button } = ui
  const current = await read($, view)

  if (current.kind === 'loading') return <Text dimColor>Reading the instinct queue...</Text>
  if (current.kind === 'failed') return <Text color="red">instincts review failed: {current.message}</Text>
  if (current.kind === 'missing') {
    return (
      <Box flexDirection="column">
        <Text color="yellow">craftsman-helper not found. Tried:</Text>
        {current.tried.map(place => <Text dimColor>  {place}</Text>)}
        <Text dimColor>Reinstall the craftsman plugin: its bin/craftsman-helper is missing.</Text>
      </Box>
    )
  }

  const { candidates, approved } = current.queue
  const opened = await read($, preview)

  return (
    <Box flexDirection="column">
      {current.notice !== '' && <Text color="green">{current.notice}</Text>}
      <Text bold>Candidates ({candidates.length})</Text>
      {candidates.length === 0 && <Text dimColor>Nothing awaits review.</Text>}
      {candidates.map(candidate => drawCandidate($, { ui, candidate, opened }))}
      <Box marginTop={1} flexDirection="column">
        <Text bold>Approved ({approved.length})</Text>
        {approved.map(item => (
          <Text dimColor>{item.rule} confidence {item.confidence.toFixed(2)} · fixed {item.fixed} · {item.files} files</Text>
        ))}
      </Box>
      <Box marginTop={1}>
        <Button key="refresh" hotkey="r" onPress={() => refresh($, '')}>Refresh</Button>
      </Box>
    </Box>
  )
}

// The turn's receipt goes ahead of what the mods after this one print there,
// on the same line: the site draws one line, and a newline reached a headless
// session's output as U+FFFD (Claude Code 2.1.310). With no mod after this
// one, the event passed on carries the answer itself, which is already drawn
// above the line: repeating it is noise, measured on the same build.
function withReceipt(line: string, passed: unknown, answer: unknown) {
  if (line === '') return passed
  const theirs = typeof passed === 'object' && passed !== null && 'text' in passed ? String(passed.text ?? '') : ''
  return { text: theirs === '' || theirs === answer ? line : `${line} | ${theirs}` }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'instincts',
      description: 'Review learned-instinct candidates (ADR-0020) and approve or reject them',
    })
    await refreshPulse($)

    return next(e)
  })

  // After the event is passed on, so the craftsman PostToolUse hooks have
  // counted the write before the core is asked.
  on('classic.PostToolUse', async ($, e, next) => {
    const passed = await next(e)
    if (WRITING_TOOLS.has(String(e.tool_name))) await refreshPulse($)

    return passed
  })

  on('turn.start', async ($, e, next) => {
    const current = await read($, pulse)
    await update($, turnStart, () => current)

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const before = await read($, turnStart)
    const after = await refreshPulse($)
    const line = before !== null && after !== null ? receipt(before, after) : ''

    return withReceipt(line, await next(e), e.answer)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, pulse)
    if (!worthShowing(current)) return next(e)

    return drawBand($.ui.resolve(e), current, await next(e))
  })

  on('command.run', { command: 'instincts' }, async $ => {
    await update($, view, (): CockpitView => ({ kind: 'loading' }))
    await $.ui.open({ id: PANE, title: 'Instinct review', focus: true })
    await refresh($, '')

    return { text: 'Instinct review pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => drawPane($, $.ui.resolve(e)))
}
