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
    'craftsman-cockpit': { view: CockpitView }
  }
}
