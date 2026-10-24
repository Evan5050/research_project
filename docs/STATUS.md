# NextLab status

_Last updated: 2026-10-24 16:07 EDT. Milestone: Prompt 04 core, plus the /tdd overflow fix._

## Deadline
- **Earliest submission deadline: UNKNOWN.** The event information has not been supplied in
  the working session. Get the submission-creation and final submission deadlines from
  the organizers, record them here, and keep the last two hours before the real deadline
  for demo and submission work.

## Works now (verified)
- **Toolchain:** Julia 1.13.2 (Homebrew `juliaup`). `backend/` package `NextLab` uses HTTP 2.12.3,
  JSON 1.12.2, CSV 1.1.0, plus SHA, Dates, Statistics, LinearAlgebra and Random. Vite 8,
  React 19 and TypeScript 6 are in `frontend/`. Nothing has been committed to git yet.
- **API:** `GET /api/health`, `GET /api/pendulum` and `POST /api/pendulum/reset`.
  The frontend shows provenance and the replay state. The core is not exposed over HTTP yet.
- **Data and replay:** fastR2 snapshot, provenance, and the replay engine (`reveal!`,
  `reset!`, `engine_inputs`). See `data/README.md`.
- **Scientific core** (`backend/src/models.jl`, `analysis.jl`, `record.jl`), as
  specified in SPEC "Numerical method":
  - QR fits on setting means for the three families
  - in-sample RMSE and grouped leave-one-setting-out RMSE
  - pooled repeat noise, a stated SD, or explicitly unknown
  - heuristic support weights
  - disagreement acquisition with the maximin fallback
  - separation and adequacy labels, and plain explanations
  - immutable `PredictionRecord`
- **Demo adapter:** `recommend(session)` uses only `engine_inputs`.
- **Example:** `julia --project=backend backend/scripts/example_recommendation.jl` runs
  start → recommendation (16 m, space-filling) → freeze → reveal → refit → next
  recommendation (8 m).

## Commands run and their outcomes
- `julia --project=backend --threads=auto,1 -e 'using Pkg; Pkg.test()'`:
  - 195/195 pass. The suites are snapshot 10, replay 21, core 150 and API 14.
- The core tests cover:
  - noiseless coefficient and held-out recovery for all three families
  - agreement with R `lm()` (R 4.5.3) on setting means, to rtol 1e-10. The fixture and
    script are in `backend/test/fixtures/`.
  - repeated-x aggregation and row-order independence
  - grouped validation with no replicate leak
  - invalid input, too few settings, constant response, overflow and degenerate range
  - noise sources, deterministic feasible selection, the maximin fallback and no-candidates
  - down-weighting a wildly wrong model (its share of the spread is under 1%; with equal
    weights it would be over 50%)
  - the no-adequate-model heuristic
  - recommendations unaffected by hidden outcomes
  - the frozen record unchanged after refit
- The example script ran. Output is summarised in SPEC "Observed behaviour".

## Fixed via /tdd
- **Overflow in `fit_family` scaling.** `sqrt(mean(abs2, f .- μ))` returned Inf for
  centred features around 1e160, which zeroed the scaled column, so the linear fit was
  reported as `:rank_deficient`. The fix divides by max|f| before centring.
  - Failing before: core suite 148 pass, 2 fail (`linear.fitted`, and `linear.a` evaluated NaN ≈ 1e-160).
  - Passing after: core 150/150, full suite 195/195.
  - Pendulum example output is unchanged.

## Findings to carry forward (not tuned)
- On the pendulum start, the square-root model holds more than 0.999 support, so every
  recommendation so far is the space-filling fallback, not disagreement sampling.
- At 16 m the leading model missed by about 11 setting-mean SDs. Repeat scatter grows with
  length, so constant variance is an approximation.

## Not built yet
- core endpoints and UI: analyze, freeze, reveal gated on a frozen record, comparison, refit
- new-observation mode, CSV upload with bounds
- plots (Plotly not installed), record download, the benchmark (Prompt 05)
- a license for NextLab's own code

## Next
Prompt 05: the benchmark. Commit the protocol before the first run.
