# HTTP JSON API (contract: docs/API.md, mirrored in frontend/src/api.ts).
# Numerical requests are stateless: the browser holds an experiment `context` and sends
# it with every request. The server keeps no session table. Demo data lookups go through
# demo_adapter.jl; the scientific core sees only observed rows and candidate x values.

const API_VERSION = "0.2.0"
const MAX_OBSERVE_VALUES = 50
const MAX_HISTORY = 50
const RESULTS_DIR = normpath(joinpath(@__DIR__, "..", "..", "results", "benchmark_full"))
const MODEL_CONFIG = (method_version = METHOD_VERSION, families = [String(f.id) for f in MODEL_FAMILIES])

# ---- errors ----------------------------------------------------------------------------

struct RequestError <: Exception
    status::Int
    message::String
    fields::Vector{Tuple{String,String}}
end
RequestError(status, message) = RequestError(status, message, Tuple{String,String}[])

json_response(status::Integer, payload) =
    HTTP.Response(status, JSON.json(payload); headers = ["Content-Type" => "application/json"])

error_response(e::RequestError) =
    json_response(e.status, (error = e.message, fields = [(field = f, message = m) for (f, m) in e.fields]))

"Wrap a handler: request errors become 4xx JSON; anything else is a 500 without echoing the request."
function guarded(handler)
    return function (req::HTTP.Request)
        try
            return handler(req)
        catch e
            e isa RequestError && return error_response(e)
            @error "Unhandled API error" route = HTTP.URI(req.target).path exception = (e, catch_backtrace())
            return json_response(500, (error = "Internal error. The request was not processed.", fields = []))
        end
    end
end

function read_json(req::HTTP.Request)
    body = String(copy(req.body))
    ncodeunits(body) <= MAX_UPLOAD_BYTES || throw(RequestError(413, "The request is larger than the 2 MB prototype limit."))
    isempty(strip(body)) && return Dict{String,Any}()
    v = try
        JSON.parse(body)
    catch
        throw(RequestError(400, "The request body is not valid JSON."))
    end
    v isa AbstractDict || throw(RequestError(400, "The request body must be a JSON object."))
    return v
end

sha(s) = bytes2hex(sha256(s))

# Numbers become Float64 so a value that a browser rewrites (16.0 -> 16) hashes the same.
normalize(x::AbstractDict) = Dict{String,Any}(String(k) => normalize(v) for (k, v) in x)
normalize(x::AbstractVector) = Any[normalize(v) for v in x]
normalize(x::Bool) = x
normalize(x::Real) = Float64(x)
normalize(x) = x
canonical(x) = JSON.json(normalize(JSON.parse(JSON.json(x))); sort_keys = true)
content_hash(d::AbstractDict) = sha(canonical(Dict{String,Any}(k => v for (k, v) in d if k != "snapshot_id")))
new_session_id() = bytes2hex(rand(Random.RandomDevice(), UInt8, 16))

# ---- experiment context (client-held) --------------------------------------------------------

"Experiment state the browser sends with each request. Mirrors `ExperimentContext` in api.ts."
struct ExperimentContext
    mode::String                 # "demo" | "upload"
    session_id::String
    dataset_id::String
    observed::Vector{Tuple{Float64,Float64}}
    candidate_x::Vector{Float64}
    revealed_x::Vector{Float64}  # demo only
    response_sd::Union{Nothing,Float64}
    x_unit::String
    y_unit::String
end

"""
Revision of everything that can invalidate a pending recommendation: mode, session
(new on every start/reset/upload), dataset, observations, feasible settings, model
configuration and noise assumption.
"""
function context_revision(c::ExperimentContext)
    return sha(canonical((mode = c.mode, session_id = c.session_id, dataset_id = c.dataset_id,
                          model_config = MODEL_CONFIG, observed = [[x, y] for (x, y) in sort(c.observed)],
                          candidate_x = sort(unique(c.candidate_x)), revealed_x = sort(c.revealed_x),
                          response_sd = c.response_sd)))
