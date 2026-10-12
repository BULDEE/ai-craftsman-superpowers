// The instinct review pane (ADR-0031). The mod holds no verdict and no SQL:
// it reads the queue from `instincts review` and carries the person's press
// back to `instincts approve|reject`, both through bin/craftsman-helper. It
// registers no tool, so only a person can approve an instinct (ADR-0020).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, PluginOptions, ProcessRunResult, Register } from 'claude-code'

import type { CockpitCandidate, CockpitQueue, CockpitView } from '../types'

const PANE = 'instincts'
const view = atom({ plugin: 'craftsman-cockpit', key: 'view' } as const, { kind: 'loading' } as CockpitView)
// The id of the candidate whose skill preview is open; 0 for none.
const preview = atom({ plugin: 'craftsman-cockpit', key: 'preview' } as const, 0)

type Helper = { argv0: string; env: Record<string, string> }
type Located = { helper: Helper } | { tried: string[] }
type Answer = { ran: ProcessRunResult } | { missing: string[] } | { error: string }

// The order ADR-0031 fixes: the option, the session binding the craftsman
// hooks write, the repository layout this mod ships in, then PATH. Each place
// is named in the pane when none answers; nothing falls back to a guess.
async function locate($: EngineInterface, options: PluginOptions): Promise<Located> {
  const tried: string[] = []
  const configured = typeof options.helper === 'string' ? options.helper.trim() : ''
  if (configured !== '') {
    if (await $.fs.exists(configured)) return { helper: { argv0: configured, env: {} } }
    tried.push(`option helper: ${configured}`)
  }

  const home = await $.env.get('HOME')
  const session = await $.session.id()
  if (home !== undefined && session !== '') {
    const binding = `${home}/.claude/craftsman/sessions/${session}.json`
    const bound = await readBinding($, binding, session)
    if (bound !== undefined) return { helper: bound }
    tried.push(`session binding: ${binding}`)
  }

  const sibling = `${$.plugin.root}/../../bin/craftsman-helper`
  if (await $.fs.exists(sibling)) return { helper: { argv0: sibling, env: {} } }
  tried.push(`repository layout: ${sibling}`)

  // craftsman-path prints the installation's root and writes nothing, unlike
  // any instincts subcommand, which refreshes the candidates as it answers.
  const onPath = await $.process.run(['craftsman-path', 'bin/craftsman-helper']).catch(() => undefined)
  const resolved = onPath?.exitCode === 0 ? firstLine(onPath.stdout) : ''
  if (resolved !== '' && (await $.fs.exists(resolved))) return { helper: { argv0: resolved, env: {} } }
  tried.push('PATH: craftsman-path')

  return { tried }
}

async function readBinding($: EngineInterface, path: string, session: string): Promise<Helper | undefined> {
  if (!(await $.fs.exists(path))) return undefined
  try {
    const parsed: unknown = JSON.parse(String(await $.fs.read(path)))
    if (typeof parsed !== 'object' || parsed === null) return undefined
    const { host, session_id: id, root, data } = parsed as Record<string, unknown>
    if (host !== 'claude-code' || id !== session || typeof root !== 'string' || typeof data !== 'string') return undefined
    const argv0 = `${root}/bin/craftsman-helper`
    if (!(await $.fs.exists(argv0))) return undefined
    return {
      argv0,
      env: { CRAFTSMAN_SESSION_ID: session, CRAFTSMAN_SESSION_HOST: 'claude-code', CRAFTSMAN_PLUGIN_DATA: data },
    }
  } catch {
    return undefined
  }
}

async function helper($: EngineInterface, options: PluginOptions, args: string[]): Promise<Answer> {
  const located = await locate($, options)
  if ('tried' in located) return { missing: located.tried }
  const ran = await $.process.run([located.helper.argv0, 'instincts', ...args], { env: located.helper.env })

  return { ran }
}

async function refresh($: EngineInterface, options: PluginOptions, notice: string): Promise<void> {
  // The same directory approve writes to, so the preview names the file it will be.
  const skillsDir = `${await $.session.cwd()}/.claude/skills`
  const answer = await helper($, options, ['review', skillsDir]).catch((error: unknown) => ({ error: String(error) }))
  await update($, view, (): CockpitView => toView(answer, notice))
}

