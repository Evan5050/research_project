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

### Run record
- **Full declared run:** 100 seeds × 16 conditions × 4 policies × 6 budgets = 38,400 rows.
  - Code at commit `d1d7481`, with no changes outside `results/`. Method `nextlab-core-1`, Julia 1.13.2, 11 threads, 7.3 s.
  - Protocol committed first, in `dac3e46`, before any run. `docs/BENCHMARK.md` above this
    section is unchanged since then (protocol SHA-256 `c0c6a16c…` in `meta.json`).
  - The only code change between the two commits is the metadata dirtiness flag (`d1d7481`).
- **Smoke run:** 5 seeds, used only for the crash and runtime check.
- **Files:** `results/benchmark_full/` holds `runs.csv` (every run × budget), `summary.csv`,
  `paired.csv`, `nextlab_choices.csv` and `meta.json`.
- **Reproducibility:** rerunning with 4 threads gave byte-identical CSVs.
- **Derived preplanned sequences:** L1 gives 0.3, 0.5, 0.6, 0.9, 1.1, and L2 gives 0.3, 0.5, 0.65, 0.9, 1.1.
- **Failures:** 0 predictor failures and 0 NextLab step failures in 38,400 rows.

### Primary endpoint: 8 settings, 24 observations per run
- **Target:** RMSE of the ensemble mean against the noiseless relationship at 200 held-out test inputs.
- **Δ** = mean paired difference, NextLab − baseline. Negative means NextLab has lower error.
- **The interval** is a 95% percentile bootstrap over the 100 seeds for that mean
  difference under these simulation assumptions. It is not a predictive band.
- **W/T/L** = NextLab wins/ties/losses; a tie is |d| ≤ 1e-10.
- **Labels:** "better" or "worse" follows the declared claim rule.

