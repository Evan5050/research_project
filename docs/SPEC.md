# NextLab specification

## Purpose and user
- **User:** a research trainee who understands plots but should not have to write code.
- **Bottleneck removed:** comparing a few candidate models, deciding what to measure
  next, recording predictions before outcomes, and updating the analysis.
- **Core capability:** the measurement decision, meaning which x to measure next and what
  each model committed to before the result.

## Core loop
Load observations → compare three model families → recommend one feasible next x →
show and freeze each model's prediction → reveal a recorded observation or enter a new
one → compare it with the frozen predictions → refit explicitly and show what changed.

## Modes
- **Reveal mode** (built-in or uploaded dataset): candidates are the measured x settings
  not yet revealed. The outcome is the recorded value.
- **New-observation mode:** candidates come from user-set feasible bounds. The user
  enters the measured y.

## Model families
Each has exactly two fitted parameters, a and b:
1. Linear: `y = a·x + b`
2. Square root: `y = a·√x + b`
3. Restricted quadratic: `y = a·x² + b`. This is labelled explicitly as having no separate linear term.

## Data
- One positive numeric input x and one numeric response y.
- Built-in demo: pendulum length (m) versus reported period (s). The exact CSV snapshot and
  attribution come from build Prompt 03. The periods are averages over several swings,
  not raw individual swing timings.
- Two-column CSV upload. Repeated x values are kept as repeated observations. In
  uploaded-data mode, the user sets the feasible bounds or a candidate list separately.
- The source, license (GPL >= 2, kept as declared), files and limitations are in `data/README.md`.

## Real-data replay contract
- **Start:** the three shortest distinct lengths (0.101, 0.205 and 0.411 m), with 9 observations.
  This is a declared teaching scenario chosen by x order, not by outcome.
- **Candidates:** only the six remaining recorded lengths.
- **One reveal:** shows all three reported periods at one length. NextLab counts and displays
  both lengths measured and individual observations. A benchmark never counts three
  observations as one raw measurement.
- **What the engine sees:** only observed records enter fitting, noise estimation or
  acquisition. It gets `engine_inputs`, which is observed x and y plus the candidate x
  values only. Unrevealed periods stay out of the browser payload and the bundle. This
  keeps the scientific inputs separate; it is not a claim that public data is secret.
- **Reset:** restores the exact initial state.

## Numerical method (`nextlab-core-1`; code in `backend/src/models.jl`, `analysis.jl`, `record.jl`)
Defaults were frozen before any benchmark was run. Do not tune them after seeing benchmark results.

**Inputs:** `analyze(x, y, candidate_x; response_sd, x_unit, y_unit)` takes observed
records, feasible candidate settings and an optional stated response SD. It has no
parameter for hidden outcomes, a true formula or test outcomes. The replay adapter
`recommend(session)` passes only `engine_inputs`.

**Validation:**
- x must be positive and finite, and y finite. The x and y lengths must match.
- A stated SD must be positive and finite.
- Errors return `status = :invalid_input` with the offending row numbers.
- Comparison and recommendation need at least 3 distinct x values; otherwise the status is `:insufficient_data`.
- Candidates that are not positive and finite are dropped with a warning.

**Grouping:**
- Repeated rows stay as observations: both counts are reported.
- Each distinct x contributes one mean with equal weight, regardless of its number of
  repeats. This is a deliberate simplification: it stops a heavily repeated setting from
  dominating, at the cost of ignoring that its mean is more precise.

**Fit** for each family y = a·f(x) + b:
- Transform first. Then divide f by max|f| (so squaring cannot overflow for large
  finite f), centre and scale by the population SD, and solve
  `[1 z] β = ȳ` by QR (`qr(A) \ ȳ`). No explicit inverse.
- Convert back to the original formula: a = β₂/(s·max|f|) and b = β₁ − β₂·μ/s.
- Failures are reported as diagnostics, never as NaN coefficients:
  `:nonfinite_feature`, `:degenerate_range` (s ≤ 1e-12·|μ|), `:rank_deficient`
  (|R₂₂| ≤ 1e-10·|R₁₁|), and non-finite coefficients or fitted values.

**Metrics:**
- `fit_rmse_setting_means` is in-sample (training) error on setting means.
- `grouped_cv_mse` / `grouped_cv_rmse`: leave one distinct setting out, which removes
  all of its replicates. Refit on the rest (at least 2 settings) and predict the held-out
  mean. L_m is the mean squared error over folds. Only this metric describes unseen
  settings, and even then only interpolation and extrapolation within the observed design.

**Noise:**
- If any setting has repeats, the response SD is pooled from them:
  σ̂² = Σ within-setting sum of squares / Σ(nᵢ − 1). This assumes independent observations with one constant variance.
- Otherwise a stated `response_sd` is used, and only when there are no repeats.
- Otherwise noise is `:unknown`. Separation and adequacy are then not assessed, and the result says so.
- The SD of a setting mean is σ̂/√nᵢ. When counts differ, the representative
  setting-mean variance is σ̂²·mean(1/nᵢ) over the measured settings. This is not a
  heteroscedastic or errors-in-variables model, and x is treated as exact.

**Relative support:**
- w_m ∝ exp(−(L_m − min L)/(2s²)), normalized over models with a valid validation fit.
- s² = max(min L, representative setting-mean variance, floor), where
  floor = 1e-12·max(1, mean ȳ²). The floor protects the arithmetic; it is not measured noise.
- Support is a heuristic from validation error, not a probability that a model is true.
- Support below 0.05 is labelled "strongly down-weighted".
- Underflow can make support exactly 0 or 1. The UI shows "< 0.001" or "> 0.999" rather than 0, 1 or a percentage.

