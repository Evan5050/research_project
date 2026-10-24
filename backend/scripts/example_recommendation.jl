# Observed data -> recommendation -> frozen predictions -> reveal -> refit, on the built-in
# pendulum replay. Uses only the scientific core and the replay adapter (no HTTP).
#   julia --project=backend backend/scripts/example_recommendation.jl

using NextLab
using NextLab: ReplaySession, recommend, freeze_predictions, reveal!, fmt, fmt_support

function show_models(a)
    for m in a.models
        line = m.fitted ? "a = $(fmt(m.a)), b = $(fmt(m.b))" : "not fitted: $(m.failure)"
        cv = m.grouped_cv_rmse === nothing ? "n/a" : "$(fmt(m.grouped_cv_rmse)) s"
        flag = m.strongly_down_weighted === true ? "  [strongly down-weighted]" : ""
        println("  $(rpad(m.name, 21)) $(rpad(m.formula, 14)) $line; grouped-validation RMSE $cv; support $(m.support === nothing ? "n/a" : fmt_support(m.support))$flag")
    end
end

s = ReplaySession()
a = recommend(s)
println("Observed: $(a.data.n_settings) lengths, $(a.data.n_observations) reported period observations (revision $(first(a.data.revision, 12)))")
println("Noise: $(a.noise.source); individual SD $(fmt(a.noise.sd_individual)) s; setting-mean SD $(fmt(a.noise.representative_mean_sd)) s")
show_models(a)
println("\nRecommendation ($(a.recommendation.kind)): $(a.recommendation.x) m\n  ", a.explanation)

frozen = freeze_predictions(a)
println("\nFrozen at $(frozen.created_at):")
for m in frozen.models
    m.predicted_y === nothing || println("  $(rpad(m.name, 21)) predicts $(fmt(m.predicted_y)) s")
end

revealed = reveal!(s, frozen.x)
ȳ = sum(o.y for o in revealed) / length(revealed)
println("\nRevealed $(length(revealed)) recorded periods at $(frozen.x) m: ", join((o.y for o in revealed), ", "), " (mean $(fmt(ȳ)) s)")
for m in frozen.models
    m.predicted_y === nothing || println("  $(rpad(m.name, 21)) error $(fmt(ȳ - m.predicted_y)) s")
end

a2 = recommend(s)
println("\nAfter explicit refit: $(a2.data.n_settings) lengths, $(a2.data.n_observations) observations")
show_models(a2)
println("\nNext recommendation ($(a2.recommendation.kind)): $(a2.recommendation.x) m\n  ", a2.explanation)
