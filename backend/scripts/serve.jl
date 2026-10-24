# Run NextLab locally: the Julia API plus the built frontend (frontend/dist), on 127.0.0.1.
#   julia --project=backend --threads=auto,1 backend/scripts/serve.jl
# Environment: NEXTLAB_PORT (default 8080), NEXTLAB_STATIC (default frontend/dist if it exists).
# Prints "NextLab READY" once the demo and upload paths are warmed up; /api/ready agrees.

const T0 = time()
using NextLab
const LOADED = time() - T0

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
port = parse(Int, get(ENV, "NEXTLAB_PORT", "8080"))
default_static = joinpath(ROOT, "frontend", "dist")
static_dir = get(ENV, "NEXTLAB_STATIC", isdir(default_static) ? default_static : "")
static_dir = isempty(static_dir) ? nothing : static_dir
static_dir === nothing && @warn "No built frontend found; serving the API only. Run: npm --prefix frontend run build"

t_start = time()
server = try
    NextLab.start_server(; port, static_dir)
catch e
    msg = sprint(showerror, e)
    occursin(r"address already in use|EADDRINUSE"i, msg) || rethrow()
    println(stderr, "Port $port is already in use. Another NextLab may be running: check http://127.0.0.1:$port/api/ready, ",
            "or stop it (lsof -tiTCP:$port -sTCP:LISTEN | xargs kill) and start again.")
    exit(1)
end
listening = time() - t_start
base = "http://127.0.0.1:$port"
println("NextLab listening on $base (package load ", round(LOADED; digits = 1), " s, server start ", round(listening; digits = 1), " s); warming up…")
flush(stdout)
w = NextLab.warmup(base)
println("NextLab READY at $base  [first pass incl. compilation: ", round(w.first_pass_seconds; digits = 1),
        " s; steady-state /api/recommend median ", round(w.steady_recommend_median_ms; digits = 1), " ms, max ",
        round(w.steady_recommend_max_ms; digits = 1), " ms over $(w.repeats) requests]")
flush(stdout)
wait(server)