end

context_json(c::ExperimentContext) = (mode = c.mode, session_id = c.session_id, dataset_id = c.dataset_id,
    observed = [(x = x, y = y) for (x, y) in c.observed], candidate_x = c.candidate_x, revealed_x = c.revealed_x,
    response_sd = c.response_sd, x_unit = c.x_unit, y_unit = c.y_unit)

function number_list(v, field, errs; maxlen)
    v isa AbstractVector || (push!(errs, (field, "Must be a list of numbers.")); return Float64[])
    length(v) <= maxlen || (push!(errs, (field, "At most $maxlen values are allowed in this prototype.")); return Float64[])
    out = Float64[]
    for (i, e) in enumerate(v)
        f = json_float(e)
        if f === nothing
            push!(errs, ("$field[$i]", "Must be a finite number within double-precision range."))
        else
            push!(out, f)
        end
    end
    return out
end

function str_field(o, key, field, errs; maxlen = 200, default = nothing)
    v = get(o, key, default)
    v isa AbstractString && ncodeunits(v) <= maxlen && return String(v)
    push!(errs, (field, "Must be text of at most $maxlen characters."))
    return ""
end

"Validate and build the context, or throw a 422 with field-level errors."
function parse_context(body::AbstractDict; key = "context")
    o = get(body, key, nothing)
    o isa AbstractDict || throw(RequestError(422, "Missing experiment context.", [(key, "Must be an object.")]))
    errs = Tuple{String,String}[]
    mode = str_field(o, "mode", "$key.mode", errs; maxlen = 10)
    mode in ("demo", "upload") || push!(errs, ("$key.mode", "Must be \"demo\" or \"upload\"."))
    session_id = str_field(o, "session_id", "$key.session_id", errs; maxlen = 64)
    occursin(r"^[0-9a-f]{32}$", session_id) || push!(errs, ("$key.session_id", "Must be a session id issued by this server."))
    dataset_id = str_field(o, "dataset_id", "$key.dataset_id", errs)
    obs_raw = get(o, "observed", nothing)
    observed = Tuple{Float64,Float64}[]
    if !(obs_raw isa AbstractVector)
        push!(errs, ("$key.observed", "Must be a list of {x, y} observations."))
    elseif length(obs_raw) > MAX_ROWS
        push!(errs, ("$key.observed", "At most $MAX_ROWS observations are allowed in this prototype."))
    else
        for (i, r) in enumerate(obs_raw)
            r isa AbstractDict || (push!(errs, ("$key.observed[$i]", "Must be an object with numeric x and y.")); continue)
            x, y = json_float(get(r, "x", nothing)), json_float(get(r, "y", nothing))
            okx = x !== nothing && x > 0
            okx || push!(errs, ("$key.observed[$i].x", "Must be a positive finite number within double-precision range."))
            y === nothing && push!(errs, ("$key.observed[$i].y", "Must be a finite number within double-precision range."))
            okx && y !== nothing && push!(observed, (x, y))
        end
    end
    cands = number_list(get(o, "candidate_x", nothing), "$key.candidate_x", errs; maxlen = MAX_CANDIDATES)
    for (i, c) in enumerate(cands)
        c > 0 || push!(errs, ("$key.candidate_x[$i]", "Feasible settings must be positive."))
    end
    revealed = number_list(get(o, "revealed_x", Any[]), "$key.revealed_x", errs; maxlen = 100)
    sd_raw = get(o, "response_sd", nothing)
    sd_f = json_float(sd_raw)
    sd = if sd_raw === nothing
        nothing
    elseif sd_f !== nothing && sd_f > 0
        sd_f
    else
        push!(errs, ("$key.response_sd", "Must be empty or a positive finite number.")); nothing
    end
    xu = str_field(o, "x_unit", "$key.x_unit", errs; maxlen = 20, default = "")
    yu = str_field(o, "y_unit", "$key.y_unit", errs; maxlen = 20, default = "")
    isempty(errs) || throw(RequestError(422, "The experiment context is invalid.", errs))

    if mode == "demo"
        dataset_id == DEMO_DATASET_ID || push!(errs, ("$key.dataset_id", "Demo mode uses the built-in dataset only."))
        append!(errs, demo_revealed_errors(revealed))
        if isempty(errs)
            expected = sort([(r.x, r.y) for r in demo_observed(revealed)])
            sort(observed) == expected || push!(errs, ("$key.observed", "Observed rows do not match the recorded demo data for the revealed lengths. Start the demo again."))
            sort(cands) == demo_remaining(revealed) || push!(errs, ("$key.candidate_x", "Demo candidates must be exactly the recorded lengths not yet revealed."))
        end
    else
        isempty(revealed) || push!(errs, ("$key.revealed_x", "Only demo mode reveals recorded settings."))
    end
    isempty(errs) || throw(RequestError(422, "The experiment context is inconsistent.", errs))
    return ExperimentContext(mode, session_id, dataset_id, observed, cands, revealed, sd, xu, yu)
