import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const SESSION = 'sid-1'
// Not under /home/<user>/: the secrets scan refuses any such path in the tree.
const HOME = '/fixture/home'
const isHelper = (path: string) => path.endsWith('/bin/craftsman-helper')

// What `craftsman-helper session status` prints (hooks/lib/session_status.py).
const QUIET = {
  since: 1, writes: 0, files: 0, blocked: 0, warned: 0, open: [],
  tests: { verdict: 'not-run', red_runs: [] }, compactions: 0,
}
const BUSY = {
  ...QUIET, writes: 12, files: 5, blocked: 2, warned: 3,
  open: [{ file: '/work/project/src/Domain/Order.php', rules: ['LAYER001'] }],
  tests: { verdict: 'red', red_runs: ['vendor/bin/phpunit'] },
}

const BAND = {
  plugin: 'craftsman', component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 4, bodyColumns: 120, scroll: { offset: 0, bodyRows: 4 }, view: {} },
} as const

// A host whose helper answers each `session status` with the next state in
// line, the last one standing once the line runs out.
function host(on: On, states: object[], beneath = ''): string[][] {
  const calls: string[][] = []
  on('env.get', () => ({ value: HOME }))
  on('session.id', () => ({ value: SESSION }))
  on('session.cwd', () => ({ value: '/work/project' }))
  on('session.start', () => ({ cwd: '/work/project' }))
  on('command.register', () => ({ value: undefined }))
  on('fs.exists', ($, e) => ({ value: isHelper(e.path) }))
  on('fs.read', () => ({ value: '' }))
  on('classic.PostToolUse', () => ({}))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: beneath }))
  // What the mods after this one draw in the band, which it must keep.
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['another mod'] }))
  on('process.run', ($, e) => {
    calls.push([...e.argv])
    const state = states[Math.min(calls.length - 1, states.length - 1)]
    return { value: { exitCode: 0, stdout: JSON.stringify(state), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  return calls
}

const start = { surface: 'terminal', isInteractive: true, cwd: '/work/project' } as const

test('a session that did nothing draws nothing above the prompt', async ($, on) => {
  host(on, [QUIET])
  await $.session.start(start)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /craftsman/ })).toBeUndefined()
  await ui.unmount()
})

test('the band says what is open, what warned and what the tests say', async ($, on) => {
  const calls = host(on, [BUSY])
  await $.session.start(start)
  expect(calls[0]?.slice(1)).toEqual(['session', 'status'])
  // craftsman-ignore: DB003 (wrong: one mount per surface, no query in the loop)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: /12 writes in 5 files/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /1 open: LAYER001 Order\.php/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /3 warnings/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /tests red: vendor\/bin\/phpunit/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'another mod' })).toBeDefined()
    await ui.unmount()
  }
})

test('a write the hooks judged moves the band; a read does not ask the core', async ($, on) => {
  const calls = host(on, [QUIET, BUSY])
  await $.session.start(start)
  await $.classic.PostToolUse({ tool_name: 'Read', tool_input: { file_path: '/work/project/README.md' } })
  expect(calls.length).toBe(1)
  await $.classic.PostToolUse({ tool_name: 'Write', tool_input: { file_path: '/work/project/src/Domain/Order.php' } })
  expect(calls.length).toBe(2)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /12 writes in 5 files/ })).toBeDefined()
  await ui.unmount()
})

test('a turn that wrote leaves a receipt under the answer', async ($, on) => {
  host(on, [QUIET, BUSY])
  await $.session.start(start)
  await $.turn.start({ turnId: 't1' })
  const answer = await $.turn.complete({ turnId: 't1', answer: 'done', durationMs: 10, isAborted: false, usage: null })
  expect(answer.text).toBe('craftsman: 12 writes, 2 blocked, 3 warnings · 1 open: LAYER001 Order.php · tests red: vendor/bin/phpunit')
})

test('one write reads as one, and what the mods after this one say stays under it', async ($, on) => {
  const ONE = { ...QUIET, writes: 1, files: 1, warned: 1 }
  host(on, [QUIET, ONE], 'their line')
  await $.session.start(start)
  await $.turn.start({ turnId: 't3' })
  const answer = await $.turn.complete({ turnId: 't3', answer: 'done', durationMs: 10, isAborted: false, usage: null })
  expect(answer.text).toBe('craftsman: 1 write, 0 blocked, 1 warning · nothing open · tests not run | their line')
})

// What Claude Code 2.1.310 passes back when no mod after this one answers: the
// answer, which the receipt must not repeat under itself.
test('the receipt does not repeat the answer it sits under', async ($, on) => {
  host(on, [QUIET, BUSY], 'done')
  await $.session.start(start)
  await $.turn.start({ turnId: 't4' })
  const answer = await $.turn.complete({ turnId: 't4', answer: 'done', durationMs: 10, isAborted: false, usage: null })
  expect(answer.text).toBe('craftsman: 12 writes, 2 blocked, 3 warnings · 1 open: LAYER001 Order.php · tests red: vendor/bin/phpunit')
})

test('a turn that only talked leaves no receipt', async ($, on) => {
  host(on, [BUSY, BUSY])
  await $.session.start(start)
  await $.turn.start({ turnId: 't2' })
  const answer = await $.turn.complete({ turnId: 't2', answer: 'here is why', durationMs: 10, isAborted: false, usage: null })
  expect(answer.text).toBe('')
})

test('a core that cannot answer hides the band instead of drawing a guess', async ($, on) => {
  host(on, [{ unexpected: true }])
  await $.session.start(start)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /craftsman/ })).toBeUndefined()
  await ui.unmount()
})
