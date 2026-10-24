import { useState } from 'react'
import {
  ApiError,
  SAMPLE_CSV_URL,
  previewUpload,
  upload,
  type ExperimentContext,
  type FieldError,
  type PreviewResponse,
  type UploadResponse,
} from './api'
import { sig } from './format'
import { feasibleRequest, parseNumbers, type FeasibleInput } from './inputs'

const MAX_BYTES = 2 * 1024 * 1024

function FieldErrors({ errors }: { errors: FieldError[] }) {
  if (errors.length === 0) return null
  return (
    <ul className="field-errors" role="alert">
      {errors.map((e, i) => (
        <li key={i}>
          <code>{e.field}</code>: {e.message}
        </li>
      ))}
    </ul>
  )
}

const errorsOf = (e: unknown): FieldError[] =>
  e instanceof ApiError
    ? e.fields.length
      ? e.fields
      : [{ field: 'request', message: e.message }]
    : [{ field: 'request', message: String(e) }]

export function FeasibleFields({ v, set, xUnit }: { v: FeasibleInput; set: (v: FeasibleInput) => void; xUnit: string }) {
  const u = xUnit ? ` (${xUnit})` : ''
  return (
    <fieldset className="feasible">
      <legend>Feasible next settings</legend>
      <label>
        From{u} <input aria-label="Feasible range lower bound" value={v.lo} onChange={(e) => set({ ...v, lo: e.target.value })} />
      </label>
      <label>
        to{u} <input aria-label="Feasible range upper bound" value={v.hi} onChange={(e) => set({ ...v, hi: e.target.value })} />
      </label>
      <label>
        step <input aria-label="Feasible range step" value={v.step} onChange={(e) => set({ ...v, step: e.target.value })} />
      </label>
      <label className="wide">
        and/or exact settings{u}{' '}
        <input
          aria-label="Explicit feasible settings"
          placeholder="e.g. 2.5, 3, 12"
          value={v.list}
          onChange={(e) => set({ ...v, list: e.target.value })}
        />
      </label>
      <p className="dim">
        At most 201 settings after removing duplicates. Settings outside the observed range are extrapolation and are marked
        as such.
      </p>
    </fieldset>
  )
}