end

run_analysis(c::ExperimentContext) =
    analyze(first.(c.observed), last.(c.observed), c.candidate_x; response_sd = c.response_sd, x_unit = c.x_unit, y_unit = c.y_unit)

function curves_for(a, c::ExperimentContext)
    a.data === nothing && return nothing
    xs = vcat(first.(c.observed), c.candidate_x)
    lo, hi = extrema(xs)
    lo == hi && return nothing
    return model_curves(a, lo, hi)
end

# ---- snapshots ------------------------------------------------------------------------------

function make_snapshot(a, c::ExperimentContext, revision::String)
    rec = a.recommendation
    content = (kind = "nextlab-prediction-snapshot", api_version = API_VERSION, context_revision = revision,
               session_id = c.session_id, mode = c.mode, dataset_id = c.dataset_id,
               record = freeze_predictions(a),
               selection = (kind = rec.kind, fallback_reason = rec.fallback_reason, method = rec.method,
                            explanation = a.explanation),
               diagnostic_state = (status = a.status, all_models_inadequate = a.all_models_inadequate,
                                   separation = rec.separation.label, noise_source = a.noise.source,
                                   codes = [d.code for d in a.diagnostics]))
    snap = JSON.parse(JSON.json(content))
    snap["snapshot_id"] = content_hash(snap)
    return snap
end

"Check a client-returned snapshot is unaltered and belongs to this exact context."
function verify_snapshot(body, c::ExperimentContext, revision::String; key = "snapshot")
    s = get(body, key, nothing)
    s isa AbstractDict || throw(RequestError(422, "Missing prediction snapshot.", [(key, "Must be the snapshot returned by /api/recommend.")]))
    get(s, "snapshot_id", nothing) == content_hash(s) ||
        throw(RequestError(422, "The prediction snapshot was altered or is not from this server.", [("$key.snapshot_id", "Does not match the snapshot content.")]))
    get(s, "session_id", nothing) == c.session_id ||
        throw(RequestError(409, "The snapshot belongs to a different session (the demo was reset or new data loaded).", [("$key.session_id", "Stale snapshot.")]))
    get(s, "context_revision", nothing) == revision ||
        throw(RequestError(409, "The data, settings or noise assumption changed after this recommendation, so it is no longer pending.", [("$key.context_revision", "Stale snapshot.")]))
    return s
end

frozen_models(s) = [(id = String(m["id"]), name = String(m["name"]), predicted_y = m["predicted_y"]) for m in s["record"]["models"]]

