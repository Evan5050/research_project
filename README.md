# NextLab

Compare three candidate models of y versus x, choose the next measurement, freeze
predictions before the outcome, and refit honestly. See `docs/SPEC.md`.

## Setup (macOS, Apple silicon, as used here)
```sh
brew install juliaup && juliaup add release        # Julia 1.13.2
julia --project=backend -e 'using Pkg; Pkg.instantiate()'
npm --prefix frontend ci                           # Node 26, npm 11
```

## Development (two terminals)
```sh
julia --project=backend --threads=auto,1 backend/scripts/serve.jl   # API on :8080
npm --prefix frontend run dev -- --host 127.0.0.1                   # UI on :5173, proxies /api
```
Open http://127.0.0.1:5173. The page should say "Julia backend responded" and show the demo start.

## Local demo (one command)
```sh
./nextlab        # builds the frontend, serves UI + API on http://127.0.0.1:8080, prints "NextLab READY"
```
Launch, readiness, reset and crash recovery: `docs/LAUNCH.md`. Screenshots of the running
app are in `docs/screenshots/`.

## API
Contract: `docs/API.md`. Live smoke check against a running server:
```sh
julia --project=backend backend/scripts/api_smoke.jl http://127.0.0.1:8080
```

## Tests
```sh
julia --project=backend --threads=auto,1 -e 'using Pkg; Pkg.test()'
```

Browser check of the full demo loop, using a real headless Chromium (Brave here) over the
DevTools protocol, with no extra npm packages. Run it against a server that serves the built frontend:
```sh
npm --prefix frontend run build
CHROME="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  node frontend/scripts/browser-check.mjs http://127.0.0.1:8080 /tmp/nextlab-shots
```
