import { useEffect, useState } from 'react'
import {
  benchmarkFileUrl,
  fetchBenchmark,
  type Analysis,
  type BenchmarkResponse,
  type ModelId,
  type ModelResult,
  type OutcomeResponse,
  type Provenance,
  type RecommendResponse,
  type Snapshot,
} from './api'
import type { Cycle, Step } from './state'
import { MODEL_STYLE, shortId, sig, stop, support, withUnit } from './format'

const DASH = { solid: '', dash: '6 4', dashdot: '7 3 2 3' }

export function Swatch({ id }: { id: ModelId }) {
  const st = MODEL_STYLE[id]
  return (
    <svg className="swatch" width="26" height="10" aria-hidden="true">
      <line x1="1" y1="5" x2="25" y2="5" stroke={st.color} strokeWidth="3" strokeDasharray={DASH[st.dash]} />
    </svg>
  )
}

const stepsFor = (demo: boolean): { key: Exclude<Step, 'done'>; label: string; hint: string }[] => [
  { key: 'compare', label: 'Compare', hint: 'Fit three models' },
  { key: 'recommend', label: 'Recommend', hint: 'Freeze predictions' },
  demo ? { key: 'reveal', label: 'Reveal', hint: 'See the recorded value' } : { key: 'reveal', label: 'Measure', hint: 'Enter the result' },
  { key: 'update', label: 'Update', hint: 'Refit explicitly' },
]

export function StepBar({ step, cycle, demo }: { step: Step; cycle: number; demo: boolean }) {
  const STEPS = stepsFor(demo)
  const order = STEPS.map((s) => s.key)
  const at = step === 'done' ? order.length : order.indexOf(step)
  return (
    <ol className="steps" aria-label="Workflow">
      {STEPS.map((s, i) => (
        <li key={s.key} className={i < at ? 'done' : i === at ? 'current' : ''} aria-current={i === at ? 'step' : undefined}>
          <span className="num">{i + 1}</span>
          <span>
            <strong>{s.label}</strong> <small>{s.hint}</small>
          </span>
        </li>
      ))}
      <li className="cycle">Cycle {cycle}</li>
    </ol>
  )
}

export function ModelCards({ models, yUnit }: { models: ModelResult[]; yUnit: string }) {
  return (
    <div className="cards">
      {models.map((m) => (
        <article key={m.id} className={`card ${m.strongly_down_weighted ? 'muted' : ''}`}>
          <header>
            <Swatch id={m.id} /> <strong>{m.name}</strong>
          </header>
          <code className="formula">{m.formula}</code>
          {m.note && <div className="note">{m.note}</div>}
          {m.fitted ? (
            <dl>
              <dt>Fitted</dt>
              <dd>
                a = {sig(m.a)}, b = {sig(m.b)}
              </dd>
              <dt title="Each measured length is left out in turn (all its repeats together) and predicted from the rest.">
                Validation error
              </dt>
              <dd>{m.grouped_cv_rmse === null ? 'n/a' : `${withUnit(m.grouped_cv_rmse, yUnit)} RMSE`}</dd>
              <dt title="Heuristic weight from validation error; not a probability.">Relative support</dt>
              <dd>
                <span className="bar" aria-hidden="true">
                  <span style={{ width: `${Math.max(2, 100 * (m.support ?? 0))}%`, background: MODEL_STYLE[m.id].color }} />
                </span>{' '}
                {support(m.support)}
              </dd>
            </dl>
          ) : (
            <p className="warn">Not fitted: {m.failure}</p>
          )}
          {m.strongly_down_weighted && <div className="tag">strongly down-weighted</div>}
          {m.adequacy.conflicts_with_noise && <div className="tag warn">misses measured variability (heuristic)</div>}
        </article>
      ))}
    </div>
  )
}

function inRange(x: number, lo: number, hi: number) {
  return x >= lo && x <= hi
}