| C | Truth | σ | Start | Mean RMSE: NextLab / Random / Preplanned / Endpoint+maximin | vs Random: Δ [95% CI] W/T/L | vs Preplanned | vs Endpoint+maximin | NextLab steps: disagreement / fallback |
|---|---|---|---|---|---|---|---|---|
| 1 | sqrt | 0.03 | L1 cluster | 0.0072 / 0.0138 / 0.0091 / 0.00719 | -0.00656 [-0.0094, -0.00429] 77/0/23 **better** | -0.0019 [-0.00292, -0.000924] 62/0/38 **better** | 5.62e-6 [-0.000129, 0.000125] 2/95/3 | 168 / 332 |
| 2 | sqrt | 0.03 | L2 ends+mid | 0.00759 / 0.00704 / 0.00676 / 0.00761 | 0.00055 [-0.000392, 0.00149] 46/0/54 | 0.000821 [-0.000127, 0.00177] 48/0/52 | -2.5e-5 [-0.000284, 0.000239] 5/88/7 | 24 / 476 |
| 3 | sqrt | 0.1 | L1 cluster | 0.0301 / 0.046 / 0.0365 / 0.028 | -0.0159 [-0.0202, -0.0117] 75/0/25 **better** | -0.00637 [-0.00944, -0.00322] 62/0/38 **better** | 0.0021 [-0.000206, 0.00439] 37/0/63 | 463 / 37 |
| 4 | sqrt | 0.1 | L2 ends+mid | 0.0281 / 0.0313 / 0.0285 / 0.0296 | -0.00321 [-0.00598, -0.000704] 54/0/46 **better** | -0.000416 [-0.0032, 0.00231] 51/0/49 | -0.00149 [-0.00415, 0.00102] 56/0/44 | 408 / 92 |
| 5 | linear | 0.03 | L1 cluster | 0.00727 / 0.0118 / 0.00811 / 0.0073 | -0.00453 [-0.00686, -0.00266] 69/0/31 **better** | -0.000841 [-0.00188, 0.00021] 61/0/39 | -3.33e-5 [-0.000146, 5.23e-5] 2/97/1 | 166 / 334 |
| 6 | linear | 0.03 | L2 ends+mid | 0.0073 / 0.00805 / 0.00689 / 0.0077 | -0.000753 [-0.00169, 0.000187] 54/0/46 | 0.000413 [-0.000462, 0.00128] 49/0/51 | -0.000402 [-0.000866, -1.53e-5] 9/88/3 **better** | 28 / 472 |
| 7 | linear | 0.1 | L1 cluster | 0.0284 / 0.0343 / 0.0326 / 0.0296 | -0.00595 [-0.00965, -0.00232] 65/0/35 **better** | -0.00418 [-0.00745, -0.000771] 63/0/37 **better** | -0.00125 [-0.00348, 0.000922] 50/0/50 | 424 / 76 |
| 8 | linear | 0.1 | L2 ends+mid | 0.0276 / 0.0273 / 0.0272 / 0.0297 | 0.0003 [-0.00256, 0.00298] 48/0/52 | 0.000443 [-0.00234, 0.00311] 49/0/51 | -0.00204 [-0.00494, 0.000719] 58/0/42 | 357 / 143 |
| 9 | quadratic | 0.03 | L1 cluster | 0.00739 / 0.00948 / 0.00782 / 0.00739 | -0.0021 [-0.00392, -0.000511] 57/0/43 **better** | -0.000437 [-0.00141, 0.000593] 55/0/45 | 0.0 [0.0, 0.0] 0/100/0 | 126 / 374 |
| 10 | quadratic | 0.03 | L2 ends+mid | 0.00773 / 0.00763 / 0.0068 / 0.00773 | 9.61e-5 [-0.000859, 0.00101] 51/0/49 | 0.000929 [3.05e-5, 0.00182] 47/0/53 **worse** | 0.0 [0.0, 0.0] 0/100/0 | 0 / 500 |
| 11 | quadratic | 0.1 | L1 cluster | 0.0251 / 0.0491 / 0.0324 / 0.0263 | -0.024 [-0.0315, -0.0171] 73/0/27 **better** | -0.00726 [-0.0109, -0.00353] 64/0/36 **better** | -0.00119 [-0.0023, -0.000189] 16/75/9 **better** | 233 / 267 |
| 12 | quadratic | 0.1 | L2 ends+mid | 0.0259 / 0.0284 / 0.0259 / 0.0274 | -0.00247 [-0.00585, 0.00129] 55/0/45 | 7.01e-5 [-0.00296, 0.00322] 51/0/49 | -0.00143 [-0.00336, 0.000305] 29/56/15 | 103 / 397 |
| 13 | saturating | 0.03 | L1 cluster | 0.0675 / 0.0871 / 0.0744 / 0.0679 | -0.0196 [-0.0237, -0.0159] 92/0/8 **better** | -0.00686 [-0.00757, -0.0062] 99/0/1 **better** | -0.000373 [-0.000885, 0.000136] 59/0/41 | 497 / 3 |
| 14 | saturating | 0.03 | L2 ends+mid | 0.0675 / 0.0742 / 0.0729 / 0.068 | -0.0067 [-0.00812, -0.00522] 84/0/16 **better** | -0.00538 [-0.00614, -0.00465] 92/0/8 **better** | -0.000482 [-0.00103, 5.46e-5] 56/0/44 | 500 / 0 |
| 15 | saturating | 0.1 | L1 cluster | 0.0744 / 0.0953 / 0.0819 / 0.074 | -0.0209 [-0.0264, -0.0158] 79/0/21 **better** | -0.00749 [-0.00967, -0.00526] 78/0/22 **better** | 0.000392 [-0.0012, 0.00213] 57/0/43 | 500 / 0 |
| 16 | saturating | 0.1 | L2 ends+mid | 0.0746 / 0.083 / 0.0782 / 0.0749 | -0.00831 [-0.0112, -0.00532] 74/0/26 **better** | -0.00359 [-0.00595, -0.00128] 63/0/37 **better** | -0.000279 [-0.00197, 0.0015] 54/0/46 | 499 / 1 |

**Verdict counts at the primary endpoint** (16 conditions each):
| Baseline | NextLab better | No clear difference | NextLab worse |
|---|---|---|---|
| Random | 11: all 8 L1 cluster starts, plus L2 in C4, C14, C16 | 5: C2, C6, C8, C10, C12 (all L2) | 0 |
| Preplanned evenly spaced | 8: C1, C3, C7, C11, C13, C15 (L1); C14, C16 (L2) | 7 | 1: C10 (interval 3.05e-5 to 0.00182) |
| Endpoint-first + maximin | 2: C6, C11 | 14 | 0 |

There are 48 primary comparisons, each with its own 95% interval. If there were no true
differences, about 2–3 intervals would be expected to exclude zero by chance. So the two
"better" results against endpoint+maximin, and the single "worse" result against the
preplanned design, are not distinguishable from chance on this evidence. No multiplicity
correction was declared, so this is interpretation, not a protocol rule. Against
endpoint+maximin, the relative mean differences at 8 settings range from −6.9% to +7.5%.
They are computed per condition and never pooled.

