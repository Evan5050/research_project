using NextLab: analyze, freeze_predictions, group_settings, grouped_cv, model_family, maximin_choice,
    disagreement, PredictionRecord, recommend, ReplaySession, reveal!

by_id(a) = Dict(m.id => m for m in a.models)
codes(a) = Set(d.code for d in a.diagnostics)
rec_pred(a, id) = only(p.y for p in a.recommendation.predictions if p.id == id)

const FEATURES = (linear = identity, sqrt = sqrt, restricted_quadratic = x -> x^2)

@testset "scientific core" begin
    @testset "noiseless data: coefficients and held-out predictions recovered" begin
        xs = [0.5, 1.0, 2.0, 4.0, 8.0]
        for (id, f) in pairs(FEATURES)
            y = 1.7 .* f.(xs) .- 0.4
            a = analyze(xs, y, [3.0, 16.0])
            m = by_id(a)[id]
            @test a.status == :ok
            @test m.a ≈ 1.7 atol = 1e-9
            @test m.b ≈ -0.4 atol = 1e-9
            @test m.grouped_cv_rmse < 1e-9
            @test m.support > 0.99
            @test a.recommendation.x == 16.0                     # never measured: held out
            @test rec_pred(a, id) ≈ 1.7 * f(16.0) - 0.4 rtol = 1e-9
            cv = grouped_cv(model_family(id), group_settings(xs, y))
            @test cv.predictions ≈ y rtol = 1e-9                 # each fold predicts its unseen setting
        end
    end

    @testset "matches an independent R lm() fit on setting means" begin
        ref = CSV.File(joinpath(@__DIR__, "fixtures", "r_reference_fits.csv"))
        recs = NextLab.load_pendulum()
        lengths = sort(unique(r.length_m for r in recs))
        for scenario in ("initial3", "all9")
            keep = scenario == "initial3" ? Set(lengths[1:3]) : Set(lengths)
            rows = [r for r in recs if r.length_m in keep]
            a = analyze([r.length_m for r in rows], [r.period_s for r in rows], [100.0])
            for row in ref
                row.scenario == scenario || continue
                m = by_id(a)[Symbol(row.family)]
                @test m.a ≈ row.a rtol = 1e-10
                @test m.b ≈ row.b rtol = 1e-10 atol = 1e-12
            end
        end
    end

    @testset "repeated x values: kept as observations, one equal-weight mean per setting" begin
        x = [1.0, 1.0, 1.0, 2.0, 4.0, 4.0]
        y = [1.0, 2.0, 3.0, 5.0, 7.0, 9.0]
        g = group_settings(x, y)
        @test g.x == [1.0, 2.0, 4.0]
        @test g.mean == [2.0, 5.0, 8.0]
        @test g.n == [3, 1, 2]
        a = analyze(x, y, [8.0])
        @test a.data.n_observations == 6
        @test a.data.n_settings == 3
        # More identical repeats at one setting must not pull the fit toward it.
        a_more = analyze(vcat(x, [1.0, 1.0, 1.0]), vcat(y, [1.0, 2.0, 3.0]), [8.0])
        for id in keys(FEATURES)
            @test by_id(a_more)[id].a ≈ by_id(a)[id].a
            @test by_id(a_more)[id].b ≈ by_id(a)[id].b
        end
        # Row order is irrelevant, including the data revision.
        p = [5, 2, 6, 1, 4, 3]
        @test JSON.json(analyze(x[p], y[p], [8.0])) == JSON.json(a)
    end

    @testset "grouped validation leaves out every replicate of the held-out setting" begin
        fam = model_family(:sqrt)
        x = [1.0, 1.0, 2.0, 2.0, 4.0, 4.0, 8.0, 8.0]
        y = [1.0, 1.2, 1.4, 1.5, 2.0, 2.1, 2.8, 2.9]
        cv = grouped_cv(fam, group_settings(x, y))
        @test length(cv.predictions) == 4                        # folds are settings, not rows
        y2 = copy(y); y2[5] += 5.0                               # change ONE replicate at x = 4
        cv2 = grouped_cv(fam, group_settings(x, y2))
        @test cv2.predictions[3] == cv.predictions[3]            # its sibling did not leak into training
        @test all(cv2.predictions[[1, 2, 4]] .!= cv.predictions[[1, 2, 4]])
    end

    @testset "invalid input returns diagnostics, never NaN fits" begin
        for (x, y, code) in (([1.0, 0.0, 2.0, 3.0], [1.0, 2, 3, 4], :invalid_x),
                             ([1.0, -1.0, 2.0, 3.0], [1.0, 2, 3, 4], :invalid_x),
                             ([1.0, NaN, 2.0, 3.0], [1.0, 2, 3, 4], :invalid_x),
                             ([1.0, Inf, 2.0, 3.0], [1.0, 2, 3, 4], :invalid_x),
                             ([1.0, 2.0, 3.0, 4.0], [1.0, NaN, 3, 4], :invalid_y),
                             ([1.0, 2.0, 3.0, 4.0], [1.0, 2, -Inf, 4], :invalid_y),
                             ([1.0, 2.0, 3.0], [1.0, 2.0], :length_mismatch),
                             (Float64[], Float64[], :no_observations))
            a = analyze(x, y, [5.0])
            @test a.status == :invalid_input
            @test code in codes(a)
            @test a.recommendation === nothing
            @test JSON.json(a) isa String                        # serialisable: no NaN/Inf leaked
        end
        @test occursin("Rows 2", only(d.message for d in analyze([1.0, 0.0, 2.0], [1.0, 2, 3], [5.0]).diagnostics))
        for sd in (0.0, -1.0, NaN, Inf)
            @test analyze([1.0, 2.0, 4.0], [1.0, 2, 3], [8.0]; response_sd = sd).status == :invalid_input
        end
    end

    @testset "too few distinct settings" begin
        a = analyze([1.0, 1.0, 2.0, 2.0], [1.0, 1.1, 2.0, 2.1], [4.0, 8.0])
        @test a.status == :insufficient_data
        @test :too_few_settings in codes(a)
        @test a.recommendation === nothing
        @test all(m -> m.support === nothing, a.models)
        @test occursin("at least 1 more distinct setting", a.explanation)
    end

    @testset "constant responses: models indistinguishable, labelled fallback" begin
        a = analyze([1.0, 2.0, 4.0, 8.0], fill(3.0, 4), [3.0, 16.0])
        @test a.status == :ok
        @test :constant_response in codes(a)
        @test all(m -> m.support ≈ 1 / 3, a.models)
        @test a.recommendation.kind == :space_filling
        @test a.recommendation.fallback_reason == :predictions_agree
        @test JSON.json(a) isa String
    end

    @testset "numerical failure is reported, not hidden" begin
        a = analyze([1e160, 2e160, 3e160], [1.0, 2.0, 3.0], [5e160])   # x² overflows
        q = by_id(a)[:restricted_quadratic]
        @test !q.fitted && q.a === nothing && q.support === nothing
        @test :nonfinite_feature in codes(a)
        # Regression: large finite features must not overflow the scaling step and be
        # misreported as rank-deficient; only the family whose transform overflows fails.
        @test by_id(a)[:linear].fitted
        @test something(by_id(a)[:linear].a, NaN) ≈ 1e-160 rtol = 1e-9
        @test by_id(a)[:sqrt].fitted
        @test JSON.json(a) isa String
        d = analyze([1.0, 1.0 + 1e-15, 1.0 + 2e-15], [1.0, 2.0, 3.0], [2.0])
        @test d.status == :no_valid_fit
        @test :degenerate_range in codes(d)
        @test d.recommendation === nothing
    end

    @testset "noise: repeats, stated SD, or explicitly unknown" begin
        a = analyze([1.0, 1.0, 2.0, 2.0, 4.0], [1.0, 3.0, 5.0, 5.0, 9.0], [8.0])
        @test a.noise.source == :repeats
        @test a.noise.df == 2
        @test a.noise.sd_individual ≈ 1.0                       # pooled: (2 + 0) / 2
        @test a.noise.mean_sd_by_setting ≈ [1 / √2, 1 / √2, 1.0] # SD of a mean, kept separate
        b = analyze([1.0, 2.0, 4.0], [1.0, 2.0, 3.5], [8.0]; response_sd = 0.2)
        @test b.noise.source == :user && b.noise.sd_individual == 0.2
        c = analyze([1.0, 2.0, 4.0], [1.0, 2.0, 3.5], [8.0])
        @test c.noise.source == :unknown && c.noise.sd_individual === nothing
        @test c.recommendation.separation.label == :unassessed
        @test all(m -> !m.adequacy.assessed, c.models)
        @test occursin("Noise unknown", c.explanation)
        @test :response_sd_not_used in codes(analyze([1.0, 1.0, 2.0, 4.0], [1.0, 1.1, 2.0, 3.0], [8.0]; response_sd = 0.5))
    end

    @testset "selection: feasible, unmeasured, deterministic, highest weighted disagreement" begin
        x, y = [1.0, 2.0, 3.0], [1.0, 1.45, 1.75]
        a = analyze(x, y, [10.0, 0.5, 5.0, 2.0, 5.0]; response_sd = 0.5)   # 2.0 already measured
        r = a.recommendation
        @test r.kind == :disagreement
        @test r.x in (0.5, 5.0, 10.0)
        @test r.n_unmeasured == 3
        @test r.feasible_range == (lo = 0.5, hi = 10.0)
        @test r.score == maximum(s.score for s in a.candidate_scores)
        @test JSON.json(analyze(x, y, [5.0, 10.0, 0.5]; response_sd = 0.5)) == JSON.json(a)  # order-free
        @test maximin_choice([1.0, 3.0], [2.0]) == (1.0, 1.0)  # tie -> smallest x
    end

    @testset "fallback is a maximin space-filling point" begin
        xs = [1.0, 2.0, 4.0, 8.0]
        a = analyze(xs, 2 .* sqrt.(xs), [1.5, 3.0, 5.0, 6.0, 12.0])
        @test a.recommendation.kind == :space_filling
        @test a.recommendation.fallback_reason == :dominant_model
        mind(c) = minimum(abs(c - m) for m in xs)
        @test all(mind(a.recommendation.x) >= mind(c) for c in (1.5, 3.0, 5.0, 6.0, 12.0))
        @test occursin("not chosen to distinguish", a.explanation)
    end

    @testset "no feasible remaining setting is a clean completed state" begin
        a = analyze([1.0, 2.0, 4.0], [1.0, 1.4, 2.0], [1.0, 2.0, 4.0])
        @test a.status == :no_candidates
        @test a.recommendation === nothing
        @test occursin("complete", a.explanation)
        @test analyze([1.0, 2.0, 4.0], [1.0, 1.4, 2.0], Float64[]).status == :no_candidates
    end

    @testset "a wildly wrong model is down-weighted and cannot dominate acquisition" begin
        xs = repeat(1.0:9.0, inner = 3)
        jitter = repeat([-0.02, 0.0, 0.02], 9)
        y = 2 .* sqrt.(xs) .+ 0.1 .+ jitter
        a = analyze(xs, y, [12.0, 16.0, 25.0])
        q = by_id(a)[:restricted_quadratic]
        @test q.support < 1e-3
        @test q.strongly_down_weighted
        @test by_id(a)[:sqrt].support == maximum(m.support for m in a.models)
        share_q = only(p.share_of_spread for p in a.recommendation.predictions if p.id == :restricted_quadratic)
        @test share_q < 0.01
        # Without the weights, the quadratic's extreme curve would dominate the spread.
        preds = [p.y for p in a.recommendation.predictions]
        @test disagreement(preds, fill(1 / 3, 3)).shares[3] > 0.5
    end

    @testset "heuristic: no candidate fits adequately" begin
        xs = repeat([1.0, 2.0, 3.0, 4.0, 5.0], inner = 2)
        y = repeat([1.0, 3.0, 1.0, 3.0, 1.0], inner = 2) .+ repeat([-0.001, 0.001], 5)
        a = analyze(xs, y, [6.0])
        @test a.all_models_inadequate === true
        @test :no_adequate_model in codes(a)
        @test occursin("no candidate fits", a.explanation)
    end

    @testset "hidden outcomes cannot change the recommendation" begin
        s1, s2 = ReplaySession(), ReplaySession()
        for v in values(s2.hidden.by_x)
            v .= 50.0 .- reverse(v)
        end
        @test JSON.json(recommend(s1)) == JSON.json(recommend(s2))
        reveal!(s1, 0.809); reveal!(s2, 0.809)                   # once revealed, the data differ
        @test JSON.json(recommend(s1)) != JSON.json(recommend(s2))
    end

    @testset "a frozen prediction record is immutable and survives refitting" begin
        s = ReplaySession()
        a = recommend(s)
        r = freeze_predictions(a; created_at = "2026-10-24T20:00:00Z")
        before = JSON.json(r)
        @test !ismutable(r) && r.models isa Tuple
        @test_throws ErrorException setfield!(r, :x, 1.0)
        @test r.x == a.recommendation.x
        @test all(m.predicted_y == rec_pred(a, m.id) for m in r.models)
        reveal!(s, r.x)
        a2 = recommend(s)
        @test a2.data.revision != r.data_revision
        @test JSON.json(r) == before
        @test_throws ArgumentError freeze_predictions(analyze([1.0, 2.0], [1.0, 2.0], [3.0]))
    end
end
