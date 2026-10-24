import { expect, test } from 'claude-code/testing'
import type { On, ProcessRunInit } from 'claude-code'

const SESSION = 'sid-1'
// Not under /home/<user>/: the secrets scan refuses any such path in the tree.
const HOME = '/fixture/home'
const DATA = `${HOME}/.claude/plugins/data/craftsman`
const BINDING = `${HOME}/.claude/craftsman/sessions/${SESSION}.json`
// The module ships in the craftsman plugin: its helper is the plugin's own,
// under whatever root the test kit loads the plugin from.
const isHelper = (path: string) => path.endsWith('/bin/craftsman-helper')

const QUEUE = {
  candidates: [{
    id: 7, rule: 'PHP001', confidence: 0.82, fixed: 18, rejected: 2, files: 9,
    summary: 'added strict_types', evidence: [{ file: 'src/A/**/*.php', context: 'added strict_types' }],
    rule_text: 'declare(strict_types=1) at the top of every PHP file', rule_group: 'PHP',
    rule_owner: 'symfony', default_severity: 'block', ignored: 1, scoped: 1, last_fixed: '2026-09-30 10:00:00',
    skill_path: '.claude/skills/learned-php001/SKILL.md',
    skill_preview: '---\nname: learned-php001\n---\n\n## Pattern\n\nadded strict_types\n',
  }],
  approved: [{ id: 3, rule: 'TS001', confidence: 0.96, fixed: 101, files: 40 }],
}

const PANE = {
  plugin: 'craftsman', component: 'Pane', requestId: 'instincts',
  props: { title: 'Instinct review', isFocused: true, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

const OPEN = {
  command: 'instincts', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 160 },
} as const

type Call = { argv: readonly string[]; init?: ProcessRunInit }
// What a helper answers instead of the queue: how a stale one fails.
type Reply = (argv: readonly string[]) => { exitCode: number; stdout: string; stderr: string }

// The files the host has: the given ones, and the plugin's helper unless the
// test removes it.
function present(files: Record<string, string>, helper: boolean): (path: string) => boolean {
  return path => path in files || (helper && isHelper(path))
}

// The engine beneath the mod: a host where the craftsman hooks bound this
// session, and a helper that answers the review queue and records each argv.
function host(on: On, files: Record<string, string>, queue: typeof QUEUE = QUEUE, reply?: Reply, helper = true): Call[] {
  const calls: Call[] = []
  on('env.get', ($, e) => ({ value: e.name === 'HOME' ? HOME : undefined }))
  on('session.id', () => ({ value: SESSION }))
  on('session.cwd', () => ({ value: '/work/project' }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('fs.exists', ($, e) => ({ value: present(files, helper)(e.path) }))
  on('fs.read', ($, e) => ({ value: files[e.path] ?? '' }))
  on('process.run', ($, e) => {
    calls.push({ argv: e.argv, init: e.init })
    if (!isHelper(e.argv[0])) throw new Error('not found')
    const stdout = e.argv[2] === 'review' ? JSON.stringify(queue) : `${e.argv[2]}: #${e.argv[3]}`
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false, ...reply?.(e.argv) } }
  })
  return calls
}

const BOUND = {
  [BINDING]: JSON.stringify({ host: 'claude-code', session_id: SESSION, root: '/elsewhere', data: DATA }),
}

test('the pane lists the queue the core answers, on every surface that has buttons', async ($, on) => {
  host(on, BOUND)
  await $.command.run(OPEN)
  // craftsman-ignore: DB003 (wrong: one mount per surface, no query in the loop)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /PHP001/ }))?.text).toContain('strict_types=1')
    expect(await ui.find({ type: 'Text', text: /src\/A/ })).toBeDefined()
    expect(await ui.find({ key: 'approve-7' })).toBeDefined()
    expect(await ui.find({ key: 'reject-7' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /TS001/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a candidate says what the rule is, how it was refused and what each button does', async ($, on) => {
  host(on, BOUND)
  await $.command.run(OPEN)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /declare\(strict_types=1\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /symfony pack.*blocks the write/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Accepted 18 of 20 times \(90%\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /1 craftsman-ignore, 1 relaxed by config/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Last fixed 2026-09-30/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\.claude\/skills\/learned-php001\/SKILL\.md/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /name: learned-php001/ })).toBeUndefined()
  await ui.press({ key: 'skill-7' })
  expect(await ui.find({ type: 'Text', text: /name: learned-php001/ })).toBeDefined()
  await ui.press({ key: 'skill-7' })
  expect(await ui.find({ type: 'Text', text: /name: learned-php001/ })).toBeUndefined()
  await ui.unmount()
})

test('approve hands the core the id and the project skills directory, under the bound data', async ($, on) => {
  const calls = host(on, BOUND)
  await $.command.run(OPEN)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'approve-7' })
  const approve = calls.find(call => call.argv[2] === 'approve')
  expect(approve?.argv[0]).toMatch(/\/bin\/craftsman-helper$/)
  expect(approve?.argv.slice(1)).toEqual(['instincts', 'approve', '7', '/work/project/.claude/skills'])
  expect(approve?.init?.env?.CRAFTSMAN_PLUGIN_DATA).toBe(DATA)
  expect(approve?.init?.env?.CRAFTSMAN_SESSION_ID).toBe(SESSION)
  expect(await ui.find({ type: 'Text', text: 'approve: #7' })).toBeDefined()
  await ui.unmount()
})

test('reject carries the id alone', async ($, on) => {
  const calls = host(on, BOUND)
  await $.command.run(OPEN)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'reject-7' })
  expect(calls.find(call => call.argv[2] === 'reject')?.argv.slice(1)).toEqual(['instincts', 'reject', '7'])
  await ui.unmount()
})

