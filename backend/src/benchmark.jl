# Simulation benchmark, as declared in docs/BENCHMARK.md. The generating relationship is
# used only to build the observation table and in the evaluator. Policies see observed
# rows, remaining candidate x values and the starting settings.

module Benchmark

using Random
using Statistics
using ..NextLab: analyze, ensemble_predict, maximin_choice, METHOD_VERSION

const PROTOCOL_VERSION = "nextlab-benchmark-1"
const CANDIDATES = collect(range(0.2, 1.2; length = 21))
const TEST_X = [0.2 + (i - 0.5) * 0.005 for i in 1:200]
const REPS = 3
const N_START = 3
const N_FINAL = 8
const TIE_TOL = 1e-10
const BOOT_B = 2000
const BOOT_SEED = 20261024
const REL_GUARD = 1e-6
const PREPLANNED_TARGETS = [0.3, 0.5, 0.7, 0.9, 1.1]

const TRUTHS = (
    (id = "T1_sqrt", formula = "2*sqrt(x)", f = x -> 2 * sqrt(x)),
    (id = "T2_linear", formula = "1.6*x+0.5", f = x -> 1.6 * x + 0.5),
    (id = "T3_quadratic", formula = "1.4*x^2+0.6", f = x -> 1.4 * x^2 + 0.6),
    (id = "T4_saturating", formula = "1.5*(1-exp(-3*x))+0.2 (outside all families)", f = x -> 1.5 * (1 - exp(-3 * x)) + 0.2),
)
const NOISE_SDS = (0.03, 0.10)
const LAYOUTS = (
    (id = "L1_middle_cluster", start = CANDIDATES[[10, 11, 12]]),
    (id = "L2_ends_middle", start = CANDIDATES[[1, 11, 21]]),
)
const POLICIES = (:nextlab, :random, :preplanned_even, :endpoint_maximin)
const BASELINES = (:random, :preplanned_even, :endpoint_maximin)

const CONDITIONS = let k = 0
    [(index = (k += 1), truth = t, sd = s, layout = l) for t in TRUTHS for s in NOISE_SDS for l in LAYOUTS]
end

# ---- observations: the only place the truth meets noise -----------------------------------

"Per-seed standard-normal draws, shared by every policy and condition with this seed."
noise_draws(seed::Integer) = randn(Xoshiro(seed), length(CANDIDATES), REPS)

struct ObservationTable
    y::Matrix{Float64}      # candidate × replicate; read only through `request!`
end
ObservationTable(truth_f, sd::Real, seed::Integer) = ObservationTable(truth_f.(CANDIDATES) .+ sd .* noise_draws(seed))

mutable struct Oracle
    table::ObservationTable
    requested::Vector{Int}
end
Oracle(t::ObservationTable) = Oracle(t, Int[])

"Return the 3 observations at setting `x`, charging one setting to the budget."
function request!(o::Oracle, x::Float64)
    j = findfirst(==(x), CANDIDATES)
    j === nothing && throw(ArgumentError("$x is not a candidate setting"))
    j in o.requested && throw(ArgumentError("setting $x already measured"))
    push!(o.requested, j)
    return o.table.y[j, :]
end

# ---- policies: see only (x, y, remaining, start) plus their own context ----------------------

function preplanned_plan(start::AbstractVector{Float64})
    used = Set(start)
    plan = Float64[]
    for t in PREPLANNED_TARGETS
        free = [c for c in CANDIDATES if !(c in used)]
        d = abs.(free .- t)
        c = free[findfirst(<=(minimum(d) + 1e-9), d)]      # ascending: ties -> smaller x
        push!(plan, c); push!(used, c)
    end
    return plan
end

const PLANS = Dict(l.id => preplanned_plan(l.start) for l in LAYOUTS)

choice(x; kind, fallback = "", failure = false) = (x = x, kind = kind, fallback = fallback, failure = failure)

