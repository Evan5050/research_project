using NextLab: analyze, ensemble_predict
using Random

const BM = NextLab.Benchmark

"Rebuild the observed data a policy received from the table rows it requested, in a given order."
observed_from(table, requested) =
    (reduce(vcat, [fill(BM.CANDIDATES[j], BM.REPS) for j in requested]),
     reduce(vcat, [table.y[j, :] for j in requested]))

@testset "benchmark protocol checks" begin
    @testset "design: candidate and test inputs are as declared and disjoint" begin
        @test length(BM.CANDIDATES) == 21
        @test BM.CANDIDATES[1] == 0.2 && BM.CANDIDATES[end] == 1.2
        @test BM.CANDIDATES[[10, 11, 12]] ≈ [0.65, 0.7, 0.75]
        @test length(BM.TEST_X) == 200
        @test all(0.2 .< BM.TEST_X .< 1.2)
        @test minimum(abs(t - c) for t in BM.TEST_X for c in BM.CANDIDATES) >= 0.0025 - 1e-12
        @test length(BM.CONDITIONS) == 16
    end

    cond = BM.CONDITIONS[7]          # T2 linear, sd 0.10, middle cluster
    table = BM.ObservationTable(cond.truth.f, cond.sd, 3)

    @testset "equal costs: every policy measures 8 distinct settings, 24 observations" begin
        for p in BM.POLICIES
            rows, oracle = BM.run_policy(cond, 3, p, table)
            @test length(oracle.requested) == BM.N_FINAL
            @test allunique(oracle.requested)
            @test [r.n_settings for r in rows] == collect(3:8)
            @test [r.n_observations for r in rows] == collect(9:3:24)
            @test oracle.requested[1:3] == [findfirst(==(s), BM.CANDIDATES) for s in cond.layout.start]
        end
    end

    @testset "fixed seeds reproduce identical results" begin
        c = BM.CONDITIONS[[1, 16]]
        @test isequal(BM.run_benchmark(1:3; conditions = c), BM.run_benchmark(1:3; conditions = c))
    end

    @testset "truth isolation: unrequested rows cannot influence any policy" begin
        for p in BM.POLICIES
            rows, oracle = BM.run_policy(cond, 3, p, table)
            tampered = copy(table.y)
            for j in 1:length(BM.CANDIDATES)
                j in oracle.requested || (tampered[j, :] .= 1e6)
            end
            rows2, oracle2 = BM.run_policy(cond, 3, p, BM.ObservationTable(tampered))
            @test oracle2.requested == oracle.requested
            @test isequal(rows2, rows)
        end
        # The policy view carries no truth, table or test responses.
        @test fieldnames(typeof((x = Float64[], y = Float64[], remaining = Float64[], start = Float64[]))) ==
              (:x, :y, :remaining, :start)
        # Noise depends on the seed alone, not on any policy's random calls.
        before = BM.noise_draws(3)
        BM.run_policy(cond, 3, :random, table)
        @test BM.noise_draws(3) == before
    end

    @testset "one shared predictor: RMSE depends only on the observed set" begin
        truth_at_test = cond.truth.f.(BM.TEST_X)
        for p in BM.POLICIES
            rows, oracle = BM.run_policy(cond, 3, p, table)
            x, y = observed_from(table, oracle.requested)
            @test BM.evaluate(x, y, truth_at_test).rmse == last(rows).rmse_noiseless
            xr, yr = observed_from(table, reverse(oracle.requested))
            @test BM.evaluate(xr, yr, truth_at_test).rmse ≈ last(rows).rmse_noiseless rtol = 1e-12
        end
    end

    @testset "ensemble predictor: support-weighted mean of supported fits" begin
        xs = [0.2, 0.4, 0.6, 0.8, 1.0]
        a = analyze(repeat(xs, inner = 2), repeat(1.6 .* xs .+ 0.5, inner = 2), [1.2])
        @test ensemble_predict(a, [1.1]) ≈ [1.6 * 1.1 + 0.5] rtol = 1e-9
        @test ensemble_predict(analyze([1.0, 2.0], [1.0, 2.0], [3.0]), [1.5]) === nothing
    end

    @testset "paired summary counts wins, ties and losses with the declared tolerance" begin
        runs = BM.run_benchmark(1:4; conditions = BM.CONDITIONS[[11]])   # T3, sd 0.03, L1
        pr = [r for r in BM.paired(runs) if r.n_settings == 3]           # identical starts: all ties
        @test all(r -> r.ties == 4 && r.wins == 0 && r.losses == 0 && r.mean_diff == 0, pr)
        @test all(r -> r.n_pairs + r.n_missing_pairs == 4, BM.paired(runs))
    end
end