test('a binding for another session lends it no data directory', async ($, on) => {
  const calls = host(on, {
    [BINDING]: JSON.stringify({ host: 'claude-code', session_id: 'someone-else', root: '/elsewhere', data: DATA }),
  })
  await $.command.run(OPEN)
  const review = calls.find(call => call.argv[2] === 'review')
  expect(review?.init?.env?.CRAFTSMAN_SESSION_ID).toBe(SESSION)
  expect(review?.init?.env?.CRAFTSMAN_PLUGIN_DATA).toBeUndefined()
})

test('a plugin without its helper says where it looked', async ($, on) => {
  host(on, {}, QUEUE, undefined, false)
  await $.command.run(OPEN)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /craftsman-helper not found/ })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: /plugin root:/ }))?.text).toMatch(/\/bin\/craftsman-helper$/)
  await ui.unmount()
})

// The pane scrolls as one block (mods reference, render sites), and
// e.viewport.rows is the whole window, never the pane. No candidate is cut.
test('every candidate is drawn with its buttons, whatever the viewport says', async ($, on) => {
  const first = QUEUE.candidates[0]
  host(on, BOUND, { ...QUEUE, candidates: [first, { ...first, id: 8, rule: 'PHP002' }, { ...first, id: 9, rule: 'PHP003' }] })
  await $.command.run(OPEN)
  for (const viewport of [undefined, { columns: 120, rows: 20, isFullscreen: false }]) {
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal', ...(viewport === undefined ? {} : { viewport }) })
    expect(await ui.find({ key: 'approve-7' })).toBeDefined()
    expect(await ui.find({ key: 'approve-8' })).toBeDefined()
    expect(await ui.find({ key: 'approve-9' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /below the fold/ })).toBeUndefined()
    await ui.unmount()
  }
})

// A helper that does not speak the protocol prints a usage text (4.12.3's,
// reached through a stale session binding before the module moved into the
// plugin, measured 2026-10-20). The pane names the helper it ran, so the path
// is read in the pane and not guessed.
test('a failed review names the helper that was run', async ($, on) => {
  host(on, BOUND, QUEUE, () => ({ exitCode: 1, stdout: '', stderr: 'Instinct pipeline (ADR-0020): corrections -> candidates\nUsage: instincts.py' }))
  await $.command.run(OPEN)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const failed = await ui.find({ type: 'Text', text: /instincts review failed/ })
  expect(failed?.text).toContain('/bin/craftsman-helper')
  expect(failed?.text).toContain('Instinct pipeline (ADR-0020)')
  await ui.unmount()
})
