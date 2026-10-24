# NextLab status

_Last updated: 2026-10-24, about 15:45 EDT. Milestone: Prompt 02, initial connection._

## Deadline
- **Earliest submission deadline: UNKNOWN.** The event information was never supplied in the
  working session, so no deadline was found. Get the submission-creation and final
  submission deadlines from the organizers, record them here, and keep the last two
  hours before the real deadline for demo and submission work.
- Remaining build estimate from the user: more than 12 hours, solo.

## Works now (verified)
- Julia 1.13.2 is installed with Homebrew `juliaup` 1.22.10 on the `release` channel.
- `backend/` package `NextLab` has resolved dependencies and a committed `Manifest.toml`:
  HTTP 2.12.3, JSON 1.12.2, CSV 1.1.0, plus Statistics, LinearAlgebra and Random. Test is test-only.
- `GET /api/health` returns
  `{"status":"ok","service":"nextlab-backend","api_version":"0.1.0","julia_version":"1.13.2"}`.
  Unknown `/api/*` paths return a JSON 404.
- `frontend/` (Vite 8, React 19, TypeScript 6) shows whether the Julia backend responded.
  Vite proxies `/api` to port 8080.
- When `frontend/dist` exists, the Julia process also serves the built page.

## Commands run and their outcomes
- `julia --project=backend --threads=auto,1 -e 'using Pkg; Pkg.test()'`: 7/7 tests pass.
- `npm run build` in `frontend/`: passes. `npm run lint`: no warnings.
- `curl` to `127.0.0.1:8080/api/health` and to `127.0.0.1:5173/api/health` (through the proxy): both 200 with the JSON above.
- `curl 127.0.0.1:8080/` returns the built page (`<title>NextLab</title>`).
- **Not done:** no visual browser check. Browser control was not available in the session.

## Not built yet
Everything in the core loop: data loading, fitting, recommendation, freezing, reveal,
refit, CSV upload, plots (Plotly not installed yet), record download, and the benchmark.

## Next
Prompt 03: the dataset snapshot and attribution.