function outcome_payload(s, c::ExperimentContext, rows)
    xnew = s["record"]["x"]
    observed = vcat(c.observed, [(r.x, r.y) for r in rows])
    revealed = c.mode == "demo" ? vcat(c.revealed_x, [xnew]) : c.revealed_x
    cands = c.mode == "demo" ? [x for x in c.candidate_x if x != xnew] : c.candidate_x
    updated = ExperimentContext(c.mode, c.session_id, c.dataset_id, observed, cands, revealed, c.response_sd, c.x_unit, c.y_unit)
    return (snapshot_id = s["snapshot_id"], x = xnew, observations = rows,
            comparison = compare_to_frozen(frozen_models(s), Float64[r.y for r in rows];
                                           sd_individual = s["record"]["noise"]["sd_individual"]),
            refit_performed = false,
            updated_context = context_json(updated), updated_revision = context_revision(updated))
end

# ---- handlers --------------------------------------------------------------------------------

health(::HTTP.Request) = json_response(200, (status = "ok", service = "nextlab-backend",
    api_version = API_VERSION, julia_version = string(VERSION)))

function ready(::HTTP.Request)
    checks = [(name = "demo_data", ok = try demo_records(); true catch; false end),
              (name = "method", ok = METHOD_VERSION == "nextlab-core-1"),
              (name = "benchmark_results", ok = isfile(joinpath(RESULTS_DIR, "meta.json")))]
    ok = all(c -> c.ok, checks[1:2])                   # benchmark results are optional for readiness
    return json_response(ok ? 200 : 503, (ready = ok, checks = checks))
end

function demo_start(req::HTTP.Request)
    read_json(req)
    c = ExperimentContext("demo", new_session_id(), DEMO_DATASET_ID,
                          [(r.x, r.y) for r in demo_observed(Float64[])], demo_remaining(Float64[]), Float64[],
                          nothing, "m", "s")
    return json_response(200, (context = context_json(c), revision = context_revision(c), dataset = PENDULUM_PROVENANCE,
        counts = (lengths_measured = length(unique(first.(c.observed))), observations = length(c.observed),
                  remaining_lengths = length(c.candidate_x))))
end

function analyze_route(req::HTTP.Request)
    c = parse_context(read_json(req))
    a = run_analysis(c)
    return json_response(200, (revision = context_revision(c), session_id = c.session_id, status = a.status,
                                analysis = a, curves = curves_for(a, c)))
end

function recommend_route(req::HTTP.Request)
    c = parse_context(read_json(req))
    rev = context_revision(c)
    a = run_analysis(c)
    a.status == :insufficient_data && throw(RequestError(422, a.explanation,
        [("context.observed", "At least 3 distinct x values are needed; there are $(a.data.n_settings).")]))
    snap = a.status == :ok ? make_snapshot(a, c, rev) : nothing
    return json_response(200, (revision = rev, session_id = c.session_id, status = a.status, analysis = a,
                                curves = curves_for(a, c), snapshot = snap))
end

function demo_reveal_route(req::HTTP.Request)
    body = read_json(req)
    c = parse_context(body)
    c.mode == "demo" || throw(RequestError(422, "Reveal is only for the built-in demo; enter measured values instead.", [("context.mode", "Must be \"demo\".")]))
    rev = context_revision(c)
    s = verify_snapshot(body, c, rev)
    x = Float64(s["record"]["x"])
    x in c.candidate_x || throw(RequestError(422, "The frozen setting is not a remaining recorded length.", [("snapshot.record.x", "Unknown or already revealed demo setting.")]))
    rows = demo_reveal(c.revealed_x, x)
    return json_response(200, (revision = rev, session_id = c.session_id, outcome_payload(s, c, rows)...))
end

