// Typed calls to the Julia API. The frontend holds no dataset values of its own.

export type Health = {
  status: string
  service: string
  api_version: string
  julia_version: string
}

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

export type ReplayState = {
  observed: { x: number; y: number }[]
  candidate_x: number[]
  revealed_order: number[]
  lengths_measured: number
  observations: number
  remaining_lengths: number
}

export type PendulumPayload = { provenance: Provenance; state: ReplayState }

async function getJson<T>(url: string, init?: RequestInit): Promise<T> {
  const resp = await fetch(url, init)
  if (!resp.ok) throw new Error(`HTTP ${resp.status} from ${url}`)
  return (await resp.json()) as T
}

export async function fetchHealth(): Promise<Health> {
  const body = await getJson<Partial<Health>>('/api/health')
  if (body.status !== 'ok' || typeof body.julia_version !== 'string') {
    throw new Error('Unexpected /api/health response')
  }
  return body as Health
}

export const fetchPendulum = () => getJson<PendulumPayload>('/api/pendulum')

export const resetPendulum = () => getJson<PendulumPayload>('/api/pendulum/reset', { method: 'POST' })
