// Workbench state for the built-in pendulum replay.
//
// Every async result carries the `epoch` it was requested in. Reset bumps the epoch, so
// responses from before a reset are ignored. Results must also match the expected
// revision/session (see `assertCurrent` in api.ts). The workflow is a strict sequence:
// analyzed -> frozen snapshot -> revealed outcome -> explicit update -> analyzed ...

import type {
  AnalyzeResponse,
  ExperimentContext,
  FieldError,
  ModelResult,
  Noise,
  OutcomeResponse,
  Provenance,
  RecommendResponse,
  Snapshot,
  StartResponse,
} from './api'

export type Pending = null | 'start' | 'analyze' | 'recommend' | 'reveal' | 'update'

export type UiError = { message: string; fields: FieldError[]; unavailable: boolean }

export type Cycle = {
  snapshot: Snapshot
  outcome: OutcomeResponse
  before: { models: ModelResult[]; noise: Noise | null }
  after: { models: ModelResult[]; noise: Noise | null } | null
}

export type State = {
  epoch: number
  pending: Pending
  error: UiError | null
  dataset: Provenance | null
  context: ExperimentContext | null
  revision: string | null
  analysis: AnalyzeResponse | null
  previous: AnalyzeResponse | null // fit before the latest update, drawn faintly for comparison
  recommendation: RecommendResponse | null
  snapshot: Snapshot | null // frozen, pending reveal
  outcome: OutcomeResponse | null // revealed, waiting for an explicit update
  complete: boolean // no remaining recorded lengths
  cycles: Cycle[]
}

export const initialState: State = {
  epoch: 0,
  pending: null,
  error: null,
  dataset: null,
  context: null,
  revision: null,
  analysis: null,
  previous: null,
  recommendation: null,
  snapshot: null,
  outcome: null,
  complete: false,
  cycles: [],
}

export type Action =
  | { type: 'reset'; epoch: number }
  | { type: 'request'; epoch: number; pending: Exclude<Pending, null> }
  | { type: 'failed'; epoch: number; error: UiError }
  | { type: 'started'; epoch: number; start: StartResponse }
  | { type: 'analyzed'; epoch: number; resp: AnalyzeResponse }
  | { type: 'recommended'; epoch: number; resp: RecommendResponse }
  | { type: 'revealed'; epoch: number; resp: OutcomeResponse }
  | { type: 'updated'; epoch: number; resp: AnalyzeResponse }

const current = (s: State, r: { revision: string; session_id: string }) =>
  s.context !== null && r.revision === s.revision && r.session_id === s.context.session_id

export function reducer(s: State, a: Action): State {
  if (a.type === 'reset') return { ...initialState, epoch: a.epoch, pending: 'start' }
  if (a.epoch !== s.epoch) return s // stale: requested before the last reset
  switch (a.type) {
    case 'request':
      return { ...s, pending: a.pending, error: null }
    case 'failed':
      return { ...s, pending: null, error: a.error }
    case 'started':
      return {
        ...initialState,
        epoch: s.epoch,
        pending: null,
        dataset: a.start.dataset,
        context: a.start.context,
        revision: a.start.revision,
      }
    case 'analyzed':
      if (!current(s, a.resp)) return s
      return { ...s, pending: null, analysis: a.resp }
    case 'recommended':
      if (!current(s, a.resp) || s.snapshot || s.outcome) return s
      return {
        ...s,
        pending: null,
        analysis: a.resp,
        recommendation: a.resp,
        snapshot: a.resp.snapshot,
        complete: a.resp.status === 'no_candidates',
      }
    case 'revealed': {
      if (!current(s, a.resp) || !s.snapshot || a.resp.snapshot_id !== s.snapshot.snapshot_id || !s.analysis) return s
      const before = { models: s.analysis.analysis.models, noise: s.analysis.analysis.noise }
      return {
        ...s,
        pending: null,
        outcome: a.resp,
        cycles: [...s.cycles, { snapshot: s.snapshot, outcome: a.resp, before, after: null }],
      }
    }
    case 'updated': {
      const o = s.outcome
      if (!o || a.resp.revision !== o.updated_revision || a.resp.session_id !== o.updated_context.session_id) return s
      const cycles = s.cycles.map((c, i) =>
        i === s.cycles.length - 1 ? { ...c, after: { models: a.resp.analysis.models, noise: a.resp.analysis.noise } } : c,
      )
      return {
        ...s,
        pending: null,
        context: o.updated_context,
        revision: o.updated_revision,
        previous: s.analysis,
        analysis: a.resp,
        recommendation: null,
        snapshot: null,
        outcome: null,
        complete: o.updated_context.candidate_x.length === 0,
        cycles,
      }
    }
  }
}

/** Which workflow step is next, for the step bar and the primary action. */
export type Step = 'compare' | 'recommend' | 'reveal' | 'update' | 'done'
export function nextStep(s: State): Step {
  if (s.complete) return 'done'
  if (!s.analysis) return 'compare'
  if (s.outcome) return 'update'
  if (s.snapshot) return 'reveal'
  return 'recommend'
}
