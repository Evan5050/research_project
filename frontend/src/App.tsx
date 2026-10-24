import { useCallback, useEffect, useLayoutEffect, useReducer, useRef } from 'react'
import {
  ApiError,
  BACKEND_UNAVAILABLE,
  analyze,
  exportRecord,
  feasibleSettings,
  observe,
  recommend,
  revealDemo,
  startDemo,
  type FieldError,
  type UploadResponse,
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
import { MeasurementEntry, SettingsEditor, UploadForm } from './Upload'
import type { feasibleRequest } from './inputs'
import { sig, withUnit } from './format'

function toUiError(e: unknown): UiError {
  if (e instanceof ApiError) {
    return { message: e.message, fields: e.fields, unavailable: e.status === BACKEND_UNAVAILABLE }
  }
  return { message: e instanceof Error ? e.message : String(e), fields: [], unavailable: false }
}

function download(content: string, type: string, filename: string) {
  const url = URL.createObjectURL(new Blob([content], { type }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
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

  const newEpoch = (mode: 'demo' | 'upload', loading: boolean) => {
    epochRef.current += 1
    inFlight.current = null
    dispatch({ type: 'reset', epoch: epochRef.current, mode, loading })
    return epochRef.current
  }

  const startDemoRun = useCallback(async () => {
    const epoch = newEpoch('demo', true)
    try {
      const st = await startDemo()
      dispatch({ type: 'started', epoch, context: st.context, revision: st.revision, dataset: st.dataset })
      dispatch({ type: 'request', epoch, pending: 'analyze' })
      const an = await analyze(st.context)
      dispatch({ type: 'analyzed', epoch, resp: an })
    } catch (e) {
      dispatch({ type: 'failed', epoch, error: toUiError(e) })
    }
  }, [])

  const chooseUpload = () => newEpoch('upload', false)

  const onUploaded = async (r: UploadResponse) => {
    const epoch = newEpoch('upload', false)
    dispatch({ type: 'started', epoch, context: r.context, revision: r.revision, dataset: null })
    dispatch({ type: 'request', epoch, pending: 'analyze' })
    try {
      dispatch({ type: 'analyzed', epoch, resp: await analyze(r.context) })
    } catch (e) {
      dispatch({ type: 'failed', epoch, error: toUiError(e) })
    }
  }

  useEffect(() => {
    void startDemoRun()
  }, [startDemoRun])

  const step = nextStep(s)
  const busy = s.pending !== null
  const demo = s.mode === 'demo'

  const onRecommend = () => {
    const ctx = stateRef.current.context
    if (ctx) void run('recommend', () => recommend(ctx), (resp, epoch) => ({ type: 'recommended', epoch, resp }))
  }
  const onReveal = () => {
    const { context, snapshot } = stateRef.current
    if (context && snapshot)
      void run('reveal', () => revealDemo(context, snapshot), (resp, epoch) => ({ type: 'revealed', epoch, resp }))
  }
  const onMeasured = (ys: number[]) => {
    const { context, snapshot } = stateRef.current
    if (context && snapshot)
      void run('reveal', () => observe(context, snapshot, ys), (resp, epoch) => ({ type: 'revealed', epoch, resp }))
  }
  const onUpdate = () => {
    const o = stateRef.current.outcome
    if (o) void run('update', () => analyze(o.updated_context), (resp, epoch) => ({ type: 'updated', epoch, resp }))
  }
  const onCompareRetry = () => {
    const ctx = stateRef.current.context
    if (ctx) void run('analyze', () => analyze(ctx), (resp, epoch) => ({ type: 'analyzed', epoch, resp }))
    else if (stateRef.current.mode === 'demo') void startDemoRun()
  }
  const onApplySettings = async (req: ReturnType<typeof feasibleRequest>['req'], sd: number | null): Promise<FieldError[]> => {
    const { context, outcome } = stateRef.current
    if (!context || outcome) return [{ field: 'settings', message: 'Update the models first.' }]
    try {
      const { candidate_x } = await feasibleSettings(req)
      const next = { ...context, candidate_x, response_sd: sd }
      const epoch = epochRef.current
      const resp = await analyze(next)
      dispatch({ type: 'contextChanged', epoch, context: next, revision: resp.revision })
      dispatch({ type: 'analyzed', epoch, resp })
      return []
    } catch (e) {
      return e instanceof ApiError && e.fields.length ? e.fields : [{ field: 'settings', message: toUiError(e).message }]
    }
  }
  const onExport = async () => {
    const { context, cycles, outcome } = stateRef.current
    if (!context) return
    try {
      // Include entered/revealed values that are waiting for Update, marked as not yet refitted.
      const ctx = outcome ? outcome.updated_context : context
      const ex = await exportRecord(ctx, cycles.map((c) => ({ snapshot: c.snapshot, updated: c.after !== null })))
      const id = ex.record_id.slice(0, 8)
      download(JSON.stringify(ex, null, 2), 'application/json', `nextlab-record-${id}.json`)
      download(ex.observations_csv, 'text/csv', `nextlab-observations-${id}.csv`)
    } catch (e) {
      dispatch({ type: 'failed', epoch: epochRef.current, error: toUiError(e) })
    }
  }

  const ds = s.dataset
  const ctx = s.context
  const an = s.analysis?.analysis ?? null
  const units = { x: ctx?.x_unit ?? '', y: ctx?.y_unit ?? '' }
  const labels = { x: ctx?.x_label || 'x', y: ctx?.y_label || 'y' }
  const xs = ctx?.observed.map((o) => o.x) ?? []
  const measured: [number, number] = [Math.min(...xs), Math.max(...xs)]
  const settingsMeasured = new Set(xs).size
  const lastCycle = s.cycles.length ? s.cycles[s.cycles.length - 1] : null
  const cands = ctx?.candidate_x ?? []
  const outside = cands.filter((x) => x < measured[0] || x > measured[1]).length

  const primaryLabel =
    step === 'done' || (step === 'reveal' && !demo) || (step === 'recommend' && an !== null && an.status !== 'ok' && an.status !== 'no_candidates')
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
    else if (now === 'reveal' && stateRef.current.mode === 'demo') onReveal()
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
          <div className="modes" role="group" aria-label="Data source">
            <button className={demo ? 'on' : ''} aria-pressed={demo} onClick={() => void startDemoRun()}>
              Built-in demonstration
            </button>
            <button className={!demo ? 'on' : ''} aria-pressed={!demo} onClick={chooseUpload}>
              Use my data
            </button>
          </div>
          {demo ? (
            <span>
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
            </span>
          ) : (
            <span>
              <strong>User-uploaded data</strong>
              {ctx && <span className="dim"> · {ctx.source_name} · kept in this browser session and the local server only</span>}
            </span>
          )}
        </div>
        <div className="top-actions">
          <button onClick={() => void onExport()} disabled={!ctx || busy}>
            Download record
          </button>
          <button onClick={() => (demo ? void startDemoRun() : chooseUpload())}>{demo ? 'Reset demo' : 'Start over'}</button>
        </div>
      </header>

      <StepBar step={step} cycle={s.cycles.filter((c) => c.after).length + (step === 'done' ? 0 : 1)} demo={demo} />

      {s.error && (
        <div className={`banner ${s.error.unavailable ? 'unavailable' : 'invalid'}`} role="alert">
          {s.error.unavailable ? (
            <>
              <strong>Backend unavailable.</strong> The Julia server did not respond. Start it with{' '}
              <code>julia --project=backend --threads=auto,1 backend/scripts/serve.jl</code>, then{' '}
              <button onClick={onCompareRetry}>Retry</button>
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

      {!demo && !ctx ? (
        <UploadForm onLoaded={(r) => void onUploaded(r)} disabled={busy} />
      ) : (
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
                xLabel={labels.x}
                yLabel={labels.y}
                xUnit={units.x}
                yUnit={units.y}
                demo={demo}
              />
            ) : (
              <div className="plot placeholder">{s.error ? 'No data loaded.' : 'Loading…'}</div>
            )}
            {an && <ModelCards models={an.models} yUnit={units.y} />}
          </div>

          <aside className="right">
            {ctx &&
              (demo ? (
                <p className="observed-note">
                  Observed: <strong>{settingsMeasured} lengths</strong>, <strong>{ctx.observed.length} period observations</strong>{' '}
                  (reported averages over several swings).{' '}
                  {ctx.candidate_x.length > 0 && (
                    <>
                      The other {ctx.candidate_x.length} recorded lengths ({ctx.candidate_x.join(', ')} {units.x}) stay hidden
                      for replay; the recommendation sees only the observed periods and which lengths exist.
                    </>
                  )}
                </p>
              ) : (
                <p className="observed-note">
                  Observed: <strong>{settingsMeasured} distinct {labels.x} values</strong>,{' '}
                  <strong>{ctx.observed.length} rows</strong>. Every uploaded row is already observed; there is no hidden data.
                  Feasible next settings: {cands.length} from {sig(Math.min(...cands))} to {sig(Math.max(...cands))} {units.x}
                  {outside > 0 && <>, {outside} of them outside the observed range (extrapolation)</>}.
                </p>
              ))}

            {primaryLabel && (
              <button className="primary" onClick={onPrimary} disabled={busy || !ctx}>
                {primaryLabel}
              </button>
            )}
            {!demo && step === 'reveal' && ctx && s.snapshot && (
              <MeasurementEntry x={s.snapshot.record.x} context={ctx} disabled={busy} onSubmit={onMeasured} />
            )}
            {step === 'update' && (
              <p className="dim">
                Check the frozen predictions against the {demo ? 'recorded' : 'entered'} values, then update. The next
                recommendation waits for this step.
              </p>
            )}

            {an && an.status !== 'ok' && an.status !== 'no_candidates' && <p className="callout warn">{an.explanation}</p>}
            {an?.all_models_inadequate && (
              <p className="callout warn">
                Poor fit (heuristic): every model misses the measured means by more than the measured variability. No
                candidate fits adequately.
              </p>
            )}
            {an?.noise?.source === 'unknown' && <p className="callout">{an.noise.note}</p>}
            {s.complete && (
              <p className="callout">
                {demo
                  ? 'Replay complete: all recorded lengths are measured. Download the record or reset the demo to start again.'
                  : 'Every feasible setting has been measured. Add feasible settings to continue, or download the record.'}
              </p>
            )}

            {s.outcome ? (
              <ComparisonPanel outcome={s.outcome} units={units} demo={demo} />
            ) : s.snapshot && s.recommendation ? (
              <RecommendationPanel rec={s.recommendation} snapshot={s.snapshot} measured={measured} units={units} demo={demo} />
            ) : lastCycle?.after ? (
              <ChangePanel cycle={lastCycle} units={units} />
            ) : (
              an &&
              an.status === 'ok' && (
                <section className="panel">
                  <h2>Models compared</h2>
                  <p>
                    Three two-parameter models fitted to {an.data?.n_settings} distinct {demo ? 'lengths' : 'settings'} (
                    {an.data?.n_observations} observations). Leading by validation error:{' '}
                    {(() => {
                      const best = [...an.models].sort((a, b) => (b.support ?? -1) - (a.support ?? -1))[0]
                      return `${best.name}, ${withUnit(best.grouped_cv_rmse, units.y)} RMSE`
                    })()}
                    . Recommend a next setting to freeze each model's prediction before anything is {demo ? 'revealed' : 'measured'}.
                  </p>
                  <p className="dim">
                    Observed range: {sig(measured[0])}–{sig(measured[1])} {units.x}.{' '}
                    {an.noise?.source === 'repeats' &&
                      `Repeats vary by about ${withUnit(an.noise.sd_individual, units.y)} (SD of individual observations); the mean of a setting is uncertain by about ${withUnit(an.noise.representative_mean_sd, units.y)}.`}
                    {an.noise?.source === 'user' &&
                      `Using the stated noise SD of ${withUnit(an.noise.sd_individual, units.y)} per observation (no repeats in the data).`}
                  </p>
                </section>
              )
            )}
            {!demo && ctx && <SettingsEditor key={s.revision ?? ''} context={ctx} locked={s.outcome !== null} busy={busy} onApply={onApplySettings} />}
          </aside>
        </main>
      )}

      <History cycles={s.cycles} units={units} />
      {an && <Assumptions analysis={an} dataset={ds} />}
      <BenchmarkSection />
    </div>
  )
}

export default App
