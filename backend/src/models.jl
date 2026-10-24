# Candidate model families, grouping by distinct setting, least-squares fits and
# leave-one-setting-out validation. No HTTP, no frontend, no hidden outcomes.

"A two-parameter family y = a·f(x) + b."
struct ModelFamily
    id::Symbol
    name::String
    formula::String
    note::String
    feature::Function
end

const MODEL_FAMILIES = (
    ModelFamily(:linear, "Linear", "y = a·x + b", "", identity),
    ModelFamily(:sqrt, "Square root", "y = a·√x + b", "", sqrt),
    ModelFamily(:restricted_quadratic, "Restricted quadratic", "y = a·x² + b",
                "Restricted quadratic: no separate linear term.", x -> x^2),
)

function model_family(id::Symbol)
    for fam in MODEL_FAMILIES
        fam.id == id && return fam
    end
    throw(ArgumentError("unknown model family $id"))
end

"""
Observations grouped by distinct x. Fitting uses one mean per setting with equal weight,
so a setting measured five times counts the same as one measured once.
"""
struct SettingMeans
    x::Vector{Float64}     # sorted distinct settings
    mean::Vector{Float64}
    n::Vector{Int}
    ss::Vector{Float64}    # within-setting sum of squared deviations from the mean
end

function group_settings(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    order = sortperm(x)
    xs, means, ns, sss = Float64[], Float64[], Int[], Float64[]
    i = 1
    while i <= length(order)
        j = i
        while j < length(order) && x[order[j+1]] == x[order[i]]
            j += 1
        end
        vals = Float64[y[order[k]] for k in i:j]
        m = mean(vals)
        push!(xs, x[order[i]]); push!(means, m); push!(ns, length(vals))
        push!(sss, sum(abs2, vals .- m))
        i = j + 1
    end
    return SettingMeans(xs, means, ns, sss)
end

"Result of fitting one family. When `ok` is false, `a` and `b` are meaningless and never reported."
struct LineFit
    ok::Bool
    a::Float64
    b::Float64
    code::Symbol
    message::String
end

fit_failure(code::Symbol, message::String) = LineFit(false, NaN, NaN, code, message)

"""
    fit_family(fam, x, y) -> LineFit

Least-squares fit of y = a·f(x) + b with equal weight per point (each point is one
setting mean). The transformed column f(x) is centred and scaled before a QR solve;
the transform is applied first, so the family is unchanged. Coefficients are reported
for the original formula.
"""
function fit_family(fam::ModelFamily, x::AbstractVector{Float64}, y::AbstractVector{Float64})
    length(x) >= 2 ||
        return fit_failure(:too_few_settings, "$(fam.name): at least two distinct settings are needed to fit two parameters.")
    f = fam.feature.(x)
    all(isfinite, f) ||
        return fit_failure(:nonfinite_feature, "$(fam.name): the transformed input in $(fam.formula) overflows for some x, so this family cannot be fitted to these settings.")
    # Divide by max|f| before centring so squaring cannot overflow for large finite f.
    c = maximum(abs, f)
    fs = f ./ c
    μ = mean(fs)
    s = sqrt(mean(abs2, fs .- μ))
    c > 0 && s > 1e-12 * abs(μ) ||
        return fit_failure(:degenerate_range, "$(fam.name): the settings are too close together to separate slope from intercept. Measure over a wider range of x.")
    A = hcat(ones(length(f)), (fs .- μ) ./ s)
    F = qr(A)
    R = F.R
    abs(R[2, 2]) > 1e-10 * abs(R[1, 1]) ||
        return fit_failure(:rank_deficient, "$(fam.name): the design is numerically rank-deficient. Measure over a wider range of x.")
    β = F \ y
    a = β[2] / s / c
    b = β[1] - β[2] * μ / s
    (isfinite(a) && isfinite(b)) ||
        return fit_failure(:nonfinite_coefficients, "$(fam.name): the fit produced non-finite coefficients.")
    all(isfinite, a .* f .+ b) ||
        return fit_failure(:nonfinite_predictions, "$(fam.name): fitted values are not finite at the measured settings.")
    return LineFit(true, a, b, :ok, "")
end

predict(fam::ModelFamily, fit::LineFit, x::Real) = fit.a * fam.feature(Float64(x)) + fit.b

"""
    grouped_cv(fam, g) -> (; ok, predictions, mse, code, message)

Leave one distinct setting out at a time: every observation at that setting is removed,
the family is refitted on the remaining setting means, and the held-out mean is
predicted. Needs at least three settings so each training fold has two.
"""
function grouped_cv(fam::ModelFamily, g::SettingMeans)
    G = length(g.x)
    preds = fill(NaN, G)
    G >= 3 || return (ok = false, predictions = preds, mse = NaN, code = :too_few_settings,
                      message = "$(fam.name): grouped validation needs at least three distinct settings.")
    for k in 1:G
        keep = [i for i in 1:G if i != k]
        fit = fit_family(fam, g.x[keep], g.mean[keep])
        fit.ok || return (ok = false, predictions = preds, mse = NaN, code = fit.code,
                          message = "Validation fold without x = $(g.x[k]): " * fit.message)
        p = predict(fam, fit, g.x[k])
        isfinite(p) || return (ok = false, predictions = preds, mse = NaN, code = :nonfinite_predictions,
                               message = "$(fam.name): validation prediction at x = $(g.x[k]) is not finite.")
        preds[k] = p
    end
    return (ok = true, predictions = preds, mse = mean(abs2, g.mean .- preds), code = :ok, message = "")
end
