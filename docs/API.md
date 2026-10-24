# NextLab HTTP API (v0.2.0)

**Basics:**
- Implemented in `backend/src/api.jl`. The types are mirrored in `frontend/src/api.ts`.
- JSON in and out. The server binds to `127.0.0.1:8080` by default. No CORS headers are
  sent: the browser reaches the API through the Vite proxy (development) or the same
  Julia process (demo).
- **Stateless:** the server keeps no session table. The browser holds an
  `ExperimentContext` and sends it with every numerical request.

## Experiment context and revisions
```ts
ExperimentContext = { mode: "demo" | "upload", session_id, dataset_id,
  observed: {x, y}[], candidate_x: number[], revealed_x: number[],
  response_sd: number | null, x_unit, y_unit,
  x_label, y_label, source_name }   // descriptive only; not part of the revision
```

**Session id:**
- A random 128-bit id issued by `/api/demo/start` or `/api/upload`.
- A new id on every start, reset or upload. That invalidates older in-flight requests and snapshots.

**`revision`:**
- SHA-256 over the mode, session, dataset, observations (order-free), feasible settings,
  revealed lengths, model configuration (`nextlab-core-1`, the three families) and `response_sd`.
- Every numerical response echoes `revision` and `session_id`.
- The frontend's `assertCurrent` rejects any response that doesn't match the state on screen.

**Demo contexts are checked against the recorded data:**
- The observed rows must equal the declared start plus all reported periods at the revealed lengths.
- The candidates must equal the unrevealed recorded lengths.

The scientific core never sees the demo table. `demo_adapter.jl` is the only reader, and
`/api/demo/reveal` returns one recorded length at a time.

## Snapshots
- `/api/recommend` returns an immutable prediction snapshot, with these fields:
  - `snapshot_id`
  - `context_revision` (the context it was made for)
  - `record`, the frozen `PredictionRecord`:
    - `data_revision` (observed rows only)
    - the selected `x`
    - every model's formula, `a`, `b`, `support` and `predicted_y`
    - the noise assumptions and the acquisition method
  - `selection` (kind, fallback reason, explanation)
  - `diagnostic_state`
- **`snapshot_id`:** the SHA-256 of the content, with all numbers normalized to Float64 (and signed zero to 0.0) so
  that browser re-serialization (`16.0` → `16`, `-0.0` → `0`) still verifies. Context revisions use the same canonical form.
- **Verification on reveal, observe and export:**
  - An altered snapshot → 422.
  - A different session or a changed context → 409.
- **Nothing refits automatically:** reveal and observe return `refit_performed: false`,
  plus an `updated_context`. Refitting happens only when the client calls `/api/analyze`
  (or `/api/recommend`) with that context.

## Routes
| Method & path | Request | Response (200) | Errors |
|---|---|---|---|
| GET `/api/health` | none | `{status, service, api_version, julia_version}` | |
| GET `/api/ready` | none | `{ready, checks: [{name, ok}]}`. Benchmark results are optional. | 503 if demo data or method check fails |
| POST `/api/demo/start` | `{}` | `{context, revision, dataset (provenance), counts}`: start rows and remaining lengths only. Also used for reset. | |
| POST `/api/analyze` | `{context}` | `{revision, session_id, status, analysis, curves}`. `analysis` is the full core result: models, support, diagnostics, `data.revision`. `curves` holds model and ensemble curves on a 101-point geometric grid (even spacing on a log x axis), plus the exact ends of the measured range. | 422 field errors |
| POST `/api/recommend` | `{context}` | as analyze, plus `snapshot`. `snapshot` is `null` when `status = "no_candidates"`. | 422 (including fewer than 3 distinct x) |
| POST `/api/demo/reveal` | `{context, snapshot}` | `{revision, session_id, snapshot_id, x, observations, comparison, refit_performed: false, updated_context, updated_revision}` | 422 (not demo, unknown or revealed length, altered snapshot), 409 (stale) |
| POST `/api/observe` | `{context, snapshot, y: number[]}` (1–50 values) | same shape as reveal | 422 (not upload mode, bad values), 409 (stale) |
| POST `/api/upload/preview` | `{csv}` | `{columns, n_rows, rows (first 8, as text), column_info: [{name, numeric_rows, other_rows, min, max, distinct}], problems}` | 422 if unreadable |
| POST `/api/upload` | `{csv, x_column?, y_column?, bounds?: {lo, hi, step} \| {lo, hi, n}, candidate_x?, response_sd?, x_label?, x_unit?, y_label?, y_unit?, source_name?}`. The range and the list are combined, deduplicated (12 significant digits) and capped at 201. | `{context, revision, columns, x_column, y_column, counts: {observations, settings, candidates, candidates_outside_observed_range}, observed_range}` | 422 with row-numbered CSV errors and `bounds.*` / `candidate_x[i]` field errors |
| GET `/api/sample.csv` | none | The derived two-column pendulum file (`length_m,period_s`), as a download | |
| POST `/api/feasible` | `{lo?, hi?, step? \| n?, candidate_x?}` | `{candidate_x}`: the same combination rule as upload | 422 |
| POST `/api/export` | `{context, history: [{snapshot, updated}]}`. Send the context that includes any values waiting for Update. | `{record_id, exported_at, record, observations_csv}`; see below | 422 if a snapshot doesn't verify |
| GET `/api/benchmark` | none | `{meta, primary_endpoint, verdicts, paired, summary, nextlab_choices, reproduce: {command, protocol, results_dir}}` | 404 if there are no saved results |
| GET `/api/benchmark/files/{name}` | `name` ∈ `runs.csv`, `summary.csv`, `paired.csv`, `nextlab_choices.csv`, `meta.json` | The saved file, as a download | 404 for any other name |

