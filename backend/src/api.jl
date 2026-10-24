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

# Numbers become Float64 so a value that a browser rewrites hashes the same: 16.0 -> 16, and
# -0.0 -> 0 (JSON.stringify drops the sign of zero), so signed zero canonicalizes to 0.0.
normalize(x::AbstractDict) = Dict{String,Any}(String(k) => normalize(v) for (k, v) in x)
normalize(x::AbstractVector) = Any[normalize(v) for v in x]
normalize(x::Bool) = x
normalize(x::Real) = (f = Float64(x); iszero(f) ? 0.0 : f)
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
    # Descriptive only (not part of the revision): how the browser labels the data.
    x_label::String
    y_label::String
    source_name::String
end

"Copy of `c` with new data and the same session, units and labels."
with_data(c::ExperimentContext; observed = c.observed, candidate_x = c.candidate_x, revealed_x = c.revealed_x,
          response_sd = c.response_sd) =
    ExperimentContext(c.mode, c.session_id, c.dataset_id, observed, candidate_x, revealed_x, response_sd,
                      c.x_unit, c.y_unit, c.x_label, c.y_label, c.source_name)

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
    response_sd = c.response_sd, x_unit = c.x_unit, y_unit = c.y_unit, x_label = c.x_label, y_label = c.y_label,
    source_name = c.source_name)

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
    xl = str_field(o, "x_label", "$key.x_label", errs; maxlen = 80, default = "")
    yl = str_field(o, "y_label", "$key.y_label", errs; maxlen = 80, default = "")
    src = str_field(o, "source_name", "$key.source_name", errs; maxlen = 120, default = "")
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
    return ExperimentContext(mode, session_id, dataset_id, observed, cands, revealed, sd, xu, yu, xl, yl, src)
end

run_analysis(c::ExperimentContext) =
    analyze(first.(c.observed), last.(c.observed), c.candidate_x; response_sd = c.response_sd, x_unit = c.x_unit, y_unit = c.y_unit)

function curves_for(a, c::ExperimentContext)
    a.data === nothing && return nothing
    xs = vcat(first.(c.observed), c.candidate_x)
    lo, hi = extrema(xs)
    lo == hi && return nothing
    return model_curves(a, lo, hi; include = collect(extrema(first.(c.observed))))
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
    updated = with_data(c; observed, candidate_x = cands, revealed_x = revealed)
    return (snapshot_id = s["snapshot_id"], x = xnew, observations = rows,
            comparison = compare_to_frozen(frozen_models(s), Float64[r.y for r in rows];
                                           sd_individual = s["record"]["noise"]["sd_individual"]),
            refit_performed = false,
            updated_context = context_json(updated), updated_revision = context_revision(updated))
end

# ---- handlers --------------------------------------------------------------------------------

health(::HTTP.Request) = json_response(200, (status = "ok", service = "nextlab-backend",
    api_version = API_VERSION, julia_version = string(VERSION)))

"Set by `warmup` once the demo and upload code paths have run once (see scripts/serve.jl)."
const WARM = Ref(false)
const WARMUP_TIMING = Ref{Any}(nothing)

function ready(::HTTP.Request)
    checks = [(name = "demo_data", ok = try demo_records(); true catch; false end),
              (name = "method", ok = METHOD_VERSION == "nextlab-core-1"),
              (name = "warmed_up", ok = WARM[]),
              (name = "benchmark_results", ok = isfile(joinpath(RESULTS_DIR, "meta.json")))]
    ok = all(c -> c.ok, checks[1:3])                   # benchmark results are optional for readiness
    return json_response(ok ? 200 : 503, (ready = ok, checks = checks, warmup = WARMUP_TIMING[]))
end

