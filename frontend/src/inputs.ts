// Input parsing for the upload forms (text to numbers); the server validates again.

import type { FieldError } from './api'

/** Parse "1.2, 3 4" into numbers; returns null with the offending token if one is not a number. */
export function parseNumbers(text: string): { values: number[] } | { bad: string } {
  const tokens = text.split(/[\s,;]+/).filter((s) => s.length > 0)
  const values: number[] = []
  for (const t of tokens) {
    const v = Number(t)
    if (!Number.isFinite(v)) return { bad: t }
    values.push(v)
  }
  return { values }
}

/** Feasible range (lo, hi, step) plus an optional explicit list. Shared by the upload form and the settings editor. */
export type FeasibleInput = { lo: string; hi: string; step: string; list: string }

/** Turn the form into a request; returns local errors for text that is not a number. */
export function feasibleRequest(v: FeasibleInput): { req: { lo?: number; hi?: number; step?: number; candidate_x?: number[] }; errors: FieldError[] } {
  const errors: FieldError[] = []
  const req: { lo?: number; hi?: number; step?: number; candidate_x?: number[] } = {}
  const anyRange = v.lo.trim() || v.hi.trim() || v.step.trim()
  if (anyRange) {
    for (const k of ['lo', 'hi', 'step'] as const) {
      const n = Number(v[k])
      if (!v[k].trim() || !Number.isFinite(n)) errors.push({ field: `bounds.${k}`, message: 'Enter a number.' })
      else req[k] = n
    }
  }
  if (v.list.trim()) {
    const p = parseNumbers(v.list)
    if ('bad' in p) errors.push({ field: 'candidate_x', message: `"${p.bad}" is not a number.` })
    else req.candidate_x = p.values
  }
  return { req, errors }
}

