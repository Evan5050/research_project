# HTTP JSON API. Handlers return real computed values; there are no stub responses.

const API_VERSION = "0.1.0"

json_response(status::Integer, payload) =
    HTTP.Response(status, JSON.json(payload); headers = ["Content-Type" => "application/json"])

function health(::HTTP.Request)
    return json_response(200, (
        status = "ok",
        service = "nextlab-backend",
        api_version = API_VERSION,
        julia_version = string(VERSION),
    ))
end

not_found(::HTTP.Request) = json_response(404, (error = "not found",))

# One local replay session per server process (local-first single-user demo).
const SESSION_LOCK = ReentrantLock()
const SESSION = Ref{Union{Nothing,ReplaySession}}(nothing)

function with_session(f)
    lock(SESSION_LOCK) do
        SESSION[] === nothing && (SESSION[] = ReplaySession())
        f(SESSION[])
    end
end

pendulum_payload(s::ReplaySession) = (provenance = PENDULUM_PROVENANCE, state = public_state(s))

pendulum(::HTTP.Request) = with_session(s -> json_response(200, pendulum_payload(s)))

pendulum_reset(::HTTP.Request) = with_session(s -> json_response(200, pendulum_payload(reset!(s))))

"""
    router(; static_dir = nothing)

Build the request router. When `static_dir` points at a built frontend, paths
outside `/api` are served from it so one Julia process can run the whole demo.
"""
function router(; static_dir::Union{Nothing,AbstractString} = nothing)
    fallback = static_dir === nothing ? not_found :
        HTTP.fileserver(static_dir; spa_fallback = "index.html")
    r = HTTP.Router(fallback)
    HTTP.register!(r, "GET", "/api/health", health)
    HTTP.register!(r, "GET", "/api/pendulum", pendulum)
    HTTP.register!(r, "POST", "/api/pendulum/reset", pendulum_reset)
    HTTP.register!(r, "/api/**", not_found)
    return r
end

"""
    start_server(; host = "127.0.0.1", port = 8080, static_dir = nothing) -> HTTP.Server

Start the API in the background. Use `port = 0` for a free port (tests).
"""
start_server(; host = "127.0.0.1", port::Integer = 8080, static_dir = nothing) =
    HTTP.serve!(router(; static_dir), host, port)
