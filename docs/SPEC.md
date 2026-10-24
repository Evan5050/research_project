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

## Numerical method
Build Prompt 04 is authoritative:
- Fit the mean at each distinct x, giving every distinct x equal weight.
- Validate by leaving out one distinct setting at a time.
- Show transparent heuristic support weights.
- Recommend by weighted prediction disagreement, with the documented maximin fallback.
- Do not use AICc or row-wise leave-one-out validation.

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

## Six design criteria
None of these is satisfied yet; each needs evidence.
1. Effort removed
2. One central capability
3. Original combination
4. Useful, perceptible output
5. Bounded scope linked to a larger purpose
6. Technical choices that fit the problem

Missing evidence so far: a trainee trying the tool, a prior-art check against existing
active-learning and experimental-design tools, and the benchmark result.

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
