# NextLab status

_Last updated: 2026-10-24 16:21 EDT. Milestone: Prompt 05, benchmark run._

## Deadline
- **Earliest submission deadline: UNKNOWN.** The event information has not been supplied in
  the working session. Get the submission-creation and final submission deadlines from
  the organizers, record them here, and keep the last two hours before the real deadline
  for demo and submission work.

## Git
- `main` holds the user's milestone commits up to `542c727`, which includes the core and the /tdd fix.
- The local branch `benchmark` has two more commits:
  - `dac3e46` pre-registers the protocol and code, before any run
  - `d1d7481` is a metadata-only fix
- Not pushed. The results write-up (`docs/BENCHMARK.md` Results, `docs/SPEC.md`, this file)
  and `results/` are not committed.

## Works now (verified)
- **Toolchain:** Julia 1.13.2 (Homebrew `juliaup`). `backend/` package `NextLab` uses HTTP 2.12.3,
  JSON 1.12.2, CSV 1.1.0, plus SHA, Dates, Statistics, LinearAlgebra and Random. Vite 8,
  React 19 and TypeScript 6 are in `frontend/`.
- **API:** `GET /api/health`, `GET /api/pendulum` and `POST /api/pendulum/reset`. The
  frontend shows provenance and replay state. The core is not exposed over HTTP yet.
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
  - 245/245 pass. The suites are snapshot 10, replay 21, core 150, benchmark 50 and API 14.
  - The benchmark checks cover equal costs, disjoint test inputs, fixed-seed repeatability,
    tampering with unrequested rows (no effect for any policy), noise independent of
    policy random calls, one shared predictor, and win/tie counting.
- `run_benchmark.jl smoke 5`: no failures (crash and runtime check only).
- `run_benchmark.jl full 100`: 0 predictor failures and 0 NextLab step failures.

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

## Fixed via /tdd
- **Overflow in `fit_family` scaling** (centred features around 1e160 were reported as
  `:rank_deficient`). The fix divides by max|f| before centring.
  - Failing before: core 148 pass, 2 fail.
  - Passing after: core 150/150.

## Findings to carry forward (not tuned)
- On the pendulum start, the square-root model holds more than 0.999 support, so the demo's
  recommendations are space-filling fallbacks (16 m, then 8 m).
- At 16 m the leading model missed by about 11 setting-mean SDs. Repeat scatter grows with
  length, so constant variance is an approximation.

## Background servers
Both dev servers (Vite on 5173, Julia on 8080) were stopped by the background time limit.
Restart them with the commands in `README.md` when UI work resumes.

## Not built yet
- core endpoints and UI: analyze, freeze, reveal gated on a frozen record, comparison, refit
- new-observation mode, CSV upload with bounds
- plots (Plotly not installed), record download
- a license for NextLab's own code

## Next
The next build prompt: the UI loop.
