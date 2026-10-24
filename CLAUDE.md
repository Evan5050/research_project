# NextLab — working contract

NextLab helps a research trainee who reads plots but does not write analysis code
compare three predefined two-parameter models of y versus x, choose one feasible next
measurement, freeze each model's prediction before the outcome is seen, and refit
honestly. Hackathon Research Track entry; aim for a working, defensible demo, not a
promise of winning.

Details: `docs/SPEC.md` (decisions). Current state: `docs/STATUS.md` (facts only).

## Rules
- **Skills:** only `how`, `unslop`, `in-your-own-words`, `sharpen`, `tdd`. Add no others; do not switch models.
- **Out of scope:** chatbot or LLM narration, literature search, symbolic regression or
  free-form equation discovery, accounts, databases, collaboration, sensors, a second
  scientific domain, more than one input variable.
- **Data honesty:** cite every real dataset; never imply the user collected it. Describe
  reported pendulum periods as averages over several swings. Keep synthetic benchmarks
  labelled and separate. Report missing noise information as missing.
- **No hidden-outcome leakage:** the recommender sees only observed (x, y), candidate x
  values, and bounds. Unrevealed y values and simulator truth never reach it; a test
  enforces this.
- **No fake success:** no stub responses, no JavaScript substitute for Julia numerics.
- **Meaningful verification:** a change counts as done only after real commands
  (tests, builds, live requests) pass. Report failures as failures.
- **Preserve working behavior:** keep tests green; do not break the experiment loop to add features.