### Secondary budgets: 4–7 settings
Verdict counts per budget, given as better / no clear / worse:
| Settings (observations) | vs Random | vs Preplanned | vs Endpoint+maximin |
|---|---|---|---|
| 4 (12) | 6 / 6 / 4 | 4 / 8 / 4 | 3 / 12 / 1 |
| 5 (15) | 13 / 3 / 0 | 8 / 7 / 1 | 3 / 13 / 0 |
| 6 (18) | 13 / 3 / 0 | 8 / 6 / 2 | 3 / 11 / 2 |
| 7 (21) | 12 / 4 / 0 | 8 / 8 / 0 | 4 / 12 / 0 |
| 8 (24) | 11 / 5 / 0 | 8 / 7 / 1 | 2 / 14 / 0 |

Clear losses at intermediate budgets, kept as found:
- **At 4 settings from the cluster start:** NextLab was worse than random and than preplanned
  in C3, C7, C13 and C15. For example, in C13 it lost to random in 89/100 seeds and to
  preplanned in 98/100. From the cluster start, NextLab's first extra setting was 0.2 in
  94–100% of seeds, the same first choice endpoint+maximin makes. That leaves 1.2 as
  extrapolation, and there was no clear difference against endpoint+maximin at this budget
  in these four conditions.
- **When the truth is outside the families (T4):**
  - worse than endpoint+maximin at 6 settings in C13 (100/100 losses) and C15 (85/100)
  - worse than preplanned at 5–6 settings in C14 and C16
  - worse than endpoint+maximin at 4 settings in C14

  In C13, NextLab's three extra settings were 0.2, 1.2 and then 0.25 in all 100 seeds. The
  third pick sits next to an end, where the misspecified fits diverge, instead of filling
  the gap as maximin does.

  These are properties of the declared rule, not implementation defects. No defect was
  found, so the method was not changed.

### Counts of choice types, poor fits and failures
- **NextLab step types:** 4,496 of 8,000 steps used disagreement and 3,504 used the
  maximin fallback because one model had at least 0.99 support. The "predictions agree"
  fallback never fired, and there were 0 failures.
  - The fallback dominates when noise is low and the true family is a candidate, for
    example 476/500 steps in C2 and 500/500 in C10.
  - Under T4, nearly every step was disagreement.
- **Poor-fit flag** (the heuristic says every model is inadequate), for the NextLab policy at 8 settings:
  - 0 of 1,200 runs when the truth is one of the families (T1–T3). The same was true for every policy.
  - Under T4, which is outside the families: 99/100 runs in both C13 and C14 at σ = 0.03,
    but only 3/100 in C15 and C16 at σ = 0.10. At σ = 0.03 the random and preplanned
    policies were flagged less often from the cluster start (37 and 41 of 100).
- **Ties against endpoint+maximin:** many runs tie exactly (for example 100/100 in C9 and
  C10), because NextLab's fallback and that baseline choose the same settings.

### Interpretation
- **Against random:** at 8 settings NextLab had lower error than random in every clustered
  start and in 3 of 8 ends-and-middle starts. It was never clearly worse.
- **Against the preplanned evenly spaced design:** better in 8 conditions, no clear difference in 7, worse in 1.
- **Against endpoint-first + maximin, the stronger baseline:** NextLab did not show an
  advantage. There was no clear difference in 14 of 16 conditions, and the 2 favourable
  intervals are consistent with chance across 48 comparisons. Most of NextLab's advantage
  over the naive strategies is therefore explained by measuring at distant settings, which
  endpoint+maximin also does.
- **At intermediate budgets** NextLab was sometimes clearly worse, especially when the true
  relationship was outside the candidate families.

**Strongest claim these results support:**
- In this simulation (four relationships, two assumed Gaussian noise levels, 21 candidate
  settings, 3 observations per setting), NextLab's rule produced final ensemble predictions
  about as accurate as a strong endpoint-first + maximin design, and more accurate than
  uniform random choice in 11 of 16 conditions.
- It did not show a predictive advantage over the strong space-filling baseline.
- NextLab's demonstrated value is therefore the transparent workflow: pre-committed
  predictions, explicit refits, labelled support, separation and adequacy diagnostics
  (which flagged misspecification in 99% of low-noise T4 runs). That workflow comes with
  measured limits, not superior experimental design.

**Limits of this evidence:**
- simulated data only, with Gaussian, independent, constant-variance noise
- one input range and one candidate grid
- maximin in raw x
- no multiplicity correction
- absolute RMSE differences are small (mostly below 0.01 response units)
- nothing here transfers automatically to the pendulum data or any real apparatus
