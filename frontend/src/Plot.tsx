import { useEffect, useMemo, useRef } from 'react'
import type { Curves, ModelResult, Observation, Snapshot } from './api'
import { ACCENT, MODEL_STYLE, sig } from './format'

type Props = {
  curves: Curves
  previousCurves: Curves
  models: ModelResult[]
  observed: Observation[]
  revealed: Observation[] | null // shown but not yet fitted
  snapshot: Snapshot | null
  xLabel: string
  yLabel: string
  xUnit: string
  yUnit: string
}

const TICKS = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50]

export function ExperimentPlot(p: Props) {
  const el = useRef<HTMLDivElement>(null)

  const { data, layout, offScale } = useMemo(() => {
    const xs = p.observed.map((o) => o.x)
    const mlo = Math.min(...xs)
    const mhi = Math.max(...xs)
    const ys = [...p.observed, ...(p.revealed ?? [])].map((o) => o.y)
    const frozen = p.snapshot?.record.models.filter((m) => m.predicted_y !== null) ?? []
    const leading = frozen.reduce<(typeof frozen)[number] | null>(
      (best, m) => (best === null || (m.support ?? 0) > (best.support ?? 0) ? m : best),
      null,
    )
    const ensembleMax = p.curves?.ensemble ? Math.max(...p.curves.ensemble) : 0
    const ymax = 1.25 * Math.max(...ys, ensembleMax, leading?.predicted_y ?? 0)
    const gridX = p.curves?.x ?? []
    const allX = [...gridX, ...xs, ...(p.snapshot ? [p.snapshot.record.x] : [])]
    const xlo = Math.min(...allX) / 1.35
    const xhi = Math.max(...allX) * 1.35

    const traces: object[] = []
    // Measured range: the only region where the curves interpolate.
    traces.push({
      x: [mlo, mhi, mhi, mlo, mlo],
      y: [0, 0, ymax, ymax, 0],
      fill: 'toself',
      fillcolor: 'rgba(31,35,40,0.06)',
      line: { width: 0 },
      mode: 'lines',
      hoverinfo: 'skip',
      name: 'Measured range',
      showlegend: true,
    })
    if (p.previousCurves) {
      p.previousCurves.models.forEach((m, i) => {
        if (!m.y) return
        traces.push({
          x: p.previousCurves!.x,
          y: m.y,
          mode: 'lines',
          line: { color: '#8c959f', width: 1.2, dash: 'dot' },
          name: 'Fits before last update',
          legendgroup: 'previous',
          showlegend: i === 0,
          hoverinfo: 'skip',
        })
      })
    }
    p.curves?.models.forEach((c) => {
      if (!c.y) return
      const model = p.models.find((m) => m.id === c.id)
      const st = MODEL_STYLE[c.id]
      const name = model?.name ?? c.id
      const seg = (keep: (x: number) => boolean, inside: boolean, first: boolean) => {
        const idx = gridX.map((x, i) => (keep(x) ? i : -1)).filter((i) => i >= 0)
        if (idx.length < 2) return
        traces.push({
          x: idx.map((i) => gridX[i]),
          y: idx.map((i) => c.y![i]),
          mode: 'lines',
          line: { color: st.color, dash: st.dash, width: inside ? 2.6 : 1.4 },
          opacity: inside ? 1 : 0.5,
          name: inside ? name : `${name} (extrapolated)`,
          legendgroup: c.id,
          showlegend: first,
          hovertemplate: `${name}<br>%{x:.3g} ${p.xUnit} → %{y:.3g} ${p.yUnit}${inside ? '' : ' (extrapolated)'}<extra></extra>`,
        })
      }
      seg((x) => x >= mlo && x <= mhi, true, true)
      seg((x) => x <= mlo, false, false)
      seg((x) => x >= mhi, false, false)
    })
    traces.push({
      x: p.observed.map((o) => o.x),
      y: p.observed.map((o) => o.y),
      mode: 'markers',
      marker: { color: '#1f2328', size: 7 },
      name: 'Recorded observations (fitted)',
      hovertemplate: `%{x} ${p.xUnit}: %{y} ${p.yUnit}<extra>recorded</extra>`,
    })
    if (p.revealed && p.revealed.length) {
      traces.push({
        x: p.revealed.map((o) => o.x),
        y: p.revealed.map((o) => o.y),
        mode: 'markers',
        marker: { color: ACCENT, size: 10, symbol: 'diamond', line: { color: '#fff', width: 1 } },
        name: 'Just revealed (not yet fitted)',
        hovertemplate: `%{x} ${p.xUnit}: %{y} ${p.yUnit}<extra>revealed</extra>`,
      })
    }
    if (p.snapshot) {
      const x = p.snapshot.record.x
      traces.push({
        x: [x, x],
        y: [0, ymax],
        mode: 'lines',
        line: { color: ACCENT, width: 1.5, dash: 'dot' },
        name: `Next measurement: ${x} ${p.xUnit}`,
        hoverinfo: 'skip',
      })
      frozen.forEach((m) => {
        const st = MODEL_STYLE[m.id]
        traces.push({
          x: [x],
          y: [m.predicted_y],
          mode: 'markers',
          marker: { color: st.color, size: 12, symbol: st.symbol, line: { width: 2.5, color: st.color } },
          name: `${m.name}: frozen prediction`,
          legendgroup: m.id,
          showlegend: false,
          hovertemplate: `${m.name} predicted %{y:.3g} ${p.yUnit} at ${x} ${p.xUnit} (frozen)<extra></extra>`,
        })
      })
    }
    const offScale = frozen.filter((m) => (m.predicted_y as number) > ymax)
    const layout = {
      margin: { l: 58, r: 12, t: 8, b: 48 },
      paper_bgcolor: '#ffffff',
      plot_bgcolor: '#ffffff',
      font: { family: 'system-ui, -apple-system, Segoe UI, sans-serif', size: 13, color: '#1f2328' },
      xaxis: {
        type: 'log',
        title: { text: `${p.xLabel} (${p.xUnit}), log scale` },
        range: [Math.log10(xlo), Math.log10(xhi)],
        tickvals: TICKS,
        ticktext: TICKS.map(String),
        gridcolor: '#eaeef2',
        zeroline: false,
      },
      yaxis: { title: { text: `${p.yLabel} (${p.yUnit})` }, range: [0, ymax], gridcolor: '#eaeef2', zeroline: false },
      legend: { orientation: 'h', x: 0, y: 1.0, yanchor: 'bottom', font: { size: 12 } },
      hovermode: 'closest',
    }
    return { data: traces, layout, offScale }
  }, [p])

  useEffect(() => {
    const node = el.current
    // Plotly is a separate vendor chunk (loaded once, then cached by the module system).
    void import('plotly.js-basic-dist-min').then(({ default: Plotly }) => {
      if (node) void Plotly.react(node, data, layout, { displayModeBar: false, responsive: true })
    })
  }, [data, layout])
  useEffect(() => {
    const node = el.current
    return () => {
      if (node) void import('plotly.js-basic-dist-min').then(({ default: Plotly }) => Plotly.purge(node))
    }
  }, [])

  return (
    <figure className="plot">
      <div ref={el} className="plot-canvas" aria-label={`Plot of ${p.yLabel} against ${p.xLabel} with fitted model curves`} />
      <figcaption>
        Solid curves: inside the measured range ({sig(Math.min(...p.observed.map((o) => o.x)))}–
        {sig(Math.max(...p.observed.map((o) => o.x)))} {p.xUnit}). Faint curves: extrapolation.
        {offScale.length > 0 && (
          <>
            {' '}
            <strong>Off scale:</strong>{' '}
            {offScale.map((m) => `${m.name} predicts ${sig(m.predicted_y)} ${p.yUnit}`).join('; ')}.
          </>
        )}
      </figcaption>
    </figure>
  )
}
