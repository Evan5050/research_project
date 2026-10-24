// Typed client for the Julia API. Mirrors backend/src/api.jl; contract in docs/API.md.
// The browser holds the ExperimentContext; every numerical request sends it back.

export type Mode = 'demo' | 'upload'
export type Observation = { x: number; y: number }

export type ExperimentContext = {
  mode: Mode
  session_id: string
  dataset_id: string
  observed: Observation[]
  candidate_x: number[]
  revealed_x: number[]
  response_sd: number | null
  x_unit: string
  y_unit: string
  x_label: string
  y_label: string
  source_name: string
}

export type FieldError = { field: string; message: string }
export type ApiErrorBody = { error: string; fields: FieldError[] }

export class ApiError extends Error {
  readonly status: number
  readonly fields: FieldError[]
  constructor(status: number, body: ApiErrorBody | null) {
    super(body?.error ?? `HTTP ${status}`)
    this.status = status
    this.fields = body?.fields ?? []
  }
}

export type Health = { status: string; service: string; api_version: string; julia_version: string }
export type Ready = { ready: boolean; checks: { name: string; ok: boolean }[] }

export type Axis = { column: string; label: string; unit: string }
export type Provenance = {
  name: string
  description: string
  credit: string
  collected_by_nextlab_user: boolean
  documentation_url: string
  source_file_url: string
  package_metadata_url: string
  source_file_sha256: string
  package_license: string
  x: Axis
  y: Axis
  limitations: string[]
}

export type ModelId = 'linear' | 'sqrt' | 'restricted_quadratic'
export type Status = 'ok' | 'no_candidates' | 'insufficient_data' | 'invalid_input' | 'no_valid_fit'
export type Diagnostic = { level: 'error' | 'warning' | 'info'; code: string; message: string }

export type ModelResult = {
  id: ModelId
  name: string
  formula: string
  note: string
  fitted: boolean
  a: number | null
  b: number | null
  failure: string | null
  fit_rmse_setting_means: number | null
  grouped_cv_mse: number | null
  grouped_cv_rmse: number | null
  support: number | null
  strongly_down_weighted: boolean | null
  adequacy: { assessed: boolean; standardized_rms: number | null; conflicts_with_noise: boolean | null; note: string }
}

export type Noise = {
  source: 'repeats' | 'user' | 'unknown'
  sd_individual: number | null
  df: number
  settings_with_repeats: number
  mean_sd_by_setting: (number | null)[]
  representative_mean_variance: number | null
  representative_mean_sd: number | null
  note: string
}

export type Recommendation = {
  x: number
  kind: 'disagreement' | 'space_filling'
  fallback_reason: 'dominant_model' | 'predictions_agree' | null
  distance_to_nearest_measured: number | null
  score: number
  spread: number
  predictions: { id: ModelId; name: string; y: number | null; support: number | null; share_of_spread: number | null }[]
  separation: { ratio: number | null; label: 'inconclusive' | 'separated' | 'unassessed'; setting_mean_sd: number | null; note: string }
  feasible_range: { lo: number; hi: number } | null
  n_unmeasured: number
  method: string
}

export type Analysis = {
  method_version: string
  units: { x: string; y: string }
  diagnostics: Diagnostic[]
  status: Status
  data: {
    n_observations: number
    n_settings: number
    revision: string
    settings: { x: number; mean: number; n: number; repeat_sd: number | null; mean_sd: number | null }[]
  } | null
  noise: Noise | null
  models: ModelResult[]
  support: { method: string; s2: number | null; s2_source: string; numerical_floor: number } | null
  recommendation: Recommendation | null
  candidate_scores: { x: number; score: number | null; spread: number | null }[]
  all_models_inadequate: boolean | null
  explanation: string
}

export type Curves = { x: number[]; models: { id: ModelId; y: number[] | null }[]; ensemble: number[] | null } | null

export type FrozenModel = {
  id: ModelId
  name: string
  formula: string
  note: string
  fitted: boolean
  a: number | null
  b: number | null
  support: number | null
  strongly_down_weighted: boolean | null
  grouped_cv_rmse: number | null
  predicted_y: number | null
}

/** Immutable prediction snapshot. Send it back unchanged; the server verifies snapshot_id. */
export type Snapshot = {
  kind: 'nextlab-prediction-snapshot'
  api_version: string
  snapshot_id: string
  context_revision: string
  session_id: string
  mode: Mode
  dataset_id: string
  record: {
    method_version: string
    created_at: string
    data_revision: string
    n_observations: number
    n_settings: number
    x: number
    units: { x: string; y: string }
    acquisition: {
      kind: string
      fallback_reason: string | null
      score: number
      spread: number
      separation_label: string
      separation_ratio: number | null
      method: string
    }
    models: FrozenModel[]
    noise: { source: string; sd_individual: number | null; df: number; representative_mean_sd: number | null; note: string }
  }
  selection: { kind: string; fallback_reason: string | null; method: string; explanation: string }
  diagnostic_state: { status: Status; all_models_inadequate: boolean | null; separation: string; noise_source: string; codes: string[] }
}

export type Comparison = {
  observed_mean: number
  n_observations: number
  setting_mean_sd: number | null
  models: { id: ModelId; name: string; predicted_y: number; error: number; abs_error: number; error_in_mean_sds: number | null }[]
  closest_model: ModelId | null
  note: string
}

