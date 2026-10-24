# 90-second live demo

The replay is deterministic, so the numbers below come back the same every time from the
starting state. They are the values the app produces (checked with
`backend/scripts/example_recommendation.jl` and the browser check). Only the snapshot ID
and timestamp change between runs.

## Before the judges arrive

1. Run `./nextlab` in a terminal and wait for `NextLab READY at http://127.0.0.1:8080`.
   It takes about 15 s.
2. Open http://127.0.0.1:8080 in a browser window about 1366×768 wide, then click
   **Reset demo**.
3. Check the screen.
   - The step bar shows step 2, **Recommend**, as current.
   - The right column reads "Known now: 3 lengths, 9 period observations".
   - **Recommend next measurement** is enabled.
4. Keep the Downloads folder (or the browser's download list) easy to open.

## Script

The narration is 181 words, which is roughly 72 s at 150 words per minute. That
leaves a few seconds for the clicks. Each click responds in about 0.02 s, measured in
headless Brave. The spoken timing is an estimate; time yourself once with a stopwatch.

**0 to 10 s.** The app is already on screen.

> "When trainees extend a measurement series, they should write down each model's
> prediction before measuring. Usually they don't. NextLab makes that step automatic."

**10 to 25 s.** Point at the plot, then the three cards.

> "These are recorded pendulum measurements from a public teaching dataset, credited at
> the top. We start with three lengths; six are hidden for replay. Three competing models.
> Square root validates best."

**25 to 45 s.** Click **Recommend next measurement**.

> "It recommends 16 metres, labelled a space-filling check, because one model already
> dominates. The predictions are now frozen. Linear says 33.5 seconds, square root 8.12,
> quadratic 965. Nothing is revealed yet."

**45 to 60 s.** Click **Reveal recorded measurement at 16 m**.

> "The recorded mean is 7.79 seconds. Square root is closest. But it still missed by
> about 11 times its own estimated uncertainty."

**60 to 75 s.** Click **Update models with the new observations**, then **Download record
(JSON + CSV)**.

> "Update is a separate click. Square root still leads, but its validation error went up.
> The frozen prediction stays in the history, and the record saves to two files."

**75 to 90 s.**

> "In simulation, with the protocol committed first, it beat random choice in 11 of 16
> conditions. It showed no clear advantage over a strong endpoints-then-gaps strategy. The
> value is the workflow. The main limit is that the noise model is too simple for this data."

What the screen shows at each step (checked against the live app on 2026-10-24):

| Step | On screen |
|---|---|
| Start | Step 2, "Recommend", is current. The panel reads "Known now: 3 lengths, 9 period observations" and "Hidden for replay: 6 recorded lengths (0.809, 1.485, 2.437, 4, 8, 16 m)". The cards read Linear 0.136 s, Square root 0.025 s, Restricted quadratic 0.471 s. |
| Recommend | "Next measurement: 16 m", with the label "Space-filling validation point: not chosen to tell the models apart" and "Why feasible". The frozen predictions are 33.5 s, 8.12 s and 965 s. The caption lists the two off-scale predictions. |
| Reveal | "7.68, 8.01, 7.68 s … Mean 7.79 s". The errors are −25.7, −0.329 and −957 s, and there is an orange note: "Even the closest frozen prediction (Square root) missed by 11.2 SDs of a mean." |
| Update | "Leading model unchanged: Square root". "Its validation error rose (0.025 s → 0.166 s)", and all three models are marked "↑ worse". The prediction history shows row 1. |
| Download | Two files: `nextlab-record-<id>.json` and `nextlab-observations-<id>.csv`. |
| Benchmark | Below the history: "Benchmark evidence (simulation, not pendulum data)", with the table at 11/5/0, 8/7/1 and 2/14/0. |

## If something goes wrong

- **Wrong state.** Click **Reset demo**. It always returns to the 3-length start.
- **The page shows "Backend unavailable".** The server stopped. In the terminal run
  `lsof -tiTCP:8080 -sTCP:LISTEN | xargs kill`, then `./nextlab` again, wait for READY
  (about 16 s after a crash), and reload the page.
- **Out of time after the reveal.** Skip the download, and finish with the benchmark
  sentence from 75 to 90 s.

## Things not to say

- Don't say the square-root model "wins" or that NextLab "proves" the pendulum law. The
  physics is known. The demo shows the workflow, and the model still missed by more than
  its noise estimate.
- Don't say NextLab saves a percentage of experiments. The benchmark measured prediction
  error at a fixed budget, in simulation.
- Don't say trainees use it. It has not been tested with users yet.