"""
    warmup(base; repeats = 20) -> NamedTuple

Exercise the demo and upload routes once over real HTTP so their code is compiled before
a person uses the app, then time steady-state demo requests. Uses its own throwaway
sessions and an in-memory synthetic CSV; no state is kept (the API is stateless), so the
next `/api/demo/start` begins at the declared initial demo.
"""
function warmup(base::AbstractString; repeats::Integer = 20)
    post(path, body) = JSON.parse(String(HTTP.post(base * path, ["Content-Type" => "application/json"], JSON.json(body)).body))
    first_pass = @elapsed begin
        HTTP.get(base * "/api/health"); HTTP.get(base * "/"; status_exception = false)
        st = post("/api/demo/start", Dict()); ctx = st["context"]
        post("/api/analyze", Dict("context" => ctx))
        snap = post("/api/recommend", Dict("context" => ctx))["snapshot"]
        rv = post("/api/demo/reveal", Dict("context" => ctx, "snapshot" => snap))
        post("/api/analyze", Dict("context" => rv["updated_context"]))
        post("/api/export", Dict("context" => rv["updated_context"], "history" => [Dict("snapshot" => snap, "updated" => true)]))
        csv = "x,y\n1,2.0\n1,2.1\n2,2.9\n4,4.1\n"          # synthetic warmup data, never shown
        post("/api/upload/preview", Dict("csv" => csv))
        up = post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 1, "hi" => 4, "step" => 1), "candidate_x" => [6]))
        us = post("/api/recommend", Dict("context" => up["context"]))["snapshot"]
        post("/api/observe", Dict("context" => up["context"], "snapshot" => us, "y" => [5.0]))
        HTTP.get(base * "/api/benchmark"; status_exception = false)
    end
    ctx = post("/api/demo/start", Dict())["context"]
    times = [(@elapsed post("/api/recommend", Dict("context" => ctx))) for _ in 1:repeats]
    sort!(times)
    WARMUP_TIMING[] = (first_pass_seconds = first_pass, steady_recommend_median_ms = 1000 * times[cld(repeats, 2)],
                       steady_recommend_max_ms = 1000 * last(times), repeats = repeats)
    WARM[] = true
    return WARMUP_TIMING[]
end

function demo_start(req::HTTP.Request)
    read_json(req)
    c = ExperimentContext("demo", new_session_id(), DEMO_DATASET_ID,
                          [(r.x, r.y) for r in demo_observed(Float64[])], demo_remaining(Float64[]), Float64[],
                          nothing, "m", "s", "Pendulum length", "Reported period", PENDULUM_PROVENANCE.name)
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
    cands, fe = feasible_settings(get(body, "bounds", nothing), get(body, "candidate_x", nothing))
    append!(errs, fe)
    sd_raw = get(body, "response_sd", nothing)
    sd_f = json_float(sd_raw)
    sd_raw === nothing || (sd_f !== nothing && sd_f > 0) ||
        push!(errs, ("response_sd", "Must be empty or a positive finite number."))
    xu = str_field(body, "x_unit", "x_unit", errs; maxlen = 20, default = "")
    yu = str_field(body, "y_unit", "y_unit", errs; maxlen = 20, default = "")
    xl = str_field(body, "x_label", "x_label", errs; maxlen = 80, default = "")
    yl = str_field(body, "y_label", "y_label", errs; maxlen = 80, default = "")
    src = str_field(body, "source_name", "source_name", errs; maxlen = 120, default = "")
    isempty(errs) || throw(RequestError(422, "The upload could not be used.", errs))
    c = ExperimentContext("upload", new_session_id(), "upload:" * first(sha(text), 16), collect(zip(p.x, p.y)),
                          cands, Float64[], sd_raw === nothing ? nothing : sd_f, xu, yu,
                          isempty(xl) ? p.x_column : xl, isempty(yl) ? p.y_column : yl, isempty(src) ? "Uploaded CSV" : src)
    lo, hi = extrema(p.x)
    return json_response(200, (context = context_json(c), revision = context_revision(c),
        columns = p.columns, x_column = p.x_column, y_column = p.y_column,
        counts = (observations = length(p.x), settings = length(unique(p.x)), candidates = length(cands),
                  candidates_outside_observed_range = count(x -> x < lo || x > hi, cands)),
        observed_range = (lo = lo, hi = hi)))
end

