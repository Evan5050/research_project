# Frozen prediction records: what each model committed to before an outcome is revealed.
# Records are immutable values built only from scalars, strings, symbols and tuples, so
# later refits cannot rewrite them.

struct PredictionRecord
    method_version::String
    created_at::String
    data_revision::String
    n_observations::Int
    n_settings::Int
    x::Float64
    units::NamedTuple{(:x, :y),Tuple{String,String}}
    acquisition::NamedTuple
    models::Tuple
    noise::NamedTuple
end

"""
    freeze_predictions(analysis; created_at) -> PredictionRecord

Snapshot the recommended setting, every fitted model's definition, coefficients,
support and prediction there, the noise assumptions and the acquisition method.
"""
function freeze_predictions(a; created_at::AbstractString = string(Dates.now(Dates.UTC)) * "Z")
    a.status == :ok && a.recommendation !== nothing ||
        throw(ArgumentError("predictions can only be frozen for an analysis with a recommendation (status $(a.status))"))
    rec = a.recommendation
    preds = Dict(p.id => p for p in rec.predictions)
    models = Tuple((id = m.id, name = m.name, formula = String(m.formula), note = String(m.note),
                    fitted = m.fitted, a = m.a, b = m.b, support = m.support,
                    strongly_down_weighted = m.strongly_down_weighted,
                    grouped_cv_rmse = m.grouped_cv_rmse, predicted_y = preds[m.id].y) for m in a.models)
    n = a.noise
    noise = (source = n.source, sd_individual = n.sd_individual, df = n.df,
             representative_mean_sd = n.representative_mean_sd, note = String(n.note))
    acquisition = (kind = rec.kind, fallback_reason = rec.fallback_reason, score = rec.score,
                   spread = rec.spread, separation_label = rec.separation.label,
                   separation_ratio = rec.separation.ratio, method = String(rec.method))
    return PredictionRecord(a.method_version, String(created_at), a.data.revision, a.data.n_observations,
                            a.data.n_settings, rec.x, a.units, acquisition, models, noise)
end

JSON.lower(r::PredictionRecord) = (; (f => getfield(r, f) for f in fieldnames(PredictionRecord))...)
