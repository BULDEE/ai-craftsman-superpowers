export type CockpitEvidence = { file: string; context: string }

export type CockpitCandidate = {
  id: number
  rule: string
  confidence: number
  fixed: number
  rejected: number
  files: number
  summary: string
  evidence: CockpitEvidence[]
  rule_text: string
  rule_group: string
  rule_owner: string
  default_severity: string
  ignored: number
  scoped: number
  last_fixed: string
  skill_path: string
  skill_preview: string
}

export type CockpitApproved = {
  id: number
  rule: string
  confidence: number
  fixed: number
  files: number
}

export type CockpitQueue = { candidates: CockpitCandidate[]; approved: CockpitApproved[] }

export type CockpitView =
  | { kind: 'loading' }
  | { kind: 'missing'; tried: string[] }
  | { kind: 'failed'; message: string }
  | { kind: 'ready'; queue: CockpitQueue; notice: string }

// What `craftsman-helper session status` prints: the session's quality state
// the hooks keep (hooks/lib/session_status.py).
export type CockpitTests = { verdict: 'red' | 'verified' | 'empty' | 'unverified' | 'not-run'; red_runs: string[] }

export type CockpitPulse = {
  since: number | null
  writes: number
  files: number
  blocked: number
  warned: number
  open: { file: string; rules: string[] }[]
  tests: CockpitTests
  compactions: number
}

declare module 'claude-code' {
  interface PluginState {
    craftsman: { view: CockpitView; preview: number; pulse: CockpitPulse | null; turnStart: CockpitPulse | null }
  }
}
