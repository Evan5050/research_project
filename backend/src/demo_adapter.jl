# Stateless adapter for the built-in pendulum demo. It sits outside the scientific core:
# the core never sees this table. Unrevealed periods leave this file only through
# `demo_reveal`, one recorded length at a time.

const DEMO_DATASET_ID = "fastR2-pendulum@350f183b"
const DEMO_RECORDS = Ref{Vector{PendulumRecord}}()

demo_records() = (isassigned(DEMO_RECORDS) || (DEMO_RECORDS[] = validate_pendulum(load_pendulum())); DEMO_RECORDS[])

demo_lengths() = sort!(unique(r.length_m for r in demo_records()))
demo_initial_lengths() = demo_lengths()[1:N_INITIAL_LENGTHS]
demo_candidate_lengths() = demo_lengths()[N_INITIAL_LENGTHS+1:end]

"Errors (field, message) for a client-supplied revealed list; empty when valid."
function demo_revealed_errors(revealed_x::AbstractVector{Float64})
    errs = Tuple{String,String}[]
    cands = demo_candidate_lengths()
    for (i, x) in enumerate(revealed_x)
        x in cands || push!(errs, ("context.revealed_x[$i]", "$x m is not a recorded demo length that can be revealed."))
    end
    allunique(revealed_x) || push!(errs, ("context.revealed_x", "A recorded length can be revealed only once."))
    return errs
end

"Observed rows for the declared start plus the revealed lengths (all reported periods at each)."
function demo_observed(revealed_x::AbstractVector{Float64})
    keep = Set(vcat(demo_initial_lengths(), revealed_x))
    return [(x = r.length_m, y = r.period_s) for r in demo_records() if r.length_m in keep]
end

demo_remaining(revealed_x::AbstractVector{Float64}) = [x for x in demo_candidate_lengths() if !(x in revealed_x)]

"Reported periods at one remaining recorded length. Never generates or interpolates values."
function demo_reveal(revealed_x::AbstractVector{Float64}, x::Float64)
    x in demo_remaining(revealed_x) || throw(ArgumentError("$x m is not a remaining recorded length"))
    return [(x = r.length_m, y = r.period_s) for r in demo_records() if r.length_m == x]
end
