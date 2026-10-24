# Launch and recover NextLab (local)

NextLab runs as a local Julia server on `127.0.0.1`. It serves the built web page and the
API, so a server process must be running. It is not serverless. Once dependencies are
installed, the built-in demo needs no external network: the dataset, Plotly and every
frontend asset are local.

**One-time setup** (downloads dependencies once): see `README.md`, "Setup".

## Checklist
1. **Start:** run `./nextlab` from the project root. It builds the frontend from the
   installed `node_modules`, then starts Julia.
2. **Verify readiness:** wait for the line `NextLab READY at http://127.0.0.1:8080 […]`,
   or check that `curl -s http://127.0.0.1:8080/api/ready` shows `"ready":true` (HTTP 200).
   Before warmup finishes, `/api/ready` returns 503 and `warmed_up: false`.
   - Measured on this laptop: about 15 s from `./nextlab` to ready. Package load and
     server start take about 1 s; the warmup's first pass, which includes JIT compilation,
     takes 10.8–11.4 s.
   - After warmup, a steady-state `/api/recommend` has a median of 1.2 ms (20 requests).
     These are timings of this implementation only; it has not been compared with any other.
3. **Open:** http://127.0.0.1:8080. The page should show "Recorded pendulum measurements",
   "Known now: 3 lengths, 9 period observations" and an enabled "Recommend next measurement".
4. **Reset the demo:** click **Reset demo**, top right. It starts a new session at the
   declared initial subset; any response still in flight from before the reset is ignored.
   Warmup keeps no state, so the first visitor also sees the initial subset.
5. **Restart after a crash** (or a hang):
   - Stop anything left on the port: `lsof -tiTCP:8080 -sTCP:LISTEN | xargs kill`.
   - Run `./nextlab` again and wait for READY (measured: 16 s after a `kill -9`).
   - Reload the page. In-progress browser state is lost, so download the record first if you need it.
   - If `./nextlab` says the port is in use, either NextLab is already running (check
     `/api/ready`) or another program is using it. Then use `NEXTLAB_PORT=8090 ./nextlab`
     and open that port instead.

## Two-command alternative (same result)
```sh
npm --prefix frontend run build
julia --project=backend --threads=auto,1 backend/scripts/serve.jl
```

## Verification used
- `frontend/scripts/browser-check.mjs`: 68 checks in headless Brave, including keyboard
  focus, reset, crash-free page, and **no requests outside localhost**. HTTPS was blocked
  for the whole run and every request URL was recorded.
- `backend/scripts/api_smoke.jl`.
- **Limitation:** the Julia process was not run under an OS-level network block. A code
  review shows its only HTTP calls go to its own local URL (warmup).
