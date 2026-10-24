# NextLab status

_Last updated: 2026-10-24 19:00 EDT. Milestone: Prompt 12, presentation and launch reliability._

## Deadline
- **Earliest submission deadline: UNKNOWN.** The event information has not been supplied in
  the working session. Get the submission-creation and final submission deadlines from
  the organizers, record them here, and keep the last two hours before the real deadline
  for demo and submission work.

## Git
- Current branch `benchmark`, at `6cdd0a0` (the user's commit containing the audit and /tdd fixes). `main` is at `542c727`.
- This milestone's presentation and launch work is uncommitted and nothing has been pushed.

## Works now (verified)
- **Toolchain:** Julia 1.13.2 (Homebrew `juliaup`). `backend/` package `NextLab` uses HTTP 2.12.3,
  JSON 1.12.2, CSV 1.1.0, plus SHA, Dates, Statistics, LinearAlgebra and Random. Vite 8,
  React 19 and TypeScript 6 are in `frontend/`.
- **API v0.2.0** (stateless; contract in `docs/API.md`; types in `frontend/src/api.ts`):
  - health and ready
  - demo start/reset and demo reveal
  - analyze (with curves)
  - recommend (immutable snapshot with a content-hash id)
  - observe (manual entry, upload mode)
  - upload (CSV parsed in Julia), feasible grid, export, and the benchmark summary
  - whitelisted benchmark file downloads (`/api/benchmark/files/{name}`)
  - CSV preview (`/api/upload/preview`), the sample file (`/api/sample.csv`), and feasible settings from a range with step and/or a list (deduplicated, at most 201)
  - experiment record v2 (`/api/export`) with observation origins, ordered cycles, frozen predictions and a plain observations CSV
  - curves on a geometric grid that includes the measured-range ends
  - A revision and session id invalidate stale recommendations and responses. Reveal and observe never refit.
  - Limits: 2 MB body and 2,000 rows. The server binds to 127.0.0.1 only.
  - The old `/api/pendulum` routes and the server-side session were removed.
- **Frontend workbench** (`frontend/src/App.tsx`, `state.ts`, `Plot.tsx`, `Panels.tsx`): the built-in
  pendulum loop, Compare → Recommend → Reveal → Update, repeatable through all 6 hidden lengths.
  - A reducer with an epoch and revision checks, plus a synchronous in-flight guard.
  - Reveal appears only after a frozen snapshot. Recommend waits until an explicit Update.
  - The plot uses a log length axis. Curves are solid inside the measured range and faint when
    extrapolated; there are frozen-prediction markers and newly revealed points, and any
    off-scale predictions are listed below the plot.
  - Model cards show the exact formula, validation RMSE and relative support.
  - Shown states: backend-unavailable, invalid-data, no-candidates, low-separation, poor-fit
    and noise-unknown, plus prediction history, an assumptions panel, record download and a
    benchmark section (labelled simulation).
  - Plotly basic 4.1.2 (MIT) is loaded as a separate vendor chunk.
- **"Use my data"** (`frontend/src/Upload.tsx`, `inputs.ts`):
  - Load a local CSV and preview it through the Julia parser; pick the x and y columns, labels and units (labels only, no conversion).
  - Set feasible settings with a range and step and/or an explicit list, defaulting to the observed range of the chosen x column. Settings beyond the observed range are counted and labelled as extrapolation.
  - An optional noise SD, explained in place; noise is labelled unknown when there are no repeats and no SD.
  - After the freeze, enter the measured value(s) by hand; nothing is simulated. Then the same explicit Update as the demo.
  - A settings editor discards any pending recommendation.
  - Download record saves the JSON record plus the observations CSV.
  - Uploaded data stays in the browser state and the local server only (no storage); no stronger privacy claim is made.
- **Data and replay:** fastR2 snapshot, provenance, and the replay engine. Its only gateway
  to the core is `engine_inputs`. See `data/README.md`.
- **Scientific core** (`nextlab-core-1`): see SPEC "Numerical method". Added in this
  milestone: `ensemble_predict`, the support-weighted ensemble mean that the benchmark uses for every policy.
- **Example:** `julia --project=backend backend/scripts/example_recommendation.jl`, the pendulum loop.
- **Benchmark** (`backend/src/benchmark.jl`, `backend/scripts/run_benchmark.jl`):
  - The protocol is declared in `docs/BENCHMARK.md`.
  - Full run: 100 seeds, 38,400 rows, 7.3 s. Output in `results/benchmark_full/`.
  - Byte-identical when rerun with 4 instead of 11 threads.

## Commands run and their outcomes
- `julia --project=backend --threads=auto,1 -e 'using Pkg; Pkg.test()'`:
  - 386/386 pass. The suites are snapshot 10, replay 21, core 150, benchmark 50, snapshot
    hashing 4 and API 151; readiness now requires warmup.
  - The API tests run against a real server. They cover the full demo loop; no unrevealed
    periods in the start or recommend payloads; reveal returning only the selected length;
    browser-style JSON numbers accepted; stale (409) and tampered (422) snapshots;
    field-level context errors; 400 and 413; CSV with BOM, CRLF and quotes; row-numbered
    CSV errors; impossible bounds; out-of-range JSON numbers in every numeric field; the
    upload observe flow; and the benchmark route.
  - The benchmark checks cover equal costs, disjoint test inputs, fixed-seed repeatability,
    tampering with unrequested rows (no effect for any policy), noise independent of
    policy random calls, one shared predictor, and win/tie counting.
- `run_benchmark.jl smoke 5`: no failures (crash and runtime check only).
- `run_benchmark.jl full 100`: 0 predictor failures and 0 NextLab step failures.
- `backend/scripts/api_smoke.jl` against the live server on :8080: all 8 checks pass.
- `scan_hidden.jl`:
  - the app chunk and `frontend/src` are clean
  - the Plotly vendor chunk has 22 matches, identical to the unmodified upstream
    `plotly-basic.min.js` (SVG icon path coordinates, not data)
- `npm run lint`: 0 warnings. `npm run build` passes.
- `frontend/scripts/browser-check.mjs`, headless Brave at 1366×768 and 1280×720: 68/68 pass (exit 0), including keyboard focus and no non-localhost requests.
  It now also checks:
  - displayed and exported predictions equal the raw `/api/recommend` response
  - double clicks on every action
  - a late response after a dataset switch
  - page errors
  - the full cycle (16 m → 7.68, 8.01, 7.68 s, mean 7.79 s → update), the second recommendation (8 m), and the replay run to completion (6 rows, then "Replay complete")
  - axis labels, legend, model cards, and the decision above the fold
  - one request from a same-tick double click
  - reset, and a stale response after reset ignored
  - simulated backend failure and recovery, and a simulated 422 with field messages
  - The upload flow (50 checks in total, run twice, all passing):
    - the sample CSV download and upload (27 rows, 9 distinct values)
    - a malformed value ("Data row 2: y ("abc") …")
    - a BOM/CRLF/quoted 3-column file with column selection and repeats kept (5 rows, 3 distinct values)
    - invalid bounds (`bounds.hi`)
    - an invalid manual entry rejected, then manual entry, compare, update and a settings change
    - switching dataset both ways, start over
    - the real downloaded JSON and CSV for both modes; the demo export contains no unrevealed values
  - Screenshots were inspected by eye.

## Benchmark result
At 8 settings (24 observations), comparing RMSE against the noiseless truth at 200 held-out inputs:
- **vs random:** better in 11/16 conditions (all 8 clustered starts, and 3 of 8 ends+middle), worse in 0.
- **vs preplanned evenly spaced:** better 8, no clear difference 7, worse 1 (C10).
- **vs endpoint-first + maximin:** better 2 (consistent with chance across 48 comparisons), no clear difference 14, worse 0.
- **At intermediate budgets:** clear losses, notably at 4 settings from the cluster start
  (an endpoint-first pick that the strong baseline shares) and under T4, where NextLab
  keeps choosing near the edges.
- **Supported claim:** final accuracy is on par with a strong space-filling design, with
  no design advantage. Position NextLab around the transparent workflow and its measured
  limits. Full detail is in `docs/BENCHMARK.md`.

## Audit fixes (browser reproduction failed before, passes after)
- Apply settings is disabled while a request is in flight.
- Zero-variability repeats show the backend's reason, not "noise unknown".
- No Recommend action is offered when no model can be fitted.
- Upload-mode wording no longer says "length".
- Benchmark results are flagged in the API and UI if their method version differs from the running one.

## Fixed via /tdd
- **Negative zero broke snapshot verification.** Fits can return `a = -0.0` (for example,
  constant-response uploads), and browsers serialize `-0` as `0`. As a result, the unaltered
  snapshot was rejected ("snapshot was altered"), and a context containing a `-0.0` value got
  a different revision after the round trip. `normalize` now maps signed zero to `0.0` before
  hashing, which covers both snapshot IDs and context revisions.
  - Failing before: API tests 148 pass, 3 fail (the hash, observe 422, the revision mismatch).
    Browser check: 3 FAIL, exit 1 (measurement rejected, so update and export were never reached).
  - Passing after: API 151/151, full suite 382/382, browser check 64/64 (exit 0), and the smoke check passes.
  - Detection of altered snapshots is unchanged (the tampering tests and the 5e-324 change test pass).
- **Out-of-range JSON numbers passed validation.** JSON.jl parses `1e999` and huge integers
  as finite `BigFloat`/`BigInt`, which became ±Inf only after conversion. `/api/feasible`
  returned HTTP 500; other fields accepted Inf. Now every numeric field goes through
  `json_float`: convert, catch conversion failure, check finiteness after conversion,
  and return a 422 field error.
  - Failing before: API 89 pass, 23 fail.
  - Passing after: API 112/112, full suite 343/343, and the live smoke check passes.
- **Overflow in `fit_family` scaling** (centred features around 1e160 were reported as
  `:rank_deficient`). The fix divides by max|f| before centring.
  - Failing before: core 148 pass, 2 fail.
  - Passing after: core 150/150.

## Findings to carry forward (not tuned)
- On the pendulum replay, all 6 recommendations are space-filling fallbacks (16, 8, 4, 2.437, 1.485,
  0.809 m). Square root is the closest frozen prediction every time. From cycle 2 on, the
  support-weighted spread is 0, because Square root holds essentially all the support; the UI says
  so and shows the range of the unweighted predictions. The poor-fit state never appeared on the real data.
- At 16 m the leading model missed by about 11 setting-mean SDs. Repeat scatter grows with
  length, so constant variance is an approximation.

## Launch and presentation (Prompt 12)
- **Launch:** `./nextlab` builds the frontend and serves it with the API.
  - `serve.jl` warms up the demo and upload routes over HTTP with throwaway sessions and
    synthetic data, then prints READY. `/api/ready` reports `warmed_up` and the warmup timings.
  - Port conflicts get a clear message.
  - Clean start: ready in 15 s. Restart after `kill -9`: ready in 16 s.
  - Warmup first pass, including compilation: 10.8–11.4 s. Steady-state `/api/recommend`
    median: 1.2 ms. No comparison with any other implementation.
- **Presentation:**
  - a fixed "Known now / Hidden for replay (or Feasible next)" block above the primary action
  - recommendation labelled "Discriminating measurement" or "Space-filling validation point", with "Why feasible"
  - a "What changed" verdict naming the leading model, with rises in validation error marked "↑ worse"
  - visible definitions under the model cards (no hover-only tooltips)
  - larger plot text, a clearer record button label, focus outlines on links and summaries, and a reduced-motion rule
- **Checked:** contrast ≥ 5.08:1 for every text and colour pair used.
- **Checklist:** `docs/LAUNCH.md`.

## Background servers
NextLab is running via `./nextlab` on 127.0.0.1:8080 (after the crash-restart test).

## Not built yet
- a license for NextLab's own code

## Next
The next build prompt.