function observe_route(req::HTTP.Request)
    body = read_json(req)
    c = parse_context(body)
    c.mode == "upload" || throw(RequestError(422, "Demo mode reveals recorded values; manual entry is for uploaded data.", [("context.mode", "Must be \"upload\".")]))
    rev = context_revision(c)
    s = verify_snapshot(body, c, rev)
    errs = Tuple{String,String}[]
    ys = number_list(get(body, "y", nothing), "y", errs; maxlen = MAX_OBSERVE_VALUES)
    isempty(errs) && isempty(ys) && push!(errs, ("y", "Enter at least one measured value."))
    isempty(errs) || throw(RequestError(422, "The measured values are invalid.", errs))
    x = Float64(s["record"]["x"])
    rows = [(x = x, y = y) for y in ys]
    return json_response(200, (revision = rev, session_id = c.session_id, outcome_payload(s, c, rows)...))
end

function upload_route(req::HTTP.Request)
    body = read_json(req)
    errs = Tuple{String,String}[]
    text = get(body, "csv", nothing)
    text isa AbstractString || throw(RequestError(422, "No CSV text was provided.", [("csv", "Must be the file's text.")]))
    p = parse_upload_csv(text; x_column = get(body, "x_column", nothing), y_column = get(body, "y_column", nothing))
    append!(errs, p.errors)
    b = get(body, "bounds", nothing)
    cands = Float64[]
    if b isa AbstractDict
        grid, ge = feasible_grid(get(b, "lo", nothing), get(b, "hi", nothing), get(b, "n", nothing))
        append!(errs, ge); cands = grid
    elseif haskey(body, "candidate_x")
        cands = number_list(body["candidate_x"], "candidate_x", errs; maxlen = MAX_CANDIDATES)
        isempty(cands) && push!(errs, ("candidate_x", "List at least one feasible setting."))
        any(<=(0), cands) && push!(errs, ("candidate_x", "Feasible settings must be positive."))
    else
        push!(errs, ("bounds", "Give feasible bounds {lo, hi, n} or a candidate_x list for the next measurement."))
    end
    sd_raw = get(body, "response_sd", nothing)
    sd_f = json_float(sd_raw)
    sd_raw === nothing || (sd_f !== nothing && sd_f > 0) ||
        push!(errs, ("response_sd", "Must be empty or a positive finite number."))
    xu = str_field(body, "x_unit", "x_unit", errs; maxlen = 20, default = "")
    yu = str_field(body, "y_unit", "y_unit", errs; maxlen = 20, default = "")
    isempty(errs) || throw(RequestError(422, "The upload could not be used.", errs))
    c = ExperimentContext("upload", new_session_id(), "upload:" * first(sha(text), 16), collect(zip(p.x, p.y)),
                          cands, Float64[], sd_raw === nothing ? nothing : sd_f, xu, yu)
    return json_response(200, (context = context_json(c), revision = context_revision(c),
        columns = p.columns, x_column = p.x_column, y_column = p.y_column,
        counts = (observations = length(p.x), settings = length(unique(p.x)), candidates = length(cands))))
end

function feasible_route(req::HTTP.Request)
    body = read_json(req)
    grid, errs = feasible_grid(get(body, "lo", nothing), get(body, "hi", nothing), get(body, "n", nothing))
    isempty(errs) || throw(RequestError(422, "The feasible range is invalid.", errs))
    return json_response(200, (candidate_x = grid,))
end

function export_route(req::HTTP.Request)
    body = read_json(req)
    c = parse_context(body)
    rev = context_revision(c)
    hist = get(body, "history", Any[])
    hist isa AbstractVector && length(hist) <= MAX_HISTORY ||
        throw(RequestError(422, "History must be a list of at most $MAX_HISTORY snapshots.", [("history", "Invalid.")]))
    entries = map(enumerate(hist)) do (i, s)
        s isa AbstractDict || throw(RequestError(422, "Invalid history entry.", [("history[$i]", "Must be a snapshot.")]))
        get(s, "snapshot_id", nothing) == content_hash(s) && get(s, "session_id", nothing) == c.session_id ||
            throw(RequestError(422, "A history snapshot was altered or belongs to another session.", [("history[$i]", "Snapshot does not verify.")]))
        x = s["record"]["x"]
        ys = Float64[y for (xx, y) in c.observed if xx == x]
        (snapshot = s, outcome = isempty(ys) ? nothing : (x = x, observations = [(x = x, y = y) for y in ys],
                     comparison = compare_to_frozen(frozen_models(s), ys; sd_individual = s["record"]["noise"]["sd_individual"])))
    end
    a = run_analysis(c)
    return json_response(200, (format = "nextlab-experiment-record-1", exported_at = string(Dates.now(Dates.UTC)) * "Z",
        api_version = API_VERSION, model_config = MODEL_CONFIG, revision = rev, context = context_json(c),
        dataset = c.mode == "demo" ? PENDULUM_PROVENANCE :
                  (name = "Uploaded data", dataset_id = c.dataset_id, note = "Supplied by the user; NextLab makes no claim about its provenance."),
        history = entries, current_analysis = a))