**Acquisition:**
- At each feasible, unmeasured candidate (exact match to a measured x counts as measured),
  score = Σ w_m (μ_m − μ̄)², where μ̄ = Σ w_m μ_m. This is disagreement sampling, not
  optimal design or expected information gain.
- Pick the largest finite score. Scores within a relative 1e-9 are ties, and the smallest x wins.
- Candidates where any model's prediction is not finite are skipped with a diagnostic.
- Each model's share of the spread is reported, so a low-support model that causes most of the spread is visible.
- **Fallback, space-filling validation:** used if the largest support is ≥ 0.99, or the
  best weighted spread is ≤ 1e-6·max(1, max|ȳ|). The point chosen is the unmeasured
  candidate whose distance to the nearest measured x is largest (maximin in raw x;
  ties go to the smallest x). It is labelled as not chosen to distinguish models. The
  benchmark uses the same rule.
- **Separation:** ratio = weighted spread / representative setting-mean SD.
  - Below 2 → `:inconclusive`.
  - At or above 2 → `:separated`, which means "may help distinguish (heuristic)".
  - Noise unknown, or zero variability in the repeats → `:unassessed`.
- **Adequacy (heuristic):** standardized RMS of (ȳᵢ − fitᵢ)/(σ̂/√nᵢ) over settings,
  using in-sample residuals and dividing by G rather than G−2, which makes it conservative.
  - A model above 3 is flagged as conflicting with the measured variability.
  - If every supported model is flagged, the result says no candidate fits adequately. It never claims a law has been found.
- **No unmeasured candidate** gives `:no_candidates`: a clean completed state.

**Ensemble predicted mean:** `ensemble_predict(a, xs)` = Σ_m w_m (a_m f_m(x) + b_m) over
the supported models. The benchmark uses it for every policy. It is `nothing` when it is undefined or not finite.

**Prediction record:** `freeze_predictions(analysis)` returns an immutable
`PredictionRecord`. It is built only from scalars, strings, symbols and tuples, and holds:
- method version, UTC timestamp, and data revision (the SHA-256 of the sorted observed rows)
- observation and setting counts, and the selected x
- each model's formula, coefficients, support, grouped-validation RMSE and prediction
- the noise assumptions and the acquisition method

Refitting never changes it.

**Observed behaviour on the pendulum replay** (example script, not tuning):
- From the 3-length start, the square-root model holds more than 0.999 of the support, so
  the first two recommendations are space-filling validation points (16 m, then 8 m), not
  disagreement points.
- At 16 m the frozen square-root prediction (8.12 s) missed the revealed mean (7.79 s) by
  0.33 s, about 11 setting-mean SDs from the 3-length estimate.
- After that reveal, the pooled SD rose from 0.051 s to 0.105 s. Repeat scatter grows with
  length, so the constant-variance assumption is visibly approximate.
- Optional diagnostic only: the 9-length square-root fit has a = 1.934, which implies
  g = (2π/a)² ≈ 10.6 m/s², with b = 0.10 s. The simplified model and the reported
  averages need not match the ideal formula.

**Fixed bug (2026-10-24, via `/tdd`):** for finite features near 1e160, squaring the centred
values overflowed, so a well-conditioned linear fit was misreported as rank-deficient. It
is now prevented by dividing by max|f| first. The regression test is in `core_tests.jl`,
"numerical failure is reported, not hidden".

**Deferred:** bootstrap bands, Bayesian inference, symbolic regression and extra families.

## Uncertainty language
Keep three things distinct and labelled:
- measured variability between repeats
- uncertainty of a setting's mean
- disagreement between models

Do not show calibrated prediction intervals or standardized errors without a justified
implementation. When noise information is missing, say so.

## Benchmark
Build Prompt 05 is authoritative:
- four generating relationships
- two stated synthetic noise levels
- two starting layouts
- four policies (recommender, random, space-filling, and endpoint-first followed by maximin)
- equal observation budgets
- prediction error at unseen inputs

The protocol is committed to git before the first run. That the recommender beats the
baselines is a **hypothesis to test**. Whatever the result, it is reported.

**Result** (`docs/BENCHMARK.md`): at 8 settings, NextLab beat random in 11/16 conditions
and preplanned in 8/16. It showed no clear advantage over endpoint-first + maximin
(14/16 no clear difference). Position NextLab around the transparent workflow and
measured limits, not superior design.

## Six design criteria
None of these is satisfied yet; each needs evidence.
1. Effort removed
2. One central capability
3. Original combination
4. Useful, perceptible output
5. Bounded scope linked to a larger purpose
6. Technical choices that fit the problem

Missing evidence so far: a trainee trying the tool, and a prior-art check against existing
active-learning and experimental-design tools. The benchmark result is in, and it does not support
a design-superiority claim.

## Acceptance checks
- The recommender's output does not change when unrevealed y values are permuted.
- Coefficients match an independent reference fit on the same data.
- Reveal is disabled until predictions are frozen, and the record is append-only.
- A researcher's own two-column CSV runs the full loop. The downloaded record reproduces the session.
- Inconclusive, weak-fit and unchanged-or-worse results are shown honestly.
- A first-time viewer can explain the decision and its consequence within 90 seconds.
- Estimated g (from the square-root fit) is an optional diagnostic, not a pass condition.

## Stack
- **Backend:** Julia 1.13 package `NextLab` in `backend/`, using HTTP.jl 2.x, JSON.jl 1.x, CSV.jl and the standard libraries.
- **Frontend:** Vite + React + TypeScript in `frontend/`. Plotly's basic cartesian bundle is planned for plots.
- **Development:** Vite proxies `/api` to Julia on port 8080.
- **Demo:** one Julia process serves `frontend/dist` and `/api`.
