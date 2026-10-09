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

declare module 'claude-code' {
  interface PluginState {
    'craftsman-cockpit': { view: CockpitView; preview: number }
  }
}
