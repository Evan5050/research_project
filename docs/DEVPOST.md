# NextLab: Devpost draft

This is a draft for review. Nothing here has been submitted. Fields I could not fill from
the project files are listed at the end.

## Tagline

Pick the next measurement, commit each model's prediction before the result arrives, and
see what the data changed, without writing analysis code.

## Short description

NextLab is a local web app for one-input experiments.
- It fits three two-parameter models to your observations.
- It recommends one feasible setting to measure next.
- It freezes every model's prediction there.
- After the result arrives, it compares the result with those frozen predictions, and
  refits only when you ask.

The demo replays recorded pendulum measurements from a public teaching dataset. You can
also upload your own two-column CSV and enter new measurements by hand. A simulation
benchmark tests whether its choices beat simple measurement strategies. It beats random
choice in most conditions; against a strong space-filling strategy there was no clear
difference.

## Inspiration

Extending a series of measurements involves the same steps each time:
- fit a few candidate relationships
- decide where to measure next
- note what each one predicts
- measure
- check
- refit

A trainee who reads plots but does not write analysis code tends to do these steps by eye.
The step that most often gets skipped is writing down the predictions before the result
arrives. I wanted a tool that makes that step automatic and keeps a record of it.

## What it does

- Fits y = a·x + b, y = a·√x + b and y = a·x² + b, and ranks them by leave-one-setting-out
  validation error.
- Recommends the next setting. Usually this is where the models disagree most, weighted by
  how well each model validates. When one model already has nearly all the support, it
  recommends a space-filling check instead, and labels it as such.
- Freezes each model's prediction under a content-hash ID, before anything is revealed or
  measured.
- Compares the new result with those frozen predictions. It never recomputes them after
  the result is known.
- Refits only when you click Update, then shows which model leads and whether validation
  error went up or down.
- Exports a JSON record and a CSV of observations. The record contains the data source,
  the method version, each frozen recommendation, the later observations, and the order of
  updates.
- States where its noise estimate comes from. It estimates noise from repeats, uses an SD you state, or marks
  it as unknown. It also flags low separation and a poor fit as heuristics.

The demo uses the fastR2 `Pendulum` dataset, credited to Calvin College physics students
under Professor Steve Plath. The recommendation code never sees the hidden recorded periods.

## How I built it

I worked alone. All of the code was written on 2026-10-24, starting from an empty
repository. The first commit, `a7123af` at 14:10, contains only a README.

The scientific core is a Julia package. It does the QR least-squares fits, the
leave-one-setting-out validation, the support weights, the next-setting choice and the
frozen records. A stateless JSON API, built on HTTP.jl, sits on top. The browser holds the
experiment state, and every request carries a revision, so a response from before a reset
or a data change is ignored.

The front end is React and TypeScript, built with Vite, and plots with Plotly's basic
bundle. One command, `./nextlab`, builds the page, starts the server and warms up the code
paths before reporting ready.

I committed the benchmark protocol before running it.
- 16 simulated conditions with 100 seeds each.
- Four measurement policies that share one predictor.
- Errors are measured against the noiseless relationship at inputs that are never
  candidates.

**AI assistance.** I used Claude Code (model: Claude Opus 5.5) as a coding assistant
throughout. I wrote the project brief and the stage-by-stage build instructions, set the
scope, the benchmark design and the evidence rules, ran the bug-fix sessions and reviewed
and committed each stage. Claude Code wrote most of the code, tests and documentation
drafts to those instructions, and ran the checks.

**Pre-existing software and data.**
- Julia packages: HTTP.jl, JSON.jl and CSV.jl, plus the Julia standard libraries.
- npm packages: React, Vite, TypeScript, Plotly basic (plotly.js-basic-dist-min) and oxlint.
- R: used only to generate a reference fit for one test.
- Data: the fastR2 `Pendulum` dataset.

## Challenges I ran into

- **Hidden data.** Keeping hidden recorded values out of the recommendation took
  structural measures. The browser never receives them, the API checks that a demo request
  contains only the recorded values for lengths already revealed, and a test changes every
  hidden period and checks that the recommendation does not move.
- **Browser JSON.** A browser writes 16.0 as 16 and −0.0 as 0. Both broke the content
  hashes that prove a snapshot was not altered. Constant-response data triggered the −0.0
  case. I found it in an audit, reproduced it in a failing test, then fixed it.
- **Out-of-range numbers.** JSON numbers such as 1e999 parse as finite big-number types in
  Julia and turn into infinity only on conversion. That reached validation, and one route
  returned an HTTP 500 error, before I fixed it the same way.
- **Honest wording.** At one step on the pendulum replay, the support-weighted model spread
  is exactly 0 s, even though the predictions differ by about 3 s. That is because one model
  holds nearly all the support. The first version of the page called that "low
  separation", which was misleading. The page now says why the spread is 0 and shows the
  range of the unweighted predictions.

## Accomplishments that I'm proud of

- The full loop works in both modes, and 68 automated browser checks cover it. Those
  checks include double clicks, resets during pending requests, simulated server failures
  and exports.
- 386 backend checks pass. The fits match R's `lm()` to a relative tolerance of 1e-10.
- The benchmark is reproducible: a rerun with a different thread count gave byte-identical
  results. I report the losses as well as the wins.
- I reported the benchmark result as it came out, including where NextLab did not win.

## What I learned

- **Benchmarks.** The choice of baseline changed the conclusion. NextLab beat random choice in 11
  of 16 conditions, but most of that advantage came from measuring at distant settings,
  which the endpoints-then-maximin baseline also does. Against that baseline there was no
  clear difference in 14 of 16 conditions.
- **Recorded data.** On this replay, one model dominates from the start, so every
  recommendation is a space-filling check. Even so, freezing predictions showed something.
  The leading square-root model missed the 16 m result by about 11 times its own estimated
  uncertainty of a mean. That says the constant-noise assumption is too simple for these
  data.

## What's next

- Put NextLab in front of experimental researchers and trainees.
- Measure whether the frozen-prediction workflow changes what they record or how they
  choose settings.
- Compare NextLab against existing experimental-design and active-learning tools.
- Let noise change with x, and handle uncertainty in x.

## Missing fields and evidence to check before submitting

- **Track and rules.** I based the track description on the brief given to me: a Research
  Track about removing a research bottleneck. I have not seen the event's official rules
  page.
- **AI-use policy.** I have not seen the event's policy on AI assistance. The disclosure
  above describes how I used AI; check it against the official rules and adjust it if they
  ask for a different format.
- **Prizes.** I have not checked whether any additional prize categories apply. None are
  claimed here.
- **Video length.** I don't know the limit; the outline in `docs/VIDEO.md` assumes five minutes.
- **Deadline.** The submission deadline is not recorded anywhere in the project.
- **Event timing.** Confirm the event's official start time. The project's "built during the
  event" claim rests on the first commit time (14:10 on 2026-10-24).
- **Your role.** Confirm that the AI-assistance paragraph describes your own role accurately.
- **Links.** A GitHub remote exists (`origin`: github.com/Evan5050/research_project). Decide
  whether to make it public and link it. There is no hosted demo; the app runs locally only.
- **Team and other details.** The submitter name, team details and any school or
  affiliation fields are not filled in.
