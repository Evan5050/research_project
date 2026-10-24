// Display formatting and model styling only; all numerical work happens in Julia.

import type { ModelId } from './api'

export const MODEL_STYLE: Record<ModelId, { color: string; dash: 'solid' | 'dash' | 'dashdot'; symbol: string }> = {
  linear: { color: '#0072B2', dash: 'solid', symbol: 'circle-open' },
  sqrt: { color: '#C2410C', dash: 'dash', symbol: 'square-open' },
  restricted_quadratic: { color: '#047857', dash: 'dashdot', symbol: 'diamond-open' },
}

export const ACCENT = '#5B3FA8'

/** Three significant figures, without trailing ".0". */
export function sig(v: number | null | undefined, digits = 3): string {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—'
  if (v === 0) return '0'
  const a = Math.abs(v)
  if (a >= 1e5 || a < 1e-3) return v.toExponential(digits - 1).replace('e+', 'e')
  return String(Number(v.toPrecision(digits)))
}

export const withUnit = (v: number | null | undefined, unit: string) => (unit ? `${sig(v)} ${unit}` : sig(v))

/** Relative support, never rounded to 0 or 1 and never shown as a percentage. */
export function support(w: number | null | undefined): string {
  if (w === null || w === undefined) return 'n/a'
  if (w >= 0.999) return '> 0.999'
  if (w < 0.001) return '< 0.001'
  return w.toFixed(3)
}

export const shortId = (id: string) => id.slice(0, 8)

/** End a sentence after a value whose unit may already end in a period ("a.u."). */
export const stop = (s: string) => (s.endsWith('.') ? s : `${s}.`)