export function UploadForm({ onLoaded, disabled }: { onLoaded: (r: UploadResponse) => void; disabled: boolean }) {
  const [file, setFile] = useState<{ name: string; text: string } | null>(null)
  const [preview, setPreview] = useState<PreviewResponse | null>(null)
  const [xCol, setXCol] = useState(0)
  const [yCol, setYCol] = useState(1)
  const [labels, setLabels] = useState({ xl: '', xu: '', yl: '', yu: '' })
  const [feas, setFeas] = useState<FeasibleInput>({ lo: '', hi: '', step: '', list: '' })
  const [sd, setSd] = useState('')
  const [errors, setErrors] = useState<FieldError[]>([])
  const [busy, setBusy] = useState(false)

  const pickDefaults = (p: PreviewResponse, xi: number, yi: number) => {
    setXCol(xi)
    setYCol(yi)
    setLabels((l) => ({ ...l, xl: p.columns[xi] ?? '', yl: p.columns[yi] ?? '' }))
    const info = p.column_info[xi]
    if (info?.min !== null && info?.max !== null && info && info.max! > info.min!) {
      setFeas((f) => ({ ...f, lo: String(info.min), hi: String(info.max), step: String(sig((info.max! - info.min!) / 10)) }))
    }
  }

  const onFile = async (f: File | undefined) => {
    setErrors([])
    setPreview(null)
    if (!f) return
    if (f.size > MAX_BYTES) {
      setErrors([{ field: 'csv', message: 'The file is larger than the 2 MB prototype limit.' }])
      return
    }
    const text = await f.text()
    setFile({ name: f.name, text })
    setBusy(true)
    try {
      const p = await previewUpload(text)
      setPreview(p)
      const numeric = p.column_info.map((c, i) => (c.numeric_rows > 0 ? i : -1)).filter((i) => i >= 0)
      pickDefaults(p, numeric[0] ?? 0, numeric[1] ?? 1)
    } catch (e) {
      setErrors(errorsOf(e))
    } finally {
      setBusy(false)
    }
  }

  const onLoad = async () => {
    if (!file || !preview) return
    const fr = feasibleRequest(feas)
    const local = [...fr.errors]
    let response_sd: number | null = null
    if (sd.trim()) {
      const v = Number(sd)
      if (!Number.isFinite(v)) local.push({ field: 'response_sd', message: 'Enter a number or leave empty.' })
      else response_sd = v
    }
    if (local.length) return setErrors(local)
    setBusy(true)
    setErrors([])
    try {
      const { lo, hi, step, candidate_x } = fr.req
      const r = await upload({
        csv: file.text,
        x_column: preview.columns[xCol],
        y_column: preview.columns[yCol],
        bounds: lo !== undefined && hi !== undefined && step !== undefined ? { lo, hi, step } : undefined,
        candidate_x,
        response_sd,
        x_label: labels.xl,
        x_unit: labels.xu,
        y_label: labels.yl,
        y_unit: labels.yu,
        source_name: file.name,
      })
      onLoaded(r)
    } catch (e) {
      setErrors(errorsOf(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="panel upload">
      <h2>Use my data</h2>
      <p>
        A CSV with a header row and at least two numeric columns: one input x (positive) and one response y. Repeated x
        values are kept as repeats. Every uploaded row counts as already observed; nothing is hidden.{' '}
        <a href={SAMPLE_CSV_URL} download>
          Download a sample CSV
        </a>{' '}
        (the built-in pendulum data as two columns: fastR2 Pendulum, credited to Calvin College physics students under Prof.
        Steve Plath).
      </p>
      <label className="file">
        CSV file{' '}
        <input type="file" accept=".csv,text/csv" aria-label="CSV file" onChange={(e) => void onFile(e.target.files?.[0])} disabled={disabled || busy} />
      </label>
      {preview && file && (
        <>
          <p className="dim">
            {file.name}: {preview.n_rows} data rows, {preview.columns.length} columns. Preview of the first rows:
          </p>
          <div className="preview">
            <table className="small">
              <thead>
                <tr>
                  {preview.columns.map((c) => (
                    <th key={c}>{c}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((r, i) => (
                  <tr key={i}>
                    {r.map((v, j) => (
                      <td key={j}>{v}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {preview.problems.length > 0 && (
            <p className="warn">
              Problems found: {preview.problems.map((p) => p.message).join(' ')} These rows will be rejected, not dropped.
            </p>
          )}
          <div className="cols2">
            <fieldset>
              <legend>Input (x)</legend>
              <label>
                Column{' '}
                <select aria-label="Input column" value={xCol} onChange={(e) => pickDefaults(preview, Number(e.target.value), yCol)}>
                  {preview.columns.map((c, i) => (
                    <option key={c} value={i}>
                      {c}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Label <input aria-label="Input label" value={labels.xl} onChange={(e) => setLabels({ ...labels, xl: e.target.value })} />
              </label>
              <label>
                Unit <input aria-label="Input unit" placeholder="e.g. m" value={labels.xu} onChange={(e) => setLabels({ ...labels, xu: e.target.value })} />
              </label>
            </fieldset>
            <fieldset>
              <legend>Response (y)</legend>
              <label>
                Column{' '}
                <select aria-label="Response column" value={yCol} onChange={(e) => pickDefaults(preview, xCol, Number(e.target.value))}>
                  {preview.columns.map((c, i) => (
                    <option key={c} value={i}>
                      {c}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Label <input aria-label="Response label" value={labels.yl} onChange={(e) => setLabels({ ...labels, yl: e.target.value })} />
              </label>
              <label>
                Unit <input aria-label="Response unit" placeholder="e.g. s" value={labels.yu} onChange={(e) => setLabels({ ...labels, yu: e.target.value })} />
              </label>
            </fieldset>
          </div>
          <p className="dim">Units are labels only. NextLab does not convert units.</p>
          <FeasibleFields v={feas} set={setFeas} xUnit={labels.xu} />
          <label className="sd">
            Response noise SD{labels.yu ? ` (${labels.yu})` : ''}, optional{' '}
            <input aria-label="Response noise SD" value={sd} onChange={(e) => setSd(e.target.value)} placeholder="leave empty if unknown" />
          </label>
          <p className="dim">
            The typical scatter of one measurement. Used only if no x value is repeated; with repeats, scatter is estimated
            from them. With neither, noise is reported as unknown.
          </p>
          <FieldErrors errors={errors} />
          <button className="primary" onClick={() => void onLoad()} disabled={disabled || busy}>
            {busy ? 'Checking…' : 'Load data and compare models'}
          </button>
        </>
      )}
      {!preview && <FieldErrors errors={errors} />}
    </section>
  )
}

/** Change feasible settings or the stated noise SD for loaded upload data. */
export function SettingsEditor({
  context,
  locked,
  busy,
  onApply,
}: {
  context: ExperimentContext
  locked: boolean
  busy: boolean
  onApply: (req: ReturnType<typeof feasibleRequest>['req'], sd: number | null) => Promise<FieldError[]>
}) {
  const xs = context.candidate_x
  const [feas, setFeas] = useState<FeasibleInput>({ lo: '', hi: '', step: '', list: xs.join(', ') })
  const [sd, setSd] = useState(context.response_sd === null ? '' : String(context.response_sd))
  const [errors, setErrors] = useState<FieldError[]>([])
  const apply = async () => {
    const fr = feasibleRequest(feas)
    const local = [...fr.errors]
    let v: number | null = null
    if (sd.trim()) {
      v = Number(sd)
      if (!Number.isFinite(v)) local.push({ field: 'response_sd', message: 'Enter a number or leave empty.' })
    }
    setErrors(local.length ? local : await onApply(fr.req, v))
  }
  return (
    <details className="settings">
      <summary>Feasible settings and noise assumption</summary>
      <p className="dim">
        Current: {xs.length} settings from {sig(Math.min(...xs))} to {sig(Math.max(...xs))} {context.x_unit}. Changing them, or
        the noise SD, discards any pending recommendation.
      </p>
      {locked ? (
        <p className="warn">Update the models with the entered values before changing settings.</p>
      ) : (
        <>
          <FeasibleFields v={feas} set={setFeas} xUnit={context.x_unit} />
          <label className="sd">
            Response noise SD{context.y_unit ? ` (${context.y_unit})` : ''}{' '}
            <input aria-label="Response noise SD" value={sd} onChange={(e) => setSd(e.target.value)} placeholder="unknown" />
          </label>
          <button onClick={() => void apply()} disabled={busy}>
            Apply settings
          </button>
        </>
      )}
      <FieldErrors errors={errors} />
    </details>
  )
}

/** Enter the measured response(s) at the frozen setting. Never filled in automatically. */
export function MeasurementEntry({
  x,
  context,
  disabled,
  onSubmit,
}: {
  x: number
  context: ExperimentContext
  disabled: boolean
  onSubmit: (ys: number[]) => void
}) {
  const [text, setText] = useState('')
  const [error, setError] = useState<string | null>(null)
  const submit = () => {
    const p = parseNumbers(text)
    if ('bad' in p) return setError(`"${p.bad}" is not a number.`)
    if (p.values.length === 0) return setError('Enter at least one measured value.')
    if (p.values.length > 50) return setError('At most 50 values at once.')
    setError(null)
    onSubmit(p.values)
  }
  return (
    <section className="panel entry">
      <label>
        Measured {context.y_label || 'response'}
        {context.y_unit ? ` (${context.y_unit})` : ''} at {context.x_label || 'x'} = {x} {context.x_unit}: one value, or
        repeats separated by commas{' '}
        <input aria-label="Measured values" value={text} onChange={(e) => setText(e.target.value)} placeholder="e.g. 5.1, 5.3" />
      </label>
      <button className="primary" onClick={submit} disabled={disabled}>
        Record measurement
      </button>
      {error && <p className="warn" role="alert">{error}</p>}
    </section>
  )
}
