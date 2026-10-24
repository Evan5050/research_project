# Scientific core: observed x/y + feasible candidate x values -> fits, diagnostics,
# relative support, a next-setting recommendation and a plain explanation.
# The method and its limitations are documented in docs/SPEC.md ("Numerical method").

const METHOD_VERSION = "nextlab-core-1"
const STRONG_DOWNWEIGHT = 0.05   # support below this is labelled "strongly down-weighted"
const DOMINANT_WEIGHT = 0.99     # one model at or above this -> space-filling fallback
const AGREE_RTOL = 1e-6          # weighted spread below this × response scale -> "agree"
const SEPARATION_RATIO = 2.0     # spread / setting-mean SD below this -> "inconclusive"
const ADEQUACY_LIMIT = 3.0       # standardized RMS residual above this -> conflicts with noise
const FLOOR_REL = 1e-12          # numerical floor on s², relative to the mean square response
const TIE_RTOL = 1e-9            # scores within this relative gap are ties -> smallest x

diagnostic(level::Symbol, code::Symbol, message::AbstractString) = (level = level, code = code, message = String(message))

nothing_if_nan(v::Real) = isfinite(v) ? Float64(v) : nothing

function fmt(v::Real)
    v == 0 && return "0"
    s = string(round(Float64(v); sigdigits = 3))
    return endswith(s, ".0") ? s[1:end-2] : s
end

with_unit(v, unit) = isempty(unit) ? fmt(v) : "$(fmt(v)) $unit"

listed(idx) = join(first(idx, 10), ", ") * (length(idx) > 10 ? ", …" : "")

