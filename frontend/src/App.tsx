import { useEffect, useState } from 'react'

type Health = {
  status: string
  service: string
  api_version: string
  julia_version: string
}

type BackendState =
  | { kind: 'checking' }
  | { kind: 'ok'; health: Health }
  | { kind: 'error'; message: string }

async function fetchHealth(): Promise<Health> {
  const resp = await fetch('/api/health')
  if (!resp.ok) throw new Error(`HTTP ${resp.status} from /api/health`)
  const body = (await resp.json()) as Partial<Health>
  if (body.status !== 'ok' || typeof body.julia_version !== 'string') {
    throw new Error('Unexpected /api/health response')
  }
  return body as Health
}

function App() {
  const [state, setState] = useState<BackendState>({ kind: 'checking' })

  const load = () =>
    fetchHealth()
      .then((health) => setState({ kind: 'ok', health }))
      .catch((err: unknown) =>
        setState({ kind: 'error', message: err instanceof Error ? err.message : String(err) }),
      )

  const check = () => {
    setState({ kind: 'checking' })
    load()
  }

  useEffect(() => {
    load()
  }, [])

  return (
    <main>
      <h1>NextLab</h1>
      <p>Compare candidate models, choose the next measurement, and test predictions honestly.</p>
      <section aria-live="polite" data-testid="backend-status">
        {state.kind === 'checking' && <p>Checking Julia backend…</p>}
        {state.kind === 'ok' && (
          <p className="ok">
            Julia backend responded: {state.health.service} (API {state.health.api_version}, Julia{' '}
            {state.health.julia_version})
          </p>
        )}
        {state.kind === 'error' && (
          <p className="error">Julia backend did not respond: {state.message}</p>
        )}
        <button onClick={check}>Check again</button>
      </section>
    </main>
  )
}

export default App