function preview_route(req::HTTP.Request)
    body = read_json(req)
    text = get(body, "csv", nothing)
    text isa AbstractString || throw(RequestError(422, "No CSV text was provided.", [("csv", "Must be the file's text.")]))
    p = preview_upload_csv(text)
    p.ok || isempty(p.columns) && throw(RequestError(422, "The file could not be previewed.", p.errors))
    return json_response(200, (columns = p.columns, n_rows = p.n_rows, rows = p.rows, column_info = p.column_info,
                               problems = [(field = f, message = m) for (f, m) in p.errors]))
end

sample_route(::HTTP.Request) = HTTP.Response(200, read(PENDULUM_DERIVED_CSV);
    headers = ["Content-Type" => "text/csv", "Content-Disposition" => "attachment; filename=\"nextlab_sample_pendulum_length_period.csv\""])

function feasible_route(req::HTTP.Request)
    body = read_json(req)
    bounds = any(k -> haskey(body, k), ("lo", "hi", "n", "step")) ?
        Dict{String,Any}(k => body[k] for k in ("lo", "hi", "n", "step") if haskey(body, k)) : nothing
    grid, errs = feasible_settings(bounds, get(body, "candidate_x", nothing))
    isempty(errs) || throw(RequestError(422, "The feasible settings are invalid.", errs))
    return json_response(200, (candidate_x = grid,))
end

"Observation origin for the record: rows at a frozen recommendation's x came from that cycle."
function observation_origins(c::ExperimentContext, cycles)
    initial = c.mode == "demo" ? "recorded_initial_subset" : "uploaded_file"
    later = c.mode == "demo" ? "revealed_recorded_value" : "entered_manually"
    return map(c.observed) do (x, y)
        k = findfirst(e -> Float64(e.snapshot["record"]["x"]) == x, cycles)
        (x = x, y = y, origin = k === nothing ? initial : later, cycle = k)
    end
end

