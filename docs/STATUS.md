# NextLab status

_Last updated: 2026-10-24, about 16:10 EDT. Milestone: Prompt 03, built-in dataset and provenance._

## Deadline
- **Earliest submission deadline: UNKNOWN.** The event information has not been supplied in
  the working session. Get the submission-creation and final submission deadlines from
  the organizers, record them here, and keep the last two hours before the real deadline
  for demo and submission work.
- Remaining build estimate from the user: more than 12 hours, solo.

## Works now (verified)
- **Toolchain:** Julia 1.13.2 (Homebrew `juliaup`). `backend/` package `NextLab` uses HTTP 2.12.3,
  JSON 1.12.2, CSV 1.1.0 and the standard libraries, with a resolved `Manifest.toml`.
  Nothing has been committed to git yet.
  `frontend/` uses Vite 8, React 19 and TypeScript 6. Vite proxies `/api` to port 8080, and
  Julia serves `frontend/dist` when it exists.
- **API:** `GET /api/health`, `GET /api/pendulum` (provenance plus public replay state) and
  `POST /api/pendulum/reset`. Unknown `/api/*` paths return a JSON 404.
- **Data:** `data/pendulum/` holds the untouched fastR2 snapshot and the derived
  `length_m,period_s` file. `data/README.md` has the source, attribution, license, hashes
  and limitations.
  - The source `.rda` hash matches the supplied hash.
  - The `.rda` values, loaded in R, match the snapshot.
- **Replay engine** (`backend/src/replay.jl`):
  - starts at the three shortest lengths, with 6 candidate lengths
  - `reveal!` moves all three reported periods at one recorded length and refuses
    lengths that are unrecorded or already used
  - `reset!` restores the exact initial state
  - `engine_inputs` returns observed x and y plus candidate x only
- **Frontend:** shows the backend status, provenance, the starting scenario table, the counts
  (lengths and observations), the remaining candidate lengths (no periods), the
  limitations, and a reset button.

## Commands run and their outcomes
- `julia --project=backend --threads=auto,1 -e 'using Pkg; Pkg.test()'`: 45/45 pass.
  The suites are pendulum snapshot 10, replay contract 21 and API 14. They include
  rejecting malformed snapshots, checking that engine inputs don't change when hidden
  outcomes are altered, and checking that the payload has no hidden period, both in
  process and over HTTP.
- `npm run lint`: clean. `npm run build`: passes.
- `julia --project=backend backend/scripts/scan_hidden.jl …`:
  - positive control on the source CSV: finds 18 values, as expected
  - `frontend/dist` and `frontend/src`: none
  - live `/api/pendulum` payload fetched through the Vite proxy: none
  - An earlier macOS `grep` scan was invalid (BSD grep ignored the `(^|…)` pattern), so it was replaced by this script.
- `curl` through the proxy: `/api/pendulum` returns 9 observations, 3 lengths and the 6
  candidates. Reset returns 200.
- **Not done:** no visual browser check. Browser control was not available.

## Not built yet
- reveal endpoint and UI (it will be gated on frozen predictions)
- fitting, recommendation and freezing
- new-observation mode, CSV upload and uploaded-data bounds
- plots (Plotly not installed yet), record download and the benchmark
- no license chosen for NextLab's own code

## Next
Prompt 04: the numerical method.