**Error shape:** `{error: string, fields: [{field, message}]}`, with field paths such as
`context.observed[3].x`, `bounds.hi` and `y[1]`.
- 400: malformed JSON.
- 413: body over 2 MB (enforced by HTTP.jl, so the body is empty).
- 500: no internal details. The request body is never logged.

## Experiment record (`nextlab-experiment-record-2`)
- **IDs:** `record_id` is the SHA-256 of the record content. The record also carries the
  `session_id`, the context `revision` and every `snapshot_id`.
- **`run_type`:** `recorded_data_replay` or `user_uploaded_data`. Synthetic benchmark
  runs are not exported this way; they live in `results/`.
- **`source`:**
  - demo: the provenance, including the source links, plus a note that revealed values are
    recorded measurements, not new ones
  - upload: the file name and a content-hash dataset ID
- **Experiment settings:** `variables` (labels and units), `method` (the version and exact
  formulas), `feasible_settings`, and `noise_assumption` (the stated SD and the current estimate).
- **`observations`:** each row with `origin` (`recorded_initial_subset`, `revealed_recorded_value`,
  `uploaded_file` or `entered_manually`) and the cycle it came from.
  - Unrevealed demo values are never included.
  - Rows at a frozen recommendation's x are attributed to that cycle, because recommendations only choose unmeasured settings.
- **`cycles`, in order:** for each cycle,
  - the snapshot ID, the context and data revisions, and the time it was frozen
  - the selected x, the selection reason and the diagnostic state
  - the frozen predictions, unchanged by later refits
  - the later observations and their comparison
  - `refit_after_observation`, as reported by the client
- **`current_analysis`:** the status, models, diagnostics and explanation.
- **`observations_csv`:** a plain CSV with columns `x label (unit), y label (unit), origin, cycle`.

## Prototype limits
| Limit | Value |
|---|---|
| Request body or CSV | 2 MB |
| Observations (CSV rows or context rows) | 2,000 |
| Feasible settings | 201 |
| Values per manual entry | 50 |
| History snapshots per export | 50 |

## CSV upload
- Parsed in Julia with CSV.jl 1.1, as text first. UTF-8 BOM, CRLF and ordinary quoting are accepted.
- A header row is required. Pick columns by name or 1-based index. If there are exactly two columns, they are x and y.
- Repeated x rows are kept as separate observations.
- **Rejected with data-row numbers** (row 1 is the first row after the header):
  - short or long rows, and malformed quoting
  - non-numeric values
  - x ≤ 0, and non-finite values
  - fewer than 3 distinct x values
- Nothing is silently dropped, and uploaded content is never evaluated.

## Numeric fields
JSON.jl parses out-of-range literals (`1e999`, `-1e999`, 400-digit integers) as
`BigFloat`/`BigInt`. These are finite before conversion and ±Inf after it.

Every numeric request field goes through `json_float`. It converts to Float64, catches
conversion failures and checks finiteness after conversion. An out-of-range value becomes a
422 field error. The fields covered are:
- `context.observed[i].x/y`
- `context.candidate_x`, `context.revealed_x` and `context.response_sd`
- `y` on observe
- `bounds.lo/hi`
- `response_sd` and `candidate_x` on upload

A tiny literal such as `1e-999` converts to 0, so it fails the positivity checks for x and bounds.
`bounds.n` and column indices must be in-range integers and are range-checked before conversion.
Fixed via `/tdd` on 2026-10-24. The regression tests are in `backend/test/api_tests.jl`.
