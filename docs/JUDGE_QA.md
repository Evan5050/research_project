# Likely judge questions

**Why use a pendulum when its physics is known?**

Because the answer can be checked. The demo shows the workflow, not a discovery. Known
physics lets a viewer judge whether the app's comparisons are sensible. And even here the
square-root model, the one closest to the textbook relationship, missed the 16 m result
by about 11 times its estimated uncertainty of a mean. The constant-noise assumption is too
simple for these recorded averages.

**Who would use this?**

The intended user is a research trainee who reads plots but does not write analysis code,
and who extends one-input measurement series. I have not tested it with trainees or
researchers yet, so this is the intended user, not a validated one.

**How is it different from a curve-fit plot?**

A curve-fit plot shows fits to the data you already have. NextLab adds four things:
- It recommends a feasible next setting and says why.
- It freezes each model's prediction before the result is known.
- It compares the result with those frozen values.
- It saves a record of every recommendation, observation and update.

Its error figures come from settings left out of the fit, not from the in-sample fit.

**Why Julia?**

The numerical core, the benchmark and the server are in one language, so the benchmark
scores exactly the predictor the app uses. The standard library provides QR and SHA. The
fits match R's `lm()` to 1e-10. I have not compared speed with any other implementation,
so I make no speed claim.

Measured times on my laptop:
- First pass, including compilation: about 11 s at startup.
- A warmed-up recommendation request: about 1.2 ms.

**Where did the data come from?**

The `Pendulum` dataset in the R package fastR2. Its documentation credits Calvin College
physics students under Professor Steve Plath. The package declares GPL (>= 2).
- Each period is a reported average over several swings.
- I verified the source file's hash and that its values match the snapshot.
- I did not collect the data.

**Is the algorithm novel?**

No. Least squares, leave-one-group-out validation, weighting models by validation error,
disagreement sampling and maximin space filling are all established. What I built is the
combination, with a workflow that freezes predictions and records them. I have not done a
prior-art review against existing experimental-design tools.

**Does it always beat simple measurement choices?**

No. These are simulated results at 24 observations, over 16 conditions:
- Better than random choice in 11, never clearly worse.
- Better than a preplanned evenly spaced design in 8, worse in 1.
- Against measuring the endpoints and then the largest gaps: no clear difference in 14,
  and the 2 favourable results are about what chance would give.

At smaller budgets it was sometimes clearly worse. A lower error at a fixed budget also
does not show that fewer experiments are needed.

**What happens if the right model is absent?**

The benchmark included one relationship outside all three models: 1.5(1 − e^(−3x)) + 0.2.
- NextLab still picks the best-validating model, and keeps choosing settings near the edges
  of the range, where the wrong models diverge. That made it worse than the strong baseline
  at intermediate budgets in some conditions.
- The "no model fits adequately" warning, a heuristic, flagged 99 of 100 low-noise runs of
  that relationship. With higher noise it flagged only 3 of 100.

It does not invent a new model.

**What does the uncertainty display mean?**

There are three separate quantities:
- The SD of individual observations, estimated from repeats.
- The uncertainty of a setting's mean, that SD divided by √n.
- The support-weighted spread of the models' predictions, which measures disagreement
  between models.

None of these is a calibrated confidence interval, and the app draws no band. Relative
support is a heuristic weight, not the probability that a model is true. When noise
cannot be estimated, the app says "unknown".

**What was built during the event?**

All of the code, the tests, the benchmark and its results, and the documents. All were
written on 2026-10-24, starting from an empty repository whose first commit is at 14:10.

The pre-existing parts:
- The Julia packages: HTTP.jl, JSON.jl, CSV.jl and the standard libraries.
- The npm packages: React, Vite, TypeScript, Plotly basic and oxlint.
- The fastR2 dataset.
- R, used once to make a reference fit for a test.

I used Claude Code (Claude Opus 5.5) as an AI coding assistant. The details are in
`docs/DEVPOST.md`.

**What would you validate next with an experimental researcher?**

- Whether freezing predictions changes what they write down and how they choose settings,
  on a real series they are extending.
- Whether the recommended settings are physically feasible and worth the cost of measuring.
- Whether the space-filling and low-separation labels are understandable without
  explanation.
- How the frozen predictions compare with what they would have expected themselves.