csv_field(s) = occursin(r"[\",\n]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s

function export_route(req::HTTP.Request)
    body = read_json(req)
    c = parse_context(body)
    rev = context_revision(c)
    hist = get(body, "history", Any[])
    hist isa AbstractVector && length(hist) <= MAX_HISTORY ||
        throw(RequestError(422, "History must be a list of at most $MAX_HISTORY entries.", [("history", "Invalid.")]))
    cycles = map(enumerate(hist)) do (i, h)
        s = h isa AbstractDict && haskey(h, "snapshot") ? h["snapshot"] : h
        s isa AbstractDict && get(s, "snapshot_id", nothing) == content_hash(s) && get(s, "session_id", nothing) == c.session_id ||
            throw(RequestError(422, "A history snapshot was altered or belongs to another session.", [("history[$i]", "Snapshot does not verify.")]))
        (snapshot = s, updated = h isa AbstractDict && get(h, "updated", false) === true)
    end
    obs = observation_origins(c, cycles)
    entries = map(enumerate(cycles)) do (k, e)
        s = e.snapshot
        x = s["record"]["x"]
        ys = Float64[o.y for o in obs if o.cycle == k]
        (order = k, snapshot_id = s["snapshot_id"], context_revision = s["context_revision"],
         data_revision = s["record"]["data_revision"], frozen_at = s["record"]["created_at"], selected_x = x,
         selection = s["selection"], diagnostic_state = s["diagnostic_state"],
         frozen_predictions = s["record"]["models"], frozen_noise = s["record"]["noise"],
         acquisition = s["record"]["acquisition"],
         later_observations = [(x = x, y = y) for y in ys],
         comparison = isempty(ys) ? nothing :
             compare_to_frozen(frozen_models(s), ys; sd_individual = s["record"]["noise"]["sd_individual"]),
         refit_after_observation = e.updated)
    end
    a = run_analysis(c)
    demo = c.mode == "demo"
    xh = isempty(c.x_unit) ? c.x_label : "$(c.x_label) ($(c.x_unit))"
    yh = isempty(c.y_unit) ? c.y_label : "$(c.y_label) ($(c.y_unit))"
    csv = join(vcat(join(csv_field.([xh, yh, "origin", "cycle"]), ","),
                    ["$(repr(o.x)),$(repr(o.y)),$(o.origin),$(something(o.cycle, ""))" for o in obs]), "\n") * "\n"
    content = (format = "nextlab-experiment-record-2", api_version = API_VERSION,
        run_type = demo ? "recorded_data_replay" : "user_uploaded_data",
        source = demo ?
            (label = "Recorded pendulum measurements", dataset_id = c.dataset_id, provenance = PENDULUM_PROVENANCE,
             note = "Revealed values are recorded measurements from the source dataset, revealed one length at a time during a replay; they were not measured in this session. Unrevealed recorded values are not included.") :
            (label = "User-uploaded data", name = c.source_name, dataset_id = c.dataset_id,
             note = "Supplied by the user. Every uploaded row was observed before the session; later rows were entered manually. NextLab makes no claim about provenance."),
        session_id = c.session_id, revision = rev,
        variables = (x = (label = c.x_label, unit = c.x_unit), y = (label = c.y_label, unit = c.y_unit)),
        method = (version = METHOD_VERSION, models = [(id = f.id, name = f.name, formula = f.formula, note = f.note) for f in MODEL_FAMILIES],
                  summary = "Each model is fitted to setting means with equal weight; grouped validation leaves one setting out; relative support is a heuristic weight from validation error, not a probability."),
        feasible_settings = c.candidate_x,
        noise_assumption = (stated_response_sd = c.response_sd, current_estimate = a.noise),
        observations = obs, cycles = entries,
        current_analysis = (status = a.status, data_revision = a.data === nothing ? nothing : a.data.revision,
                            models = a.models, diagnostics = a.diagnostics, all_models_inadequate = a.all_models_inadequate,
                            explanation = a.explanation))
    record = JSON.parse(JSON.json(content))
    return json_response(200, (record_id = content_hash(record), exported_at = string(Dates.now(Dates.UTC)) * "Z",
                                record = record, observations_csv = csv))
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
    return json_response(200, (meta = meta, current_method_version = METHOD_VERSION,
        results_match_current_method = get(meta, "method_version", nothing) == METHOD_VERSION,
        primary_endpoint = (n_settings = final, n_observations = final * Benchmark.REPS),
        verdicts = verdicts, paired = primary, summary = summary, nextlab_choices = rows("nextlab_choices.csv"),
        reproduce = (command = "julia --project=backend --threads=auto backend/scripts/run_benchmark.jl full 100",
                     protocol = "docs/BENCHMARK.md", results_dir = "results/benchmark_full")))
end

const BENCHMARK_FILES = Dict("runs.csv" => "text/csv", "summary.csv" => "text/csv", "paired.csv" => "text/csv",
                             "nextlab_choices.csv" => "text/csv", "meta.json" => "application/json")

"Download one saved benchmark result file by exact name (whitelist; no path components)."
function benchmark_file_route(req::HTTP.Request)
    name = HTTP.getparam(req, "name")
    haskey(BENCHMARK_FILES, name) ||
        throw(RequestError(404, "Unknown benchmark file.", [("name", "One of: $(join(sort(collect(keys(BENCHMARK_FILES))), ", ")).")]))
    path = joinpath(RESULTS_DIR, name)
    isfile(path) || throw(RequestError(404, "No saved benchmark results."))
    return HTTP.Response(200, read(path); headers = ["Content-Type" => BENCHMARK_FILES[name],
                                                    "Content-Disposition" => "attachment; filename=\"nextlab_benchmark_$name\""])
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
                              ("POST", "/api/upload", upload_route), ("POST", "/api/upload/preview", preview_route),
                              ("GET", "/api/sample.csv", sample_route), ("POST", "/api/feasible", feasible_route),
                              ("POST", "/api/observe", observe_route), ("POST", "/api/export", export_route),
                              ("GET", "/api/benchmark", benchmark_route),
                              ("GET", "/api/benchmark/files/{name}", benchmark_file_route))
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
