# NextLab benchmark

## Protocol (declared before any benchmark run; do not edit after results exist)

**Question:** with the same observation budget, does NextLab's next-setting rule produce
better predictions at unseen inputs than simple measurement strategies? A baseline may
win, and the answer may depend on the condition. Either outcome is reported.

**Method under test:**
- `nextlab-core-1`, as specified in `docs/SPEC.md` ("Numerical method").
- The git commit and Julia version are recorded in each run's `meta.json`.
- The disagreement rule, its maximin fallback and all thresholds are used unchanged.

**Design (all choices fixed here):**
- **Candidate settings:** 21 evenly spaced x values from 0.2 to 1.2 (step 0.05). Every policy has the same feasible set.
- **Test inputs:** 200 midpoints, x = 0.2 + (i − 0.5)·0.005 for i = 1…200. A check confirms that none coincides with a candidate (minimum gap 0.0025). Only the evaluator computes true responses at these inputs.
- **Generating relationships**, in response units:
  - T1: 2√x
  - T2: 1.6x + 0.5
  - T3: 1.4x² + 0.6
  - T4: 1.5(1 − e^(−3x)) + 0.2. This one is deliberately outside all three candidate families.
- **Observation noise:** independent zero-mean Gaussian with SD 0.03 or 0.10. These are
  simulation assumptions, not measured properties of the public pendulum dataset.
- **Starting layouts:**
  - L1, middle cluster: the three adjacent candidates nearest the middle (0.65, 0.70, 0.75).
  - L2, ends and middle: 0.2, 0.7 and 1.2.
- **Budget:**
  - Each measured setting gives 3 noisy observations.
  - Runs start with 3 settings (9 observations) and add one setting at a time until 8 settings (24 observations).
  - No setting is measured twice.
  - Results report both settings and raw observations.
- **Conditions:** 4 relationships × 2 noise SDs × 2 layouts = 16 conditions.
  - Each condition is indexed in that order, with the relationship varying slowest.
  - 100 fixed seeds per condition (seeds 1…100), chosen before any run and not changed for the result.
  - A 5-seed smoke run comes first. It checks only crashes and runtime, and its results are not used for any decision.
  - If runtime forced fewer seeds, at least 30 would be used and labelled. Declared: 100.

**Randomness and fairness:**
- **Shared observation table:** for each seed, a 21 × 3 table of standard-normal draws ε
  is generated once, with `Random.Xoshiro(seed)`. The observation at candidate j,
  replicate r, is y = T(x_j) + σ·ε[j, r]. All policies in a condition read the same
  table (paired comparison). Each policy receives only the rows for settings it requests.
- **Random policy:** draws from its own stream,
  `Random.Xoshiro(10_000_000 + 1_000·condition + seed)`. No other policy draws random
  numbers, so the noise does not depend on how many random calls any policy makes.
- **What a policy sees:** observed (x, y) for its requested settings, the remaining
  candidate x values and the starting settings. It never sees unrequested rows, T, or test-input responses.

**Policies** (only the next-setting choice differs):
1. **NextLab:** `analyze(observed x, observed y, all 21 candidates)`, then the
   recommended x, which may be disagreement or the maximin fallback. If no recommendation
   is returned, the step uses maximin and is counted as a NextLab failure.
2. **Random:** uniform over the remaining candidates.
3. **Preplanned evenly spaced:**
   - The targets are the 5 bin midpoints 0.3, 0.5, 0.7, 0.9 and 1.1, taken in ascending order.
   - Each target snaps to the nearest candidate not yet measured or planned; ties go to the smaller x.
   - The plan is computed from the layout alone, with no responses.
4. **Endpoint-first, then maximin:** take 0.2 if unmeasured, then 1.2 if unmeasured.
   After that, take the candidate with the largest distance to the nearest measured
   setting (ties go to the smallest x), using the same `maximin_choice` as NextLab's fallback.

**Predictor and target (the same for every policy):**
- At every budget, `analyze` runs on the policy's observed data and the ensemble
  predicted mean is calculated: Σ_m w_m · (a_m f_m(x) + b_m) over the supported models.
- **Target:** the RMSE of that ensemble mean against the **noiseless** generating
  relationship at the 200 test inputs. This is not error on noisy future observations.
- If the predictor is undefined or not finite, the run is recorded as a failure and stays in the counts.

**Analysis (declared):**
- **Primary endpoint:** RMSE at 8 settings (24 observations). Budgets 4–7 are secondary.
- **Paired difference:** d = RMSE(NextLab) − RMSE(baseline) for each seed. Negative means NextLab is better.
- **Win/tie/loss:** a tie is |d| ≤ 1e-10 response units.
- **Per condition and budget, report:**
  - mean, median, SD and the 10th/90th percentiles of RMSE per policy
  - mean and median paired difference
  - a 95% percentile bootstrap interval for the mean paired difference (2,000 resamples of seeds, `Xoshiro(20261024)`)
  - win/tie/loss counts
  - a relative mean difference, only when the mean baseline RMSE is at least 1e-6
- **What the interval estimates:** uncertainty in the average paired difference across
  seeds under these simulation assumptions. It is not a predictive confidence band of any model.
- **Claim rule:**
  - "NextLab better than B in condition C" requires the primary-endpoint interval to lie entirely below 0.
  - "Worse" requires it to lie entirely above 0.
  - Otherwise: "no clear difference".
  - No percentage is pooled across conditions.
- **Counts reported:**
  - NextLab disagreement vs fallback steps
  - runs where the heuristic flags every model as inadequate (poor fit)
  - failures, ties and losses
- **Saved outputs:**
  - `results/benchmark_<tag>/runs.csv`: every run × budget
  - `summary.csv`, `paired.csv` and `meta.json`

**Verification before trusting results** (backend tests):
- equal costs
- disjoint test inputs
- identical output for fixed seeds
- isolated truth access: changing unrequested table rows leaves the choices unchanged, and the noise does not depend on policy random calls
- one shared predictor: identical observation sets give identical RMSE whichever policy produced them

## Results

_Not yet run._