function toView(answer: Answer, notice: string): CockpitView {
  if ('error' in answer) return { kind: 'failed', message: answer.error }
  if ('missing' in answer) return { kind: 'missing', tried: answer.missing }
  const { exitCode, stdout, stderr } = answer.ran
  const queue = exitCode === 0 ? parseQueue(stdout) : undefined
  return queue === undefined
    ? { kind: 'failed', message: firstLine(stderr) || `instincts review exited ${exitCode}` }
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

function firstLine(text: string): string {
  return text.trim().split('\n')[0] ?? ''
}

// A press is the person's gesture: the id comes from the queue this pane drew,
// and the skill goes where /craftsman:metrics puts it, under the session's cwd.
type Decision = { options: PluginOptions; verb: 'approve' | 'reject'; candidate: CockpitCandidate }

// craftsman-ignore: WARN-TS001 (wrong: two parameters, the regex counts the destructured fields)
async function decide($: EngineInterface, { options, verb: decision, candidate }: Decision) {
  const args = decision === 'approve'
    ? ['approve', String(candidate.id), `${await $.session.cwd()}/.claude/skills`]
    : ['reject', String(candidate.id)]
  const answer = await helper($, options, args).catch((error: unknown) => ({ error: String(error) }))
  const notice = 'error' in answer
    ? `${decision} ${candidate.rule} failed: ${answer.error}`
    : 'missing' in answer
      ? `${decision} ${candidate.rule}: craftsman-helper not found`
      : answer.ran.exitCode === 0
        ? firstLine(answer.ran.stdout)
        : `${decision} ${candidate.rule} failed: ${firstLine(answer.ran.stderr)}`
  await refresh($, options, notice)
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

export const register: Register = (on, options) => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'instincts',
      description: 'Review learned-instinct candidates (ADR-0020) and approve or reject them',
    })

    return next(e)
  })

  on('command.run', { command: 'instincts' }, async $ => {
    await update($, view, (): CockpitView => ({ kind: 'loading' }))
    await $.ui.open({ id: PANE, title: 'Instinct review', focus: true })
    await refresh($, options, '')

    return { text: 'Instinct review pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const current = await read($, view)

    if (current.kind === 'loading') return <Text dimColor>Reading the instinct queue...</Text>
    if (current.kind === 'failed') return <Text color="red">instincts review failed: {current.message}</Text>
    if (current.kind === 'missing') {
      return (
        <Box flexDirection="column">
          <Text color="yellow">craftsman-helper not found. Tried:</Text>
          {current.tried.map(place => <Text dimColor>  {place}</Text>)}
          <Text dimColor>Set the helper option to the craftsman plugin's bin/craftsman-helper.</Text>
        </Box>
      )
    }

    const { candidates, approved } = current.queue
    const opened = await read($, preview)
    const room = Math.max(1, Math.floor(((e.viewport?.rows ?? 30) - 8) / 14))
    const shown = candidates.slice(0, room)

    return (
      <Box flexDirection="column">
        {current.notice !== '' && <Text color="green">{current.notice}</Text>}
        <Text bold>Candidates ({candidates.length})</Text>
        {candidates.length === 0 && <Text dimColor>Nothing awaits review.</Text>}
        {shown.map(candidate => (
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
              <Button key={`approve-${candidate.id}`} variant="primary" onPress={() => decide($, { options, verb: 'approve', candidate })}>
                Approve
              </Button>
              <Button key={`reject-${candidate.id}`} onPress={() => decide($, { options, verb: 'reject', candidate })}>
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
        ))}
        {candidates.length > shown.length && <Text dimColor>{candidates.length - shown.length} more below the fold; decide these first.</Text>}
        <Box marginTop={1} flexDirection="column">
          <Text bold>Approved ({approved.length})</Text>
          {approved.map(item => (
            <Text dimColor>{item.rule} confidence {item.confidence.toFixed(2)} · fixed {item.fixed} · {item.files} files</Text>
          ))}
        </Box>
        <Box marginTop={1}>
          <Button key="refresh" hotkey="r" onPress={() => refresh($, options, '')}>Refresh</Button>
        </Box>
      </Box>
    )
  })
}
