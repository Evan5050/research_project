# NextLab acceptance audit (2026-10-24)

This audit used the code, the running app (headless Brave driving the real Julia server),
and the saved result files. Passing software checks does not show that researchers would
adopt the tool.

**Commands run:**
- `Pkg.test()`: 382/382 pass (after the /tdd fix below)
- `npx tsc -b`: exit 0
- `npm run lint`: 0 warnings
- `npm run build`: passes
- `api_smoke.jl`: passes
- `frontend/scripts/browser-check.mjs`: 64/64 pass
- `scan_hidden.jl`: app chunk and source clean
- `/tmp` audit scripts: benchmark result files, and hidden-data tampering on the live API path

## Consequential-failure audit
| # | Failure looked for | Evidence actually observed | Status |
|---|---|---|---|
| 1 | Frontend shows values not from Julia | The source has no data literals; the frontend only does display arithmetic. The browser check confirms the shown frozen predictions and selected x equal the raw `/api/recommend` response. | Pass. Note: the "0.99" wording and a ">3 SDs" warning repeat thresholds in JS. |
| 2 | Unrevealed outcomes influence the analysis | Every unrevealed period was rewritten in-process to about 1000 s. Analysis, snapshot and candidate scores stayed identical; reveal then returned the tampered values for the selected length only (positive control). The core and API leak tests pass. | Pass |
| 3 | Prediction computed after reveal or overwritten on update | The reveal comparison uses exactly the frozen values. Update adds a history row without changing the snapshot. | Pass |
| 4 | Result attached to the wrong revision | Late responses after a reset and after a dataset switch are ignored (browser). A stale snapshot gets 409. | Pass after fix: **Apply settings was enabled during an in-flight request**; now disabled (browser check failed before, passes after). |
| 5 | A second click duplicates or advances twice | Same-tick double clicks on Recommend, Reveal, Update and Record measurement each send exactly one request and add one history row. | Pass |
| 6 | Repeats leak across folds, or budgets are inconsistent | The grouped-validation sibling-replicate test passes. `runs.csv`: observations = 3 × settings in all 38,400 rows, and each run covers budgets 3–8 once. | Pass |
| 7 | Benchmark predictor, overlap, dropped losses or stale results | Starting RMSE is identical across policies in all 1,600 condition-seed pairs. Test and candidate gap is 0.0025 (test). All 64 condition × policy groups have 600 rows, with 0 missing. Recomputing the 288 paired rows from `runs.csv` matches, including 7,059 losses. The predictor and selection code are unchanged since the benchmark commit `d1d7481`, so no rerun was needed. | Pass. Added a guard: the API and UI flag results from a different method version. |
| 8 | Training error shown as unseen; weights as probabilities; spread as confidence | Cards show grouped validation error only. Support is labelled "heuristic, not a probability" and shown as "> 0.999" or "< 0.001". Spread is "support-weighted … not a confidence interval"; no band is drawn. | Pass after fix: **zero-variability repeats were described as "noise unknown"**; now the backend's reason is shown. Pendulum-specific wording in upload mode was also generalized. |
| 9 | Invalid input crashes or gives plausible nonsense | NaN, Inf, `1e999`, `-Infinity`, x ≤ 0 and malformed rows all give row-numbered 422s. Zero-width ranges and empty lists give field errors. Degenerate x returns `no_valid_fit` with reasons. No page errors in the browser. | Pass after fix: **a dead "Recommend" button was offered when no model could be fitted**; now no action is offered. |
| 10 | Exported history differs from the pre-reveal state | The exported `frozen_predictions` are byte-equal (as JSON) to the snapshot returned before the reveal, with the same `snapshot_id`. | Pass |
| — | **Snapshot round trip with negative zero** | Constant-response uploads fit `a = -0.0`. The browser serializes `-0` as `0`, the content hash changes, and the unaltered snapshot is **rejected** on observe ("snapshot was altered"). The same could affect a demo snapshot containing `-0.0`; none was observed. | **Fixed via /tdd.** Signed zero is now canonical when hashing snapshots and contexts. Failing before: 3 API failures and 3 browser failures. Passing after: all pass, including a constant-response recommend → record → update → export after a real browser round trip. |

## Requirements
| Requirement | Evidence | Status / limitation |
|---|---|---|
| Built-in demo: compare → recommend (freeze) → reveal selected length → compare with frozen → explicit update → repeat, reset | Browser: the full replay to "Replay complete", reset, and recommending again after reset | Met. All 6 demo choices are space-filling fallbacks; disagreement sampling never decides on this data. |
| Hidden outcomes kept out of inputs and payloads | Tests, the tampering check, payload and bundle scans | Met |
| Two-column CSV: preview, choose columns, labels and units, repeats kept, row errors | API and browser tests: sample, BOM/CRLF/quoted file, malformed value, invalid bounds | Met |
| Feasible settings: range + step and/or list, deduplicated, capped, extrapolation marked | API and browser tests | Met |
| Noise: repeats, stated SD, or explicitly unknown (or zero variability) | API tests, browser | Met (after fix #8) |
| Manual measurement and explicit update | Browser (example: 6 mg → 5.1, 5.3 → update) | Met, including constant-response data (after the /tdd fix) |
| Export: JSON record + observations CSV with provenance, run type, formulas, method version, frozen cycles, origins | Real downloaded files inspected; tests | Met |
| Benchmark declared before running, all runs saved, paired analysis | Commit order `dac3e46` → run; result-file audit | Met. No design advantage over endpoint+maximin. |
| Local-only, no accounts or database; no strong privacy claim | Code review: binds to 127.0.0.1, no storage | Met; privacy not reviewed |

## Six design criteria
| Criterion | Evidence | Status |
|---|---|---|
| Effort removed | The workflow runs without code: fit, compare, choose, freeze, check, refit, export. No time-on-task measurement. | Demonstrated in software; **unvalidated with users** |
| One central capability | The frozen-prediction measurement decision is the backbone of both modes | Met |
| Original combination | No prior-art check against active-learning and experimental-design tools | **Unvalidated** |
| Useful, perceptible output | Plot, frozen predictions, errors, history, record. The benchmark shows no accuracy gain over a strong space-filling design. | Perceptible: yes. **Usefulness unvalidated** (no trainee has tried it). |
| Bounded scope linked to a larger purpose | One input, three families, local, explicit limits | Met |
| Technical choices fit | Julia core cross-checked against R `lm`, deterministic benchmark, typed API. No speed advantage measured or claimed. | Met |
