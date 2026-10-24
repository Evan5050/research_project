# Real-data replay: a declared teaching scenario over the recorded pendulum data.
#
# Contract:
# - Start with the three shortest distinct lengths (chosen by x order, not by outcome).
# - The remaining recorded lengths are the only candidate settings.
# - One reveal moves every reported observation at one selected length into the observed set.
# - Only observed records may reach fitting, noise estimation or acquisition scoring;
#   `engine_inputs` is the single gateway and carries candidate x values only.
# - Hidden outcomes never leave this file except through `reveal!`.

struct Observation
    x::Float64
    y::Float64
end

"Recorded outcomes that have not been revealed. Never serialised, never passed to the engine."
struct HiddenOutcomes
    by_x::Dict{Float64,Vector{Float64}}
end

mutable struct ReplaySession
    observed::Vector{Observation}
    candidates::Vector{Float64}
    hidden::HiddenOutcomes
    reveal_order::Vector{Float64}
    const initial_observed::Vector{Observation}
    const initial_hidden::Dict{Float64,Vector{Float64}}
end

const N_INITIAL_LENGTHS = 3

function ReplaySession(records::AbstractVector{PendulumRecord}; n_initial::Integer = N_INITIAL_LENGTHS)
    lengths = sort!(unique(r.length_m for r in records))
    1 <= n_initial < length(lengths) || throw(ArgumentError("n_initial must leave at least one candidate"))
    start = Set(lengths[1:n_initial])
    observed = [Observation(r.length_m, r.period_s) for r in records if r.length_m in start]
    hidden = Dict{Float64,Vector{Float64}}()
    for r in records
        r.length_m in start || push!(get!(hidden, r.length_m, Float64[]), r.period_s)
    end
    initial_hidden = Dict(k => copy(v) for (k, v) in hidden)
    return ReplaySession(observed, sort!(collect(keys(hidden))), HiddenOutcomes(hidden),
                         Float64[], copy(observed), initial_hidden)
end

ReplaySession() = ReplaySession(validate_pendulum(load_pendulum()))

"Restore the exact initial state."
function reset!(s::ReplaySession)
    s.observed = copy(s.initial_observed)
    s.hidden = HiddenOutcomes(Dict(k => copy(v) for (k, v) in s.initial_hidden))
    s.candidates = sort!(collect(keys(s.hidden.by_x)))
    empty!(s.reveal_order)
    return s
end

"""
    reveal!(s, x) -> Vector{Observation}

Reveal every reported observation at recorded length `x`. `x` must be a remaining
candidate; no value is generated or interpolated for any other length.
"""
function reveal!(s::ReplaySession, x::Real)
    xf = Float64(x)
    xf in s.candidates || throw(ArgumentError("$x is not a remaining recorded length"))
    ys = pop!(s.hidden.by_x, xf)
    new = [Observation(xf, y) for y in ys]
    append!(s.observed, new)
    filter!(!=(xf), s.candidates)
    push!(s.reveal_order, xf)
    return new
end

lengths_measured(s::ReplaySession) = length(unique(o.x for o in s.observed))
observation_count(s::ReplaySession) = length(s.observed)

"""
    engine_inputs(s) -> (; x, y, candidate_x)

Everything the numerical engine may see: observed pairs and remaining candidate x values.
"""
engine_inputs(s::ReplaySession) = (
    x = [o.x for o in s.observed],
    y = [o.y for o in s.observed],
    candidate_x = copy(s.candidates),
)

"JSON-safe view for the browser. Contains no unrevealed outcome."
public_state(s::ReplaySession) = (
    observed = [(x = o.x, y = o.y) for o in s.observed],
    candidate_x = copy(s.candidates),
    revealed_order = copy(s.reveal_order),
    lengths_measured = lengths_measured(s),
    observations = observation_count(s),
    remaining_lengths = length(s.candidates),
)

"""
    recommend(s; kwargs...) -> analysis

Demo adapter: runs the scientific core on `engine_inputs(s)` only.
"""
recommend(s::ReplaySession; kwargs...) =
    let inp = engine_inputs(s)
        analyze(inp.x, inp.y, inp.candidate_x; x_unit = "m", y_unit = "s", kwargs...)
    end
