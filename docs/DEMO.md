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

**0 to 10 s.** The app is already on screen.

> "When a trainee extends a series of measurements, they refit a few models, pick the next
> setting, and should write down what each model predicts before measuring. That last step
> is the one people skip. NextLab does those steps without any analysis code."

**10 to 25 s.** Show the observed data and the competing models. Point at the plot and the
three model cards.

> "These are recorded pendulum measurements from a public teaching dataset. They are not my
> data, and the source is credited at the top. We start from the three shortest lengths:
> 9 period observations. The other six lengths are hidden for replay. The three cards are
> the competing models. The square-root model has the lowest leave-one-out validation
> error, 0.025 seconds."

The cards read: Linear 0.136 s, support < 0.001; Square root 0.025 s, support > 0.999;
Restricted quadratic 0.471 s, support < 0.001.

**25 to 45 s.** Click **Recommend next measurement**. Read the right-hand panel and the
markers on the plot.

> "NextLab recommends 16 metres. That length is in the recorded set and hasn't been
> revealed yet. It's labelled a space-filling validation point. One model already holds
> nearly all the support, so this point checks it where the data are sparse. It isn't
> chosen to tell the models apart. The predictions are now frozen: linear says 33.5
> seconds, square root 8.12 seconds, the restricted quadratic 965 seconds. Nothing has
> been revealed yet."

The caption under the plot lists the two predictions that are off the scale.

**45 to 60 s.** Click **Reveal recorded measurement at 16 m**.

> "The recorded periods are 7.68, 8.01 and 7.68 seconds, a mean of 7.79. Compared with
> the frozen predictions, square root is closest, off by 0.33 seconds. But that's about
> 11 times its own estimated uncertainty of a mean. So even the best model misses by more
> than the noise model expects."

An orange note in the panel says that even the closest prediction missed by 11.2 SDs of
a mean.

**60 to 75 s.** Click **Update models with the new observations**. Then click **Download
record (JSON + CSV)**, and point at the prediction history and the two downloaded files.

> "Update is a separate click; nothing refits on its own. Square root still leads, but its
> validation error rose from 0.025 to 0.166 seconds once 16 metres was included. The other
> two models got much worse. The earlier prediction stays in the history. The record
> stores the frozen predictions, the recorded values, and the order of the updates."

The panel reads "What changed after adding 16 m", and each model's error change is marked
"↑ worse". The download produces `nextlab-record-<id>.json` and `nextlab-observations-<id>.csv`.

**75 to 90 s.**

> "I benchmarked the choice rule in simulation, with the protocol committed before
> running. At 24 observations, it beat random choice in 11 of 16 conditions. Against a
> strong strategy that measures the endpoints and then the largest gaps, there was no
> clear difference in 14 of 16. So the value is the workflow, not a better design. And
> the main limit: on this real data the noise model is too simple, as the 11-SD miss
> showed."

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
