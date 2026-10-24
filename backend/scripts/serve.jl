# Run the NextLab API (and, if built, the frontend) in the foreground.
#   julia --project=backend --threads=auto,1 backend/scripts/serve.jl
# Environment: NEXTLAB_PORT (default 8080), NEXTLAB_STATIC (default frontend/dist if it exists).

using NextLab

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
port = parse(Int, get(ENV, "NEXTLAB_PORT", "8080"))
default_static = joinpath(ROOT, "frontend", "dist")
static_dir = get(ENV, "NEXTLAB_STATIC", isdir(default_static) ? default_static : "")
static_dir = isempty(static_dir) ? nothing : static_dir

server = NextLab.start_server(; port, static_dir)
@info "NextLab listening" url = "http://127.0.0.1:$port" api = "http://127.0.0.1:$port/api/health" static = something(static_dir, "none (API only)")
wait(server)
