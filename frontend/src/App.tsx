import { useEffect, useState } from 'react'
import { fetchHealth, startDemo, type Health, type StartResponse } from './api'

type Loadable<T> = { kind: 'loading' } | { kind: 'ok'; value: T } | { kind: 'error'; message: string }

const errorText = (err: unknown) => (err instanceof Error ? err.message : String(err))

function DatasetPanel({ data, onReset }: { data: StartResponse; onReset: () => void }) {
  const { dataset: p, context: s, counts } = data
  return (
    <section>
      <h2>Built-in data: {p.name}</h2>
      <p>{p.description}</p>
      <p>
        Credit: {p.credit} Not collected by the NextLab user. License: {p.package_license}.{' '}
        <a href={p.documentation_url}>Documentation</a> · <a href={p.source_file_url}>Source file</a>
      </p>

      <h3>Declared starting scenario</h3>
      <p>
        Starts with the three shortest recorded lengths (chosen by length order, not by outcome).
        Measured so far: <strong>{counts.lengths_measured} lengths</strong>,{' '}
        <strong>{counts.observations} reported period observations</strong>.
      </p>
      <table>
        <thead>
          <tr>
            <th>
              {p.x.label} ({p.x.unit})
            </th>
            <th>
              {p.y.label} ({p.y.unit})
            </th>
          </tr>
        </thead>
        <tbody>
          {s.observed.map((o, i) => (
            <tr key={i}>
              <td>{o.x}</td>
              <td>{o.y}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p>
        Remaining recorded lengths ({counts.remaining_lengths}), periods not yet revealed:{' '}
        {s.candidate_x.map((x) => `${x} ${p.x.unit}`).join(', ')}
      </p>
      <button onClick={onReset}>Reset to starting scenario</button>

      <h3>Limitations</h3>
      <ul>
        {p.limitations.map((l) => (
          <li key={l}>{l}</li>
        ))}
      </ul>
    </section>
  )
}

function App() {
  const [health, setHealth] = useState<Loadable<Health>>({ kind: 'loading' })
  const [pendulum, setPendulum] = useState<Loadable<StartResponse>>({ kind: 'loading' })

  const load = () => {
    fetchHealth()
      .then((value) => setHealth({ kind: 'ok', value }))
      .catch((err: unknown) => setHealth({ kind: 'error', message: errorText(err) }))
    startDemo()
      .then((value) => setPendulum({ kind: 'ok', value }))
      .catch((err: unknown) => setPendulum({ kind: 'error', message: errorText(err) }))
  }

  const check = () => {
    setHealth({ kind: 'loading' })
    setPendulum({ kind: 'loading' })
    load()
  }

  const reset = () =>
    startDemo()
      .then((value) => setPendulum({ kind: 'ok', value }))
      .catch((err: unknown) => setPendulum({ kind: 'error', message: errorText(err) }))

  useEffect(() => {
    load()
  }, [])

  return (
    <main>
      <h1>NextLab</h1>
      <p>Compare candidate models, choose the next measurement, and test predictions honestly.</p>
      <section aria-live="polite" data-testid="backend-status">
        {health.kind === 'loading' && <p>Checking Julia backend…</p>}
        {health.kind === 'ok' && (
          <p className="ok">
            Julia backend responded: {health.value.service} (API {health.value.api_version}, Julia{' '}
            {health.value.julia_version})
          </p>
        )}
        {health.kind === 'error' && <p className="error">Julia backend did not respond: {health.message}</p>}
        <button onClick={check}>Check again</button>
      </section>
      {pendulum.kind === 'loading' && <p>Loading dataset…</p>}
      {pendulum.kind === 'error' && <p className="error">Dataset did not load: {pendulum.message}</p>}
      {pendulum.kind === 'ok' && <DatasetPanel data={pendulum.value} onReset={reset} />}
    </main>
  )
}

export default App