end

function benchmark_route(::HTTP.Request)
    isfile(joinpath(RESULTS_DIR, "meta.json")) ||
        throw(RequestError(404, "No saved benchmark results. Run: julia --project=backend --threads=auto backend/scripts/run_benchmark.jl full 100"))
    meta = JSON.parse(read(joinpath(RESULTS_DIR, "meta.json"), String))
    rows(f) = [NamedTuple(r) for r in CSV.File(joinpath(RESULTS_DIR, f))]
    final = Int(Benchmark.N_FINAL)
    primary = [r for r in rows("paired.csv") if r.n_settings == final]
    summary = [r for r in rows("summary.csv") if r.n_settings == final]
    verdicts = [(baseline = b, better = count(r -> r.baseline == b && r.verdict == "NextLab better", primary),
                 no_clear = count(r -> r.baseline == b && r.verdict == "no clear difference", primary),
                 worse = count(r -> r.baseline == b && r.verdict == "NextLab worse", primary))
                for b in String.(Benchmark.BASELINES)]
    return json_response(200, (meta = meta, primary_endpoint = (n_settings = final, n_observations = final * Benchmark.REPS),
        verdicts = verdicts, paired = primary, summary = summary, nextlab_choices = rows("nextlab_choices.csv"),
        reproduce = (command = "julia --project=backend --threads=auto backend/scripts/run_benchmark.jl full 100",
                     protocol = "docs/BENCHMARK.md", results_dir = "results/benchmark_full")))
end

not_found(::HTTP.Request) = json_response(404, (error = "not found", fields = []))

"""
    router(; static_dir = nothing)

When `static_dir` points at a built frontend, paths outside `/api` are served from it.
"""
function router(; static_dir::Union{Nothing,AbstractString} = nothing)
    fallback = static_dir === nothing ? not_found : HTTP.fileserver(static_dir; spa_fallback = "index.html")
    r = HTTP.Router(fallback)
    for (method, path, h) in (("GET", "/api/health", health), ("GET", "/api/ready", ready),
                              ("POST", "/api/demo/start", demo_start), ("POST", "/api/demo/reveal", demo_reveal_route),
                              ("POST", "/api/analyze", analyze_route), ("POST", "/api/recommend", recommend_route),
                              ("POST", "/api/upload", upload_route), ("POST", "/api/feasible", feasible_route),
                              ("POST", "/api/observe", observe_route), ("POST", "/api/export", export_route),
                              ("GET", "/api/benchmark", benchmark_route))
        HTTP.register!(r, method, path, guarded(h))
    end
    HTTP.register!(r, "/api/**", not_found)
    return r
end

"""
    start_server(; host = "127.0.0.1", port = 8080, static_dir = nothing) -> HTTP.Server

Binds to localhost by default. Request bodies over 2 MB get 413 from HTTP.jl.
"""
start_server(; host = "127.0.0.1", port::Integer = 8080, static_dir = nothing) =
    HTTP.serve!(router(; static_dir), host, port; max_body_bytes = MAX_UPLOAD_BYTES)