"Canonical SHA-256 of the observed records, independent of row order."
function data_revision(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    rows = sort!([(Float64(a), Float64(b)) for (a, b) in zip(x, y)])
    return bytes2hex(sha256(join(("$(repr(a)),$(repr(b))" for (a, b) in rows), "\n")))
end

"""
    noise_estimate(g, response_sd) -> NamedTuple

Response variability from within-setting repeats when any exist (pooled, assuming
independent observations with one constant variance). Otherwise a user-stated response
SD, otherwise unknown. Never estimated from unrevealed data: only `g` is used.
"""
function noise_estimate(g::SettingMeans, response_sd::Union{Nothing,Real})
    df = sum(g.n .- 1; init = 0)
    with_repeats = count(>=(2), g.n)
    if df >= 1
        source = :repeats
        var_obs = sum(g.ss) / df
        note = "Pooled from repeats at $with_repeats setting(s) ($df degrees of freedom), assuming independent observations with one constant variance."
    elseif response_sd !== nothing
        source = :user
        var_obs = Float64(response_sd)^2
        note = "No repeated settings; using the stated response SD. Assumes independent observations with one constant variance."
    else
        return (source = :unknown, sd_individual = nothing, df = 0, settings_with_repeats = 0,
                mean_sd_by_setting = Union{Nothing,Float64}[nothing for _ in g.n],
                representative_mean_variance = nothing, representative_mean_sd = nothing,
                note = "Noise unknown: no repeated settings and no stated response SD. Separation and fit adequacy are not assessed.")
    end
    mean_var = var_obs * mean(1 ./ g.n)
    return (source = source, sd_individual = sqrt(var_obs), df = df, settings_with_repeats = with_repeats,
            mean_sd_by_setting = Union{Nothing,Float64}[sqrt(var_obs / n) for n in g.n],
            representative_mean_variance = mean_var, representative_mean_sd = sqrt(mean_var),
            note = note * " Uncertainty of a setting mean is SD/√n per setting; the representative value averages σ²/n over measured settings.")
end

"""
    support_weights(L, mean_var, floor) -> (; weights, s2, s2_source)

Heuristic relative support from grouped validation MSE `L` (nothing = invalid model):
w ∝ exp(-(L - min L) / (2 s²)), s² = max(min L, setting-mean variance, floor).
Not a probability that a model is true.
"""
function support_weights(L::AbstractVector, mean_var::Union{Nothing,Float64}, floor::Float64)
    valid = [l !== nothing && isfinite(l) for l in L]
    any(valid) || return (weights = Union{Nothing,Float64}[nothing for _ in L], s2 = nothing, s2_source = :none)
    Lmin = minimum(L[i] for i in eachindex(L) if valid[i])
    terms = [(Lmin, :min_validation_mse), (something(mean_var, -Inf), :setting_mean_variance), (floor, :numerical_floor)]
    s2, src = terms[argmax(first.(terms))]
    raw = [valid[i] ? exp(-(L[i] - Lmin) / (2s2)) : 0.0 for i in eachindex(L)]
    tot = sum(raw)
    return (weights = Union{Nothing,Float64}[valid[i] ? raw[i] / tot : nothing for i in eachindex(L)],
            s2 = s2, s2_source = src)
end

"Support-weighted variance of model predictions at one setting, plus each model's share."
function disagreement(preds::AbstractVector{Float64}, w::AbstractVector{Float64})
    all(isfinite, preds) || return (score = nothing, spread = nothing, shares = nothing)
    μ = sum(w .* preds)
    parts = w .* (preds .- μ) .^ 2
    score = sum(parts)
    isfinite(score) || return (score = nothing, spread = nothing, shares = nothing)
    return (score = score, spread = sqrt(score), shares = score > 0 ? parts ./ score : zero(parts))
end

"Deterministic maximin: the candidate farthest (in x) from every measured setting; ties -> smallest x."
function maximin_choice(candidates::AbstractVector{Float64}, measured::AbstractVector{Float64})
    dists = [minimum(abs(c - m) for m in measured) for c in candidates]
    best = maximum(dists)
    i = findfirst(d -> d >= best * (1 - TIE_RTOL), dists)   # candidates are sorted ascending
    return candidates[i], dists[i]
end

"""
    analyze(x, y, candidate_x; response_sd = nothing, x_unit = "", y_unit = "")

Observed records `x`, `y` and feasible candidate settings only. Repeated x values are
separate observations. Returns a JSON-serialisable NamedTuple; failures are reported as
diagnostics with a status, never as NaN fits.
"""
function analyze(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, candidate_x::AbstractVector{<:Real};
                 response_sd::Union{Nothing,Real} = nothing, x_unit::AbstractString = "", y_unit::AbstractString = "")
    units = (x = String(x_unit), y = String(y_unit))
    diagnostics = NamedTuple[]
    base = (method_version = METHOD_VERSION, units = units, diagnostics = diagnostics)

    # ---- input validation -------------------------------------------------------------
    if length(x) != length(y)
        push!(diagnostics, diagnostic(:error, :length_mismatch, "x has $(length(x)) values but y has $(length(y)); each observation needs both."))
    else
        bad_x = findall(v -> !(isfinite(v) && v > 0), x)
        isempty(bad_x) || push!(diagnostics, diagnostic(:error, :invalid_x,
            "x must be positive and finite. Rows $(listed(bad_x)) are not."))
        bad_y = findall(v -> !isfinite(v), y)
        isempty(bad_y) || push!(diagnostics, diagnostic(:error, :invalid_y,
            "y must be finite. Rows $(listed(bad_y)) are not."))
    end
    if response_sd !== nothing && !(isfinite(response_sd) && response_sd > 0)
        push!(diagnostics, diagnostic(:error, :invalid_response_sd, "A stated response SD must be positive and finite; got $(response_sd)."))
    end
    isempty(x) && push!(diagnostics, diagnostic(:error, :no_observations, "There are no observations yet."))
    if any(d -> d.level == :error, diagnostics)
        return (; base..., status = :invalid_input, data = nothing, noise = nothing, models = [],
                support = nothing, recommendation = nothing, candidate_scores = [], all_models_inadequate = nothing,
                explanation = "The data cannot be analysed yet: " * join((d.message for d in diagnostics if d.level == :error), " "))
    end
    bad_c = [c for c in candidate_x if !(isfinite(c) && c > 0)]
    isempty(bad_c) || push!(diagnostics, diagnostic(:warning, :invalid_candidates,
        "Ignored $(length(bad_c)) candidate setting(s) that are not positive and finite."))
    feasible = sort!(unique(Float64[c for c in candidate_x if isfinite(c) && c > 0]))

    # ---- grouping and noise ---------------------------------------------------------------
    g = group_settings(x, y)
    G = length(g.x)
    noise = noise_estimate(g, response_sd)
    if response_sd !== nothing && noise.source == :repeats
        push!(diagnostics, diagnostic(:info, :response_sd_not_used, "Repeats exist, so the stated response SD is not used; variability is estimated from the repeats."))
    end
    data = (n_observations = length(x), n_settings = G, revision = data_revision(x, y),
            settings = [(x = g.x[i], mean = g.mean[i], n = g.n[i],
                         repeat_sd = g.n[i] >= 2 ? sqrt(g.ss[i] / (g.n[i] - 1)) : nothing,
                         mean_sd = noise.mean_sd_by_setting[i]) for i in 1:G])
    yscale = max(1.0, maximum(abs, g.mean))
    if G >= 2 && maximum(g.mean) - minimum(g.mean) <= AGREE_RTOL * yscale
        push!(diagnostics, diagnostic(:warning, :constant_response, "The mean response is the same at every setting, so the models cannot be told apart from these data."))
    end

    # ---- fits and grouped validation ------------------------------------------------------
    fits = [fit_family(fam, g.x, g.mean) for fam in MODEL_FAMILIES]
    cvs = [G >= 3 && fits[i].ok ? grouped_cv(MODEL_FAMILIES[i], g) : nothing for i in eachindex(fits)]
    for (fam, fit, cv) in zip(MODEL_FAMILIES, fits, cvs)
        fit.ok || G < 2 || push!(diagnostics, diagnostic(:warning, fit.code, fit.message))
        cv === nothing || cv.ok || push!(diagnostics, diagnostic(:warning, cv.code, cv.message))
    end
    L = Union{Nothing,Float64}[cv !== nothing && cv.ok ? cv.mse : nothing for cv in cvs]
    floor = FLOOR_REL * max(1.0, mean(abs2, g.mean))
    support = G >= 3 ? support_weights(L, noise.representative_mean_variance, floor) :
                       (weights = Union{Nothing,Float64}[nothing for _ in L], s2 = nothing, s2_source = :none)

    # Conservative heuristic adequacy check against the noise estimate.
    function adequacy(i)
        fits[i].ok || return (assessed = false, standardized_rms = nothing, conflicts_with_noise = nothing, note = "Not fitted.")
        noise.source == :unknown &&
            return (assessed = false, standardized_rms = nothing, conflicts_with_noise = nothing, note = "Noise unknown.")
        noise.sd_individual > 0 ||
            return (assessed = false, standardized_rms = nothing, conflicts_with_noise = nothing, note = "Repeats show zero variability.")
        fam = MODEL_FAMILIES[i]
        r = [(g.mean[k] - predict(fam, fits[i], g.x[k])) / (noise.sd_individual / sqrt(g.n[k])) for k in 1:G]
        z = sqrt(mean(abs2, r))
        return (assessed = true, standardized_rms = z, conflicts_with_noise = z > ADEQUACY_LIMIT,
                note = "Heuristic: RMS of (setting mean − fitted value) / setting-mean SD; above $(fmt(ADEQUACY_LIMIT)) is flagged.")
    end
    adequacies = [adequacy(i) for i in eachindex(fits)]

    models = [begin
        fam, fit, cv, w = MODEL_FAMILIES[i], fits[i], cvs[i], support.weights[i]
        (id = fam.id, name = fam.name, formula = fam.formula, note = fam.note,
         fitted = fit.ok, a = fit.ok ? fit.a : nothing, b = fit.ok ? fit.b : nothing,
         failure = fit.ok ? nothing : fit.message,
         fit_rmse_setting_means = fit.ok ? sqrt(mean(abs2, g.mean .- predict.(Ref(fam), Ref(fit), g.x))) : nothing,
         grouped_cv_mse = L[i], grouped_cv_rmse = L[i] === nothing ? nothing : sqrt(L[i]),
         support = w, strongly_down_weighted = w === nothing ? nothing : w < STRONG_DOWNWEIGHT,
         adequacy = adequacies[i])
    end for i in eachindex(fits)]

    assessed = [a for (a, m) in zip(adequacies, models) if m.support !== nothing && a.assessed]
    all_inadequate = isempty(assessed) ? nothing : all(a -> a.conflicts_with_noise, assessed)
    all_inadequate === true && push!(diagnostics, diagnostic(:warning, :no_adequate_model,
        "Heuristic check: every fitted model misses the observed setting means by more than $(fmt(ADEQUACY_LIMIT)) setting-mean SDs on average. No candidate fits adequately."))

    result(status, rec, scores, explanation) = (; base..., status = status, data = data, noise = noise, models = models,
        support = (method = "w ∝ exp(-(L − min L) / (2 s²)); L = grouped validation MSE; s² = max(min L, setting-mean variance, floor). Relative support, not probability of truth.",
                   s2 = support.s2, s2_source = support.s2_source, numerical_floor = floor),
        recommendation = rec, candidate_scores = scores, all_models_inadequate = all_inadequate, explanation = explanation)

    if G < 3
        push!(diagnostics, diagnostic(:error, :too_few_settings, "Comparison and recommendation need at least three distinct x settings; there are $G."))
        return result(:insufficient_data, nothing, [],
            "Measure at least $(3 - G) more distinct setting(s) before models can be compared. Repeats at one x count as observations but not as new settings.")
    end
    valid = [w !== nothing for w in support.weights]
    if !any(valid)
        return result(:no_valid_fit, nothing, [], "None of the three families could be fitted and validated on these settings. See diagnostics.")
    end

    # ---- acquisition over feasible, unmeasured settings ----------------------------------
    unmeasured = [c for c in feasible if !(c in g.x)]
    vi = findall(valid)
    w = Float64[support.weights[i] for i in vi]
    cand_preds = Dict(c => Float64[predict(MODEL_FAMILIES[i], fits[i], c) for i in vi] for c in unmeasured)
    scored = [(c, disagreement(cand_preds[c], w)) for c in unmeasured]
    scores = [(x = c, score = d.score, spread = d.spread) for (c, d) in scored]
    usable = [c for (c, d) in scored if d.score !== nothing]
    length(usable) < length(unmeasured) && push!(diagnostics, diagnostic(:warning, :nonfinite_candidate_predictions,
        "Skipped $(length(unmeasured) - length(usable)) candidate setting(s) where a model's prediction is not finite."))
    if isempty(usable)
        msg = isempty(feasible) ? "No feasible candidate settings were supplied." :
              "Every feasible candidate setting has already been measured (or has no finite predictions). The planned sequence is complete."
        return result(:no_candidates, nothing, scores, msg)
    end

    best_score = maximum(d.score for (c, d) in scored if d.score !== nothing)
    chosen_dis = first(c for (c, d) in scored if d.score !== nothing && d.score >= best_score * (1 - TIE_RTOL))
    lead = vi[argmax(w)]
    fallback = maximum(w) >= DOMINANT_WEIGHT ? :dominant_model :
               sqrt(best_score) <= AGREE_RTOL * yscale ? :predictions_agree : nothing
    if fallback === nothing
        chosen, kind, dist = chosen_dis, :disagreement, nothing
    else
        chosen, dist = maximin_choice(usable, g.x)
        kind = :space_filling
    end
    d = disagreement(cand_preds[chosen], w)
    mean_sd = noise.representative_mean_sd
    sep = if mean_sd === nothing
        (ratio = nothing, label = :unassessed, setting_mean_sd = nothing, note = "Noise unknown, so the spread cannot be compared with measurement uncertainty.")
    elseif mean_sd == 0
        (ratio = nothing, label = :unassessed, setting_mean_sd = 0.0, note = "Repeats show zero variability, so the spread cannot be compared with measurement uncertainty.")
    else
        ratio = d.spread / mean_sd
        (ratio = ratio, label = ratio < SEPARATION_RATIO ? :inconclusive : :separated, setting_mean_sd = mean_sd,
         note = ratio < SEPARATION_RATIO ?
            "Predicted spread is under $(fmt(SEPARATION_RATIO))× the uncertainty of a setting mean; the next result may not distinguish the models." :
            "Predicted spread is at least $(fmt(SEPARATION_RATIO))× the uncertainty of a setting mean; the result may help distinguish the leading models (heuristic, not a guarantee).")
    end
    preds_at = Dict(zip(vi, cand_preds[chosen]))
    rec = (x = chosen, kind = kind, fallback_reason = fallback, distance_to_nearest_measured = dist,
           score = d.score, spread = d.spread,
           predictions = [(id = MODEL_FAMILIES[i].id, name = MODEL_FAMILIES[i].name, y = get(preds_at, i, nothing),
                           support = support.weights[i],
                           share_of_spread = haskey(preds_at, i) ? d.shares[findfirst(==(i), vi)] : nothing)
                          for i in eachindex(MODEL_FAMILIES)],
           separation = sep, feasible_range = isempty(feasible) ? nothing : (lo = first(feasible), hi = last(feasible)),
           n_unmeasured = length(unmeasured),
           method = kind == :disagreement ?
               "Disagreement sampling: the unmeasured setting with the largest support-weighted variance of model predictions. Not proven optimal design or expected information gain." :
               "Space-filling validation: the unmeasured setting farthest in x from every measured setting (maximin). Not chosen to distinguish models.")
    return result(:ok, rec, scores, explain(rec, models, noise, units, all_inadequate, MODEL_FAMILIES[lead].name))
end

"Support shown without rounding near-certain or near-zero values to 1 or 0."
fmt_support(w::Real) = w >= 0.999 ? "> 0.999" : w < 0.001 ? "< 0.001" : string(round(w; digits = 3))

function explain(rec, models, noise, units, all_inadequate, lead_name)
    xs = with_unit(rec.x, units.x)
    preds = join(("$(p.name) $(with_unit(p.y, units.y)) (support $(fmt_support(p.support)))" for p in rec.predictions if p.y !== nothing), "; ")
    top = argmax(p -> something(p.share_of_spread, -1.0), rec.predictions)
    source = "$(round(Int, 100 * top.share_of_spread))% of the weighted spread comes from $(top.name) (support $(fmt_support(top.support)))"
    parts = String[]
    if rec.kind == :disagreement
        push!(parts, "Measure next at x = $xs. Of $(rec.n_unmeasured) unmeasured setting(s), this is where the support-weighted predictions disagree most (weighted spread $(with_unit(rec.spread, units.y))); $source.")
    else
        why = rec.fallback_reason == :dominant_model ?
            "$lead_name holds at least $(fmt(DOMINANT_WEIGHT)) of the relative support" :
            "the models' predictions essentially agree at every unmeasured setting"
        push!(parts, "Measure next at x = $xs as a space-filling validation point: it is the unmeasured setting farthest from any measured setting ($(with_unit(rec.distance_to_nearest_measured, units.x)) away). Because $why, disagreement is not used to choose; this point checks the models where data are sparse and is not chosen to distinguish them.")
    end
    push!(parts, "Predictions at that setting: $preds.")
    if rec.kind == :disagreement
        push!(parts, rec.separation.note)
        top.support < STRONG_DOWNWEIGHT && push!(parts,"Because that spread comes mostly from a strongly down-weighted model, treat this as weak evidence.")
    elseif rec.separation.ratio !== nothing && rec.spread > 0
        push!(parts, "For reference, the weighted spread here is $(fmt(rec.separation.ratio))× the uncertainty of a setting mean, and $source.")
    end
    if any(m -> m.strongly_down_weighted === true, models)
        names = join((m.name for m in models if m.strongly_down_weighted === true), ", ")
        push!(parts, "Strongly down-weighted (support below $(fmt(STRONG_DOWNWEIGHT))): $names. Support is a heuristic from grouped validation error, not a probability that a model is true.")
    end
    all_inadequate === true && push!(parts, "Heuristic check: no candidate fits the observed setting means within the measured variability.")
    noise.source == :unknown && push!(parts, noise.note)
    return join(parts, " ")
end
