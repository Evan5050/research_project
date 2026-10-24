import { useCallback, useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import {
  ApiError,
  BACKEND_UNAVAILABLE,
  analyze,
  exportRecord,
  recommend,
  revealDemo,
  startDemo,
} from './api'
import { initialState, nextStep, reducer, type Action, type UiError } from './state'
import { ExperimentPlot } from './Plot'
import {
  Assumptions,
  BenchmarkSection,
  ChangePanel,
  ComparisonPanel,
  History,
  ModelCards,
  RecommendationPanel,
  StepBar,
} from './Panels'
import { sig, withUnit } from './format'

function toUiError(e: unknown): UiError {
  if (e instanceof ApiError) {
    return { message: e.message, fields: e.fields, unavailable: e.status === BACKEND_UNAVAILABLE }
  }
  return { message: e instanceof Error ? e.message : String(e), fields: [], unavailable: false }
}

function download(obj: unknown, filename: string) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(obj, null, 2)], { type: 'application/json' }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

function App() {
  const [s, dispatch] = useReducer(reducer, initialState)
  const stateRef = useRef(s)
  useLayoutEffect(() => {
    stateRef.current = s
  }, [s])
  const epochRef = useRef(0)
  // Synchronous guard: a second click in the same tick, before React disables the button, sends nothing.
  const inFlight = useRef<number | null>(null)

  /** Run one request in the current epoch; results from an older epoch are dropped by the reducer. */
  const run = useCallback(
    async <T,>(pending: Exclude<typeof s.pending, null>, call: () => Promise<T>, done: (r: T, epoch: number) => Action) => {
      const epoch = epochRef.current
      if (inFlight.current === epoch) return null
      inFlight.current = epoch
      dispatch({ type: 'request', epoch, pending })
      try {
        const r = await call()
        dispatch(done(r, epoch))
        return r
      } catch (e) {
        dispatch({ type: 'failed', epoch, error: toUiError(e) })
        return null
      } finally {
        if (inFlight.current === epoch) inFlight.current = null
      }
    },
    [],
  )

  const start = useCallback(async () => {
    epochRef.current += 1
    const epoch = epochRef.current
    dispatch({ type: 'reset', epoch })
    try {
      const st = await startDemo()
      dispatch({ type: 'started', epoch, start: st })
      dispatch({ type: 'request', epoch, pending: 'analyze' })
      const an = await analyze(st.context)
      dispatch({ type: 'analyzed', epoch, resp: an })
    } catch (e) {
      dispatch({ type: 'failed', epoch, error: toUiError(e) })
    }
  }, [])

  useEffect(() => {
    void start()
  }, [start])

  const step = nextStep(s)
  const busy = s.pending !== null

  const onRecommend = () => {
    const ctx = stateRef.current.context
    if (ctx) void run('recommend', () => recommend(ctx), (resp, epoch) => ({ type: 'recommended', epoch, resp }))
  }
  const onReveal = () => {
    const { context, snapshot } = stateRef.current
    if (context && snapshot)
      void run('reveal', () => revealDemo(context, snapshot), (resp, epoch) => ({ type: 'revealed', epoch, resp }))
  }
  const onUpdate = () => {
    const o = stateRef.current.outcome
    if (o) void run('update', () => analyze(o.updated_context), (resp, epoch) => ({ type: 'updated', epoch, resp }))
  }
  const onCompareRetry = () => {
    const ctx = stateRef.current.context
    if (ctx) void run('analyze', () => analyze(ctx), (resp, epoch) => ({ type: 'analyzed', epoch, resp }))
    else void start()
  }
  const onExport = async () => {
    const { context, cycles } = stateRef.current
    if (!context) return
    try {
      const rec = await exportRecord(context, cycles.map((c) => c.snapshot))
      download(rec, `nextlab-record-${rec.revision.slice(0, 8)}.json`)
    } catch (e) {
      dispatch({ type: 'failed', epoch: epochRef.current, error: toUiError(e) })
    }
  }

  const ds = s.dataset
  const ctx = s.context
  const an = s.analysis?.analysis ?? null
  const units = { x: ctx?.x_unit ?? 'm', y: ctx?.y_unit ?? 's' }
  const xs = ctx?.observed.map((o) => o.x) ?? []
  const measured: [number, number] = [Math.min(...xs), Math.max(...xs)]
  const lengthsMeasured = new Set(xs).size
  const lastCycle = s.cycles.length ? s.cycles[s.cycles.length - 1] : null

  const primaryLabel =
    step === 'done'
      ? null
      : step === 'compare'
        ? s.pending ? 'Comparing models…' : 'Compare models'
        : step === 'recommend'
          ? s.pending === 'recommend' ? 'Freezing predictions…' : 'Recommend next measurement'
          : step === 'reveal'
            ? s.pending === 'reveal' ? 'Revealing…' : `Reveal recorded measurement at ${s.snapshot?.record.x} ${units.x}`
            : s.pending === 'update' ? 'Refitting…' : 'Update models with the new observations'
  const onPrimary = () => {
    const now = nextStep(stateRef.current)
    if (now === 'compare') onCompareRetry()
    else if (now === 'recommend') onRecommend()
    else if (now === 'reveal') onReveal()
    else if (now === 'update') onUpdate()
  }

  return (
    <div className="app">
      <header className="top">
        <div>
          <h1>NextLab</h1>
          <p className="purpose">Choose your next measurement, commit to predictions, then check them.</p>
        </div>
        <div className="source">
          <strong>Recorded pendulum measurements</strong>
          {ds && (
            <span className="dim">
              {' '}
              · {ds.name}, credited to Calvin College physics students under Prof. Steve Plath · {ds.package_license} ·{' '}
              <a href={ds.documentation_url} target="_blank" rel="noreferrer">
                source
              </a>
            </span>
          )}
        </div>
        <div className="top-actions">
          <button onClick={() => void onExport()} disabled={!ctx || busy}>
            Download record
          </button>
          <button onClick={() => void start()}>Reset demo</button>
        </div>
      </header>

      <StepBar step={step} cycle={s.cycles.filter((c) => c.after).length + (step === 'done' ? 0 : 1)} />

      {s.error && (
        <div className={`banner ${s.error.unavailable ? 'unavailable' : 'invalid'}`} role="alert">
          {s.error.unavailable ? (
            <>
              <strong>Backend unavailable.</strong> The Julia server did not respond. Start it with{' '}
              <code>julia --project=backend --threads=auto,1 backend/scripts/serve.jl</code>, then{' '}
              <button onClick={() => (ctx ? onCompareRetry() : void start())}>Retry</button>
            </>
          ) : (
            <>
              <strong>{s.error.message}</strong>
              {s.error.fields.length > 0 && (
                <ul>
                  {s.error.fields.map((f, i) => (
                    <li key={i}>
                      <code>{f.field}</code>: {f.message}
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
        </div>
      )}

      <main className="bench">
        <div className="left">
          {ctx && an && s.analysis ? (
            <ExperimentPlot
              curves={s.analysis.curves}
              previousCurves={s.previous && !s.snapshot && !s.outcome ? s.previous.curves : null}
              models={an.models}
              observed={ctx.observed}
              revealed={s.outcome?.observations ?? null}
              snapshot={s.snapshot}
              xLabel={ds?.x.label ?? 'x'}
              yLabel="Reported period"
              xUnit={units.x}
              yUnit={units.y}
            />
          ) : (
            <div className="plot placeholder">{s.error ? 'No data loaded.' : 'Loading recorded measurements…'}</div>
          )}
          {an && <ModelCards models={an.models} yUnit={units.y} />}
        </div>

        <aside className="right">
          {ctx && (
            <p className="observed-note">
              Observed: <strong>{lengthsMeasured} lengths</strong>, <strong>{ctx.observed.length} period observations</strong>{' '}
              (reported averages over several swings). {ctx.candidate_x.length > 0 && (
                <>
                  The other {ctx.candidate_x.length} recorded lengths ({ctx.candidate_x.join(', ')} {units.x}) stay hidden for
                  replay; the recommendation sees only the observed periods and which lengths exist.
                </>
              )}
            </p>
          )}

          {primaryLabel && (
            <button className="primary" onClick={onPrimary} disabled={busy || !ctx}>
              {primaryLabel}
            </button>
          )}
          {step === 'update' && (
            <p className="dim">Check the frozen predictions against the recorded values, then update. The next recommendation waits for this step.</p>
          )}

          {an && an.status !== 'ok' && an.status !== 'no_candidates' && (
            <p className="callout warn">{an.explanation}</p>
          )}
          {an?.all_models_inadequate && (
            <p className="callout warn">
              Poor fit (heuristic): every model misses the measured means by more than the measured variability. No candidate
              fits adequately.
            </p>
          )}
          {an?.noise?.source === 'unknown' && <p className="callout">{an.noise.note}</p>}
          {s.complete && (
            <p className="callout">
              Replay complete: all recorded lengths are measured. Download the record or reset the demo to start again.
            </p>
          )}

          {s.outcome ? (
            <ComparisonPanel outcome={s.outcome} units={units} />
          ) : s.snapshot && s.recommendation ? (
            <RecommendationPanel rec={s.recommendation} snapshot={s.snapshot} measured={measured} units={units} />
          ) : lastCycle?.after ? (
            <ChangePanel cycle={lastCycle} units={units} />
          ) : (
            an &&
            an.status === 'ok' && (
              <section className="panel">
                <h2>Models compared</h2>
                <p>
                  Three two-parameter models fitted to {an.data?.n_settings} lengths ({an.data?.n_observations} observations).
                  Leading by validation error:{' '}
                  {(() => {
                    const best = [...an.models].sort((a, b) => (b.support ?? -1) - (a.support ?? -1))[0]
                    return `${best.name}, ${withUnit(best.grouped_cv_rmse, units.y)} RMSE`
                  })()}
                  . Recommend a next length to freeze each model's prediction before anything is revealed.
                </p>
                <p className="dim">
                  Measured range: {sig(measured[0])}–{sig(measured[1])} {units.x}. Repeats vary by about{' '}
                  {withUnit(an.noise?.sd_individual, units.y)} (SD of individual observations); a mean of 3 is uncertain by
                  about {withUnit(an.noise?.representative_mean_sd, units.y)}.
                </p>
              </section>
            )
          )}
        </aside>
      </main>

      <History cycles={s.cycles} units={units} />
      {an && ds && <Assumptions analysis={an} dataset={ds} />}
      <BenchmarkSection />
    </div>
  )
}

export default App