export function RecommendationPanel({
  rec,
  snapshot,
  measured,
  units,
  demo,
}: {
  rec: RecommendResponse
  snapshot: Snapshot
  measured: [number, number]
  units: { x: string; y: string }
  demo: boolean
}) {
  const setting = demo ? 'length' : 'setting'
  const r = rec.analysis.recommendation!
  const top = [...r.predictions].sort((a, b) => (b.share_of_spread ?? -1) - (a.share_of_spread ?? -1))[0]
  const lead = [...r.predictions].sort((a, b) => (b.support ?? -1) - (a.support ?? -1))[0]
  const sep = r.separation
  const preds = snapshot.record.models.flatMap((m) => (m.predicted_y === null ? [] : [m.predicted_y]))
  const predRange: [number, number] | null = preds.length > 1 ? [Math.min(...preds), Math.max(...preds)] : null
  return (
    <section className="panel rec" aria-live="polite">
      <h2>
        Next measurement: {snapshot.record.x} {units.x}
      </h2>
      <div className={`badge ${r.kind}`}>
        {r.kind === 'disagreement' ? 'Largest model disagreement' : 'Space-filling validation point'}
      </div>
      {!inRange(snapshot.record.x, measured[0], measured[1]) && (
        <p className="note">
          Outside the measured range ({sig(measured[0])}–{sig(measured[1])} {units.x}): every model is extrapolating here.
        </p>
      )}
      <table className="preds">
        <caption>Frozen predictions (fixed before the {demo ? 'reveal' : 'measurement'})</caption>
        <tbody>
          {snapshot.record.models.map((m) => (
            <tr key={m.id}>
              <td>
                <Swatch id={m.id} /> {m.name}
              </td>
              <td className="num">{m.predicted_y === null ? 'n/a' : withUnit(m.predicted_y, units.y)}</td>
              <td className="dim">support {support(m.support)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p>
        {r.kind === 'disagreement'
          ? `Chosen where the support-weighted predictions disagree most among ${r.n_unmeasured} remaining ${setting}s.`
          : r.fallback_reason === 'dominant_model'
            ? `${lead.name} holds at least 0.99 of the relative support, so disagreement is not used. This point checks the leading model where data are sparse; it is not chosen to tell the models apart.`
            : 'The models agree at every remaining length, so this is a space-filling check, not a test between models.'}
      </p>
      <p>
        {sep.label === 'unassessed' ? (
          <>Measurement noise is unknown, so the model spread cannot be compared with measurement uncertainty.</>
        ) : (
          <>
            Support-weighted model spread here: {withUnit(r.spread, units.y)}, {sig(sep.ratio)}× the uncertainty of a
            setting mean ({withUnit(sep.setting_mean_sd, units.y)}).{' '}
            {r.spread > 0 && (top.share_of_spread ?? 0) > 0
              ? `${Math.round(100 * (top.share_of_spread ?? 0))}% of it comes from ${top.name} (support ${support(top.support)}).`
              : `It is ${r.spread > 0 ? 'small' : '0'} because ${lead.name} holds essentially all the relative support.`}{' '}
            {predRange && (
              <>
                The unweighted predictions still range from {withUnit(predRange[0], units.y)} to{' '}
                {stop(withUnit(predRange[1], units.y))}
              </>
            )}
          </>
        )}
      </p>
      {sep.label === 'inconclusive' && (
        <p className="callout warn">
          Low separation: weighted by current support, the predictions differ by less than 2× the uncertainty of a setting
          mean, so this result is unlikely to change the support ranking much.
        </p>
      )}
      <details>
        <summary>Why this setting?</summary>
        <p>{r.method}</p>
        <dl className="kv">
          <dt>Acquisition score (weighted variance)</dt>
          <dd>
            {sig(r.score)} {units.y}²
          </dd>
          {r.distance_to_nearest_measured !== null && (
            <>
              <dt>Distance to nearest measured {setting}</dt>
              <dd>{withUnit(r.distance_to_nearest_measured, units.x)}</dd>
            </>
          )}
          <dt>Snapshot</dt>
          <dd>
            {shortId(snapshot.snapshot_id)} · frozen {snapshot.record.created_at}
          </dd>
        </dl>
        <table className="small">
          <thead>
            <tr>
              <th>Remaining {setting}</th>
              <th>Model spread</th>
            </tr>
          </thead>
          <tbody>
            {rec.analysis.candidate_scores.map((c) => (
              <tr key={c.x} className={c.x === snapshot.record.x ? 'sel' : ''}>
                <td>
                  {c.x} {units.x}
                </td>
                <td>{withUnit(c.spread, units.y)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="dim">{rec.analysis.explanation}</p>
      </details>
    </section>
  )
}

export function ComparisonPanel({ outcome, units, demo }: { outcome: OutcomeResponse; units: { x: string; y: string }; demo: boolean }) {
  const c = outcome.comparison
  const closest = c.models.find((m) => m.id === c.closest_model)
  return (
    <section className="panel cmp" aria-live="polite">
      <h2>
        {demo ? 'Recorded' : 'Entered'} at {outcome.x} {units.x}
      </h2>
      <p>
        {outcome.observations.map((o) => sig(o.y, 4)).join(', ')} {units.y}:{' '}
        {demo
          ? `${c.n_observations} reported periods, each an average over several swings.`
          : `${c.n_observations} value${c.n_observations === 1 ? '' : 's'} you entered.`}{' '}
        <strong>{stop(`Mean ${withUnit(c.observed_mean, units.y)}`)}</strong>
      </p>
      <table className="preds">
        <caption>{demo ? 'Recorded' : 'Entered'} mean versus the frozen predictions</caption>
        <thead>
          <tr>
            <th>Model</th>
            <th className="num">Frozen prediction</th>
            <th className="num">Error</th>
            <th className="num" title="Error divided by the frozen noise estimate for a mean of these observations (heuristic scale).">
              In SDs of a mean
            </th>
          </tr>
        </thead>
        <tbody>
          {c.models.map((m) => (
            <tr key={m.id} className={m.id === c.closest_model ? 'sel' : ''}>
              <td>
                <Swatch id={m.id} /> {m.name}
              </td>
              <td className="num">{withUnit(m.predicted_y, units.y)}</td>
              <td className="num">{withUnit(m.error, units.y)}</td>
              <td className="num">{sig(m.error_in_mean_sds)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {closest && closest.error_in_mean_sds !== null && Math.abs(closest.error_in_mean_sds) > 3 && (
        <p className="callout warn">
          Even the closest frozen prediction ({closest.name}) missed by {sig(Math.abs(closest.error_in_mean_sds))} SDs of a
          mean. Either the model is inadequate at this length or the frozen noise estimate is too small.
        </p>
      )}
      <p className="dim">
        {c.note} The models have not been refitted yet.
      </p>
    </section>
  )
}

export function ChangePanel({ cycle, units }: { cycle: Cycle; units: { x: string; y: string } }) {
  if (!cycle.after) return null
  const after = cycle.after
  return (
    <section className="panel change">
      <h2>
        What changed after adding {cycle.outcome.x} {units.x}
      </h2>
      <table className="preds">
        <thead>
          <tr>
            <th>Model</th>
            <th className="num">Relative support</th>
            <th className="num">Validation error (RMSE)</th>
          </tr>
        </thead>
        <tbody>
          {cycle.before.models.map((b) => {
            const a = after.models.find((m) => m.id === b.id)!
            return (
              <tr key={b.id}>
                <td>
                  <Swatch id={b.id} /> {b.name}
                </td>
                <td className="num">
                  {support(b.support)} → {support(a.support)}
                </td>
                <td className="num">
                  {withUnit(b.grouped_cv_rmse, units.y)} → {withUnit(a.grouped_cv_rmse, units.y)}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      <p className="dim">
        SD of individual observations (from repeats): {withUnit(cycle.before.noise?.sd_individual, units.y)} →{' '}
        {withUnit(after.noise?.sd_individual, units.y)}. Errors and spread can rise after new data; these are the values as
        computed.
      </p>
    </section>
  )
}

export function History({ cycles, units }: { cycles: Cycle[]; units: { x: string; y: string } }) {
  if (cycles.length === 0) return null
  return (
    <section className="history">
      <h2>Prediction history</h2>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Length</th>
            <th>Choice</th>
            {cycles[0].snapshot.record.models.map((m) => (
              <th key={m.id} className="num">
                {m.name} predicted
              </th>
            ))}
            <th className="num">Observed mean</th>
            <th>Closest</th>
            <th>Snapshot</th>
          </tr>
        </thead>
        <tbody>
          {cycles.map((c, i) => (
            <tr key={c.snapshot.snapshot_id}>
              <td>{i + 1}</td>
              <td>
                {c.snapshot.record.x} {units.x}
              </td>
              <td>{c.snapshot.selection.kind === 'disagreement' ? 'disagreement' : 'space-filling'}</td>
              {c.snapshot.record.models.map((m) => (
                <td key={m.id} className="num">
                  {withUnit(m.predicted_y, units.y)}
                </td>
              ))}
              <td className="num">{withUnit(c.outcome.comparison.observed_mean, units.y)}</td>
              <td>{c.snapshot.record.models.find((m) => m.id === c.outcome.comparison.closest_model)?.name ?? '—'}</td>
              <td className="dim">
                {shortId(c.snapshot.snapshot_id)} {c.after ? '' : '(not yet updated)'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

export function Assumptions({ analysis, dataset }: { analysis: Analysis; dataset: Provenance | null }) {
  const n = analysis.noise
  const u = analysis.units
  return (
    <details className="assumptions">
      <summary>Assumptions and data notes</summary>
      <div className="cols">
        <div>
          <h3>Variation and uncertainty</h3>
          {n && n.source !== 'unknown' ? (
            <p>
              Variation among repeats: SD of individual observations {withUnit(n.sd_individual, u.y)} (pooled from{' '}
              {n.settings_with_repeats} lengths, {n.df} degrees of freedom). Uncertainty of a setting mean: SD/√n, typically{' '}
              {withUnit(n.representative_mean_sd, u.y)}. Assumes independent observations with one constant variance.
            </p>
          ) : (
            <p>Noise unknown: no repeats and no stated SD.</p>
          )}
          <table className="small">
            <thead>
              <tr>
                <th>Length</th>
                <th>n</th>
                <th>Mean</th>
                <th>SD of repeats</th>
                <th>SD of mean</th>
              </tr>
            </thead>
            <tbody>
              {analysis.data?.settings.map((s) => (
                <tr key={s.x}>
                  <td>
                    {s.x} {u.x}
                  </td>
                  <td>{s.n}</td>
                  <td>{withUnit(s.mean, u.y)}</td>
                  <td>{withUnit(s.repeat_sd, u.y)}</td>
                  <td>{withUnit(s.mean_sd, u.y)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div>
          <h3>Method</h3>
          <ul>
            <li>Each model is fitted to the mean at each length, with every length weighted equally. Length is treated as exact.</li>
            <li>
              Validation error leaves one whole length out (all its repeats) and predicts it from the others.
            </li>
            <li>
              Relative support = exp(−(L − min L)/(2s²)), from validation error L. It is a heuristic weight, not the
              probability that a model is true.
            </li>
            <li>
              Model spread = support-weighted SD of the three predictions at a length. It measures disagreement between
              models, not measurement uncertainty, and is not a confidence interval. No shaded band is drawn.
            </li>
            <li>
              One model with ≥ 0.99 support triggers a space-filling choice (farthest from measured lengths). Separation below
              2× the setting-mean SD is labelled low. A model is flagged when its fitted means miss by more than 3 setting-mean
              SDs on average (heuristic).
            </li>
          </ul>
          <h3>Data</h3>
          <ul>
            {dataset ? (
              dataset.limitations.map((l) => <li key={l}>{l}</li>)
            ) : (
              <>
                <li>Uploaded by the user. NextLab makes no claim about how the data were collected.</li>
                <li>Units are the labels you entered; nothing is converted.</li>
                <li>
                  If no input value is repeated and no noise SD is stated, measurement noise is unknown and separation and fit
                  adequacy are not assessed.
                </li>
              </>
            )}
          </ul>
        </div>
      </div>
    </details>
  )
}

type Loadable<T> = { kind: 'loading' } | { kind: 'ok'; value: T } | { kind: 'error'; message: string }

const BASELINE_NAMES: Record<string, string> = {
  random: 'Random choice',
  preplanned_even: 'Preplanned evenly spaced',
  endpoint_maximin: 'Endpoints first, then farthest gap',
}

export function BenchmarkSection() {
  const [b, setB] = useState<Loadable<BenchmarkResponse>>({ kind: 'loading' })
  useEffect(() => {
    fetchBenchmark()
      .then((value) => setB({ kind: 'ok', value }))
      .catch((e: unknown) => setB({ kind: 'error', message: e instanceof Error ? e.message : String(e) }))
  }, [])
  return (
    <section className="benchmark">
      <h2>Benchmark evidence (simulation, not pendulum data)</h2>
      {b.kind === 'loading' && <p>Loading saved benchmark results…</p>}
      {b.kind === 'error' && <p className="warn">Saved benchmark results are unavailable: {b.message}</p>}
      {b.kind === 'ok' && (
        <>
          <p>
            Simulated experiments: 4 generating relationships (one outside all three models), 2 assumed noise levels, 2
            starting layouts, 100 seeds each. Every strategy measured {b.value.primary_endpoint.n_settings} settings (
            {b.value.primary_endpoint.n_observations} observations). Outcome: prediction error against the noiseless
            relationship at 200 unseen inputs. Counts are of 16 conditions, by a 95% bootstrap interval of the paired
            difference.
          </p>
          <table>
            <thead>
              <tr>
                <th>NextLab versus</th>
                <th className="num">Better</th>
                <th className="num">No clear difference</th>
                <th className="num">Worse</th>
              </tr>
            </thead>
            <tbody>
              {b.value.verdicts.map((v) => (
                <tr key={v.baseline}>
                  <td>{BASELINE_NAMES[v.baseline] ?? v.baseline}</td>
                  <td className="num">{v.better}</td>
                  <td className="num">{v.no_clear}</td>
                  <td className="num">{v.worse}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p>
            Reading: NextLab beat random choice in most conditions but showed no clear advantage over the stronger
            endpoints-then-gaps strategy; at smaller budgets it was sometimes worse. Its value here is the transparent
            freeze-reveal-update record, not a better experimental design.
          </p>
          <p className="dim">
            Download:{' '}
            {(['paired.csv', 'summary.csv', 'runs.csv', 'meta.json'] as const).map((f, i) => (
              <span key={f}>
                {i > 0 && ' · '}
                <a href={benchmarkFileUrl(f)}>{f}</a>
              </span>
            ))}
            . Reproduce: <code>{b.value.reproduce.command}</code> (protocol in {b.value.reproduce.protocol}; code commit{' '}
            {String(b.value.meta.git_commit ?? '').slice(0, 7)}).
          </p>
        </>
      )}
    </section>
  )
}