function choose(policy::Symbol, v, ctx)
    if policy == :nextlab
        a = analyze(v.x, v.y, CANDIDATES)
        if a.status == :ok
            r = a.recommendation
            return choice(r.x; kind = String(r.kind), fallback = r.fallback_reason === nothing ? "" : String(r.fallback_reason))
        end
        return choice(maximin_choice(v.remaining, unique(v.x))[1]; kind = "failure_maximin", fallback = String(a.status), failure = true)
    elseif policy == :random
        return choice(rand(ctx.rng, v.remaining); kind = "random")
    elseif policy == :preplanned_even
        return choice(ctx.plan[ctx.step]; kind = "preplanned")
    elseif policy == :endpoint_maximin
        for e in (first(CANDIDATES), last(CANDIDATES))
            e in v.remaining && return choice(e; kind = "endpoint")
        end
        return choice(maximin_choice(v.remaining, unique(v.x))[1]; kind = "maximin")
    end
    throw(ArgumentError("unknown policy $policy"))
end

# ---- evaluator: the only place the noiseless truth at test inputs is used ---------------------

"Ensemble predicted mean vs the noiseless relationship at the held-out test inputs."
function evaluate(x::Vector{Float64}, y::Vector{Float64}, truth_at_test::Vector{Float64})
    a = analyze(x, y, CANDIDATES)
    pred = ensemble_predict(a, TEST_X)
    sup = [m for m in a.models if m.support !== nothing]
    lead = isempty(sup) ? missing : String(argmax(m -> m.support, sup).id)
    return (rmse = pred === nothing ? missing : sqrt(mean(abs2, pred .- truth_at_test)),
            status = String(a.status),
            max_support = isempty(sup) ? missing : maximum(m.support for m in sup),
            leading_model = lead,
            all_models_inadequate = something(a.all_models_inadequate, missing))
end

function run_policy(cond, seed::Integer, policy::Symbol, table::ObservationTable)
    oracle = Oracle(table)
    rng = Xoshiro(10_000_000 + 1_000 * cond.index + seed)
    plan = PLANS[cond.layout.id]
    truth_at_test = cond.truth.f.(TEST_X)
    x, y = Float64[], Float64[]
    for s in cond.layout.start
        append!(y, request!(oracle, s)); append!(x, fill(s, REPS))
    end
    rows = NamedTuple[]
    for nset in N_START:N_FINAL
        ev = evaluate(x, y, truth_at_test)
        ch = if nset < N_FINAL
            remaining = [c for c in CANDIDATES if !(c in x)]
            choose(policy, (x = copy(x), y = copy(y), remaining = remaining, start = cond.layout.start),
                   (rng = rng, plan = plan, step = nset - N_START + 1))
        else
            choice(missing; kind = "")
        end
        push!(rows, (condition = cond.index, truth = cond.truth.id, noise_sd = cond.sd, layout = cond.layout.id,
                     policy = String(policy), seed = seed, n_settings = nset, n_observations = length(x),
                     rmse_noiseless = ev.rmse, predictor_failed = ev.rmse === missing, analysis_status = ev.status,
                     max_support = ev.max_support, leading_model = ev.leading_model,
                     all_models_inadequate = ev.all_models_inadequate,
                     next_x = ch.x, next_choice = ch.kind, next_fallback_reason = ch.fallback, nextlab_failure = ch.failure))
        if nset < N_FINAL
            append!(y, request!(oracle, ch.x)); append!(x, fill(ch.x, REPS))
        end
    end
    return rows, oracle
end

"Run every (condition, seed, policy). Deterministic for fixed seeds, whatever the thread count."
function run_benchmark(seeds; conditions = CONDITIONS, policies = POLICIES)
    jobs = [(c, s) for c in conditions for s in seeds]
    out = Vector{Vector{NamedTuple}}(undef, length(jobs))
    Threads.@threads for k in eachindex(jobs)
        c, s = jobs[k]
        table = ObservationTable(c.truth.f, c.sd, s)
        out[k] = reduce(vcat, [first(run_policy(c, s, p, table)) for p in policies])
    end
    return [r for rows in out for r in rows]
end

# ---- summaries -----------------------------------------------------------------------------

q(v, p) = isempty(v) ? missing : quantile(v, p)