type Revisioned = { revision: string; session_id: string }
export type StartResponse = {
  context: ExperimentContext
  revision: string
  dataset: Provenance
  counts: { lengths_measured: number; observations: number; remaining_lengths: number }
}
export type AnalyzeResponse = Revisioned & { status: Status; analysis: Analysis; curves: Curves }
export type RecommendResponse = AnalyzeResponse & { snapshot: Snapshot | null }
export type OutcomeResponse = Revisioned & {
  snapshot_id: string
  x: number
  observations: Observation[]
  comparison: Comparison
  refit_performed: false
  updated_context: ExperimentContext
  updated_revision: string
}
export type Bounds = { lo: number; hi: number; step: number } | { lo: number; hi: number; n: number }
export type UploadRequest = {
  csv: string
  x_column?: string | number
  y_column?: string | number
  bounds?: Bounds
  candidate_x?: number[]
  response_sd?: number | null
  x_unit?: string
  y_unit?: string
  x_label?: string
  y_label?: string
  source_name?: string
}
export type UploadResponse = {
  context: ExperimentContext
  revision: string
  columns: string[]
  x_column: string
  y_column: string
  counts: { observations: number; settings: number; candidates: number; candidates_outside_observed_range: number }
  observed_range: { lo: number; hi: number }
}
export type PreviewResponse = {
  columns: string[]
  n_rows: number
  rows: string[][]
  column_info: { name: string; numeric_rows: number; other_rows: number; min: number | null; max: number | null; distinct: number }[]
  problems: FieldError[]
}
export type ExportResponse = {
  record_id: string
  exported_at: string
  record: Record<string, unknown> & { format: 'nextlab-experiment-record-2'; run_type: string }
  observations_csv: string
}
export type BenchmarkResponse = {
  meta: Record<string, unknown>
  current_method_version: string
  results_match_current_method: boolean
  primary_endpoint: { n_settings: number; n_observations: number }
  verdicts: { baseline: string; better: number; no_clear: number; worse: number }[]
  paired: Record<string, string | number | null>[]
  summary: Record<string, string | number | null>[]
  nextlab_choices: Record<string, string | number | null>[]
  reproduce: { command: string; protocol: string; results_dir: string }
}

/** Thrown when a response belongs to an older context (reset, new data, or a changed setting). */
export class StaleResponseError extends Error {}

/** Reject a response computed for a different session or revision than the one now on screen. */
export function assertCurrent<T extends Revisioned>(resp: T, expected: { revision: string; session_id: string }): T {
  if (resp.session_id !== expected.session_id || resp.revision !== expected.revision) {
    throw new StaleResponseError('Response is for an older experiment state and was ignored.')
  }
  return resp
}

/** Status 0 means the Julia backend could not be reached at all. */
export const BACKEND_UNAVAILABLE = 0

async function call<T>(method: 'GET' | 'POST', url: string, body?: unknown): Promise<T> {
  let resp: Response
  try {
    resp = await fetch(url, {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError(BACKEND_UNAVAILABLE, { error: 'The Julia backend is not responding.', fields: [] })
  }
  const text = await resp.text()
  let parsed: unknown = null
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    // A proxy error page or an empty 413 body is not JSON.
  }
  if (resp.status === 502 || resp.status === 503 || resp.status === 504) {
    throw new ApiError(BACKEND_UNAVAILABLE, { error: 'The Julia backend is not responding.', fields: [] })
  }
  if (!resp.ok) throw new ApiError(resp.status, parsed as ApiErrorBody | null)
  return parsed as T
}

export const benchmarkFileUrl = (name: 'runs.csv' | 'summary.csv' | 'paired.csv' | 'nextlab_choices.csv' | 'meta.json') =>
  `/api/benchmark/files/${name}`

export const fetchHealth = () => call<Health>('GET', '/api/health')
export const fetchReady = () => call<Ready>('GET', '/api/ready')
export const startDemo = () => call<StartResponse>('POST', '/api/demo/start', {})
export const analyze = (context: ExperimentContext) => call<AnalyzeResponse>('POST', '/api/analyze', { context })
export const recommend = (context: ExperimentContext) => call<RecommendResponse>('POST', '/api/recommend', { context })
export const revealDemo = (context: ExperimentContext, snapshot: Snapshot) =>
  call<OutcomeResponse>('POST', '/api/demo/reveal', { context, snapshot })
export const observe = (context: ExperimentContext, snapshot: Snapshot, y: number[]) =>
  call<OutcomeResponse>('POST', '/api/observe', { context, snapshot, y })
export const upload = (req: UploadRequest) => call<UploadResponse>('POST', '/api/upload', req)
export const exportRecord = (context: ExperimentContext, history: { snapshot: Snapshot; updated: boolean }[]) =>
  call<ExportResponse>('POST', '/api/export', { context, history })
export const previewUpload = (csv: string) => call<PreviewResponse>('POST', '/api/upload/preview', { csv })
export const feasibleSettings = (req: { lo?: number; hi?: number; step?: number; candidate_x?: number[] }) =>
  call<{ candidate_x: number[] }>('POST', '/api/feasible', req)
export const SAMPLE_CSV_URL = '/api/sample.csv'
export const fetchBenchmark = () => call<BenchmarkResponse>('GET', '/api/benchmark')