function summarize(runs)
    keys_ = unique((r.condition, r.policy, r.n_settings) for r in runs)
    return [begin
        rs = [r for r in runs if (r.condition, r.policy, r.n_settings) == k]
        v = Float64[r.rmse_noiseless for r in rs if r.rmse_noiseless !== missing]
        r1 = first(rs)
        (condition = k[1], truth = r1.truth, noise_sd = r1.noise_sd, layout = r1.layout, policy = k[2],
         n_settings = k[3], n_observations = r1.n_observations, n_runs = length(rs),
         n_predictor_failed = count(r -> r.predictor_failed, rs),
         n_all_models_inadequate = count(r -> r.all_models_inadequate === true, rs),
         mean_rmse = isempty(v) ? missing : mean(v), median_rmse = q(v, 0.5),
         sd_rmse = length(v) > 1 ? std(v) : missing, q10_rmse = q(v, 0.1), q90_rmse = q(v, 0.9))
    end for k in keys_]
end

function bootstrap_indices(n::Integer)
    rng = Xoshiro(BOOT_SEED)
    return rand(rng, 1:n, BOOT_B, n)
end

function paired(runs)
    rows = NamedTuple[]
    idx_cache = Dict{Int,Matrix{Int}}()
    for c in unique(r.condition for r in runs), b in BASELINES, nset in N_START:N_FINAL
        nl = Dict(r.seed => r.rmse_noiseless for r in runs if r.condition == c && r.policy == "nextlab" && r.n_settings == nset)
        bl = Dict(r.seed => r.rmse_noiseless for r in runs if r.condition == c && r.policy == String(b) && r.n_settings == nset)
        isempty(bl) && continue
        seeds = sort(collect(keys(nl)))
        ok = [s for s in seeds if nl[s] !== missing && bl[s] !== missing]
        d = Float64[nl[s] - bl[s] for s in ok]
        n = length(d)
        boot = n == 0 ? Float64[] : let I = get!(() -> bootstrap_indices(n), idx_cache, n)
            [mean(view(d, view(I, i, :))) for i in 1:BOOT_B]
        end
        lo, hi = n == 0 ? (missing, missing) : (quantile(boot, 0.025), quantile(boot, 0.975))
        mb = n == 0 ? missing : mean(bl[s] for s in ok)
        verdict = n == 0 ? "no data" : hi < 0 ? "NextLab better" : lo > 0 ? "NextLab worse" : "no clear difference"
        r1 = first(r for r in runs if r.condition == c)
        push!(rows, (condition = c, truth = r1.truth, noise_sd = r1.noise_sd, layout = r1.layout,
                     baseline = String(b), n_settings = nset, n_observations = nset * REPS,
                     n_pairs = n, n_missing_pairs = length(seeds) - n,
                     mean_diff = n == 0 ? missing : mean(d), median_diff = n == 0 ? missing : median(d),
                     ci95_lo = lo, ci95_hi = hi,
                     wins = count(<(-TIE_TOL), d), ties = count(x -> abs(x) <= TIE_TOL, d), losses = count(>(TIE_TOL), d),
                     mean_baseline_rmse = mb,
                     rel_mean_diff = (mb === missing || mb < REL_GUARD) ? missing : mean(d) / mb,
                     verdict = verdict))
    end
    return rows
end

"Counts of NextLab's step types (disagreement / fallback / failure) per condition."
function nextlab_choice_counts(runs)
    [begin
        rs = [r for r in runs if r.condition == c && r.policy == "nextlab" && r.next_choice != ""]
        r1 = first(rs)
        (condition = c, truth = r1.truth, noise_sd = r1.noise_sd, layout = r1.layout, steps = length(rs),
         disagreement = count(r -> r.next_choice == "disagreement", rs),
         fallback_dominant_model = count(r -> r.next_fallback_reason == "dominant_model", rs),
         fallback_predictions_agree = count(r -> r.next_fallback_reason == "predictions_agree", rs),
         failures = count(r -> r.nextlab_failure, rs))
    end for c in unique(r.condition for r in runs)]
end

end # module Benchmark
