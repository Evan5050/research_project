using NextLab: PendulumRecord, load_pendulum, validate_pendulum, ReplaySession, reveal!, reset!,
    engine_inputs, public_state, lengths_measured, observation_count, Observation,
    PENDULUM_SOURCE_CSV, PENDULUM_DERIVED_CSV

collect_numbers(x::Number, acc) = push!(acc, Float64(x))
collect_numbers(x::AbstractDict, acc) = (foreach(v -> collect_numbers(v, acc), values(x)); acc)
collect_numbers(x::AbstractVector, acc) = (foreach(v -> collect_numbers(v, acc), x); acc)
collect_numbers(_, acc) = acc
numbers_in(json::AbstractString) = collect_numbers(JSON.parse(json), Float64[])

const HIDDEN_LENGTHS = [0.809, 1.485, 2.437, 4.0, 8.0, 16.0]

@testset "pendulum snapshot" begin
    records = load_pendulum()
    @test validate_pendulum(records) === records
    @test records[1] == PendulumRecord(0.101, 0.72, 0.001)
    @test records[end] == PendulumRecord(16.0, 7.68, 0.05)

    @testset "derived two-column file maps length->length_m, period->period_s" begin
        f = CSV.File(PENDULUM_DERIVED_CSV)
        @test propertynames(f) == [:length_m, :period_s]
        @test f.length_m == [r.length_m for r in records]
        @test f.period_s == [r.period_s for r in records]
    end

    @testset "validation rejects malformed snapshots" begin
        @test_throws ErrorException validate_pendulum(records[1:26])
        bad = copy(records); bad[1] = PendulumRecord(-0.101, 0.72, 0.001)
        @test_throws ErrorException validate_pendulum(bad)
        bad = copy(records); bad[2] = PendulumRecord(0.101, NaN, 0.001)
        @test_throws ErrorException validate_pendulum(bad)
        bad = copy(records); bad[3] = PendulumRecord(0.205, 0.68, 0.001)  # 2 at 0.101, 4 at 0.205
        @test_throws ErrorException validate_pendulum(bad)
    end
end

@testset "replay contract" begin
    records = validate_pendulum(load_pendulum())
    hidden_periods = Set(r.period_s for r in records if r.length_m in HIDDEN_LENGTHS)
    s = ReplaySession(records)

    @testset "starts at the three shortest lengths" begin
        @test sort(unique(o.x for o in s.observed)) == [0.101, 0.205, 0.411]
        @test lengths_measured(s) == 3
        @test observation_count(s) == 9
        @test s.candidates == HIDDEN_LENGTHS
    end

    @testset "browser payload and engine inputs carry no hidden period" begin
        payload = JSON.json(NextLab.pendulum_payload(s))
        @test isempty(intersect(Set(numbers_in(payload)), hidden_periods))
        inputs = engine_inputs(s)
        @test isempty(intersect(Set(inputs.y), hidden_periods))
        @test inputs.candidate_x == HIDDEN_LENGTHS
        @test propertynames(inputs) == (:x, :y, :candidate_x)
    end

    @testset "engine inputs do not depend on hidden outcomes" begin
        before = engine_inputs(s)
        t = ReplaySession(records)
        for v in values(t.hidden.by_x)
            v .= reverse(v) .+ 100.0
        end
        @test engine_inputs(t) == before
    end

    @testset "reveal moves all three reported values at one recorded length" begin
        new = reveal!(s, 0.809)
        @test new == [Observation(0.809, y) for y in (1.87, 1.82, 1.85)]
        @test lengths_measured(s) == 4
        @test observation_count(s) == 12
        @test !(0.809 in s.candidates)
        @test_throws ArgumentError reveal!(s, 0.809)   # already revealed
        @test_throws ArgumentError reveal!(s, 0.101)   # initial, not a candidate
        @test_throws ArgumentError reveal!(s, 3.0)     # never recorded: no invented value
    end

    @testset "reset restores the exact initial state" begin
        reveal!(s, 16.0)
        reset!(s)
        fresh = ReplaySession(records)
        @test s.observed == fresh.observed
        @test s.candidates == fresh.candidates
        @test s.hidden.by_x == fresh.hidden.by_x
        @test isempty(s.reveal_order)
        @test reveal!(s, 0.809) == [Observation(0.809, y) for y in (1.87, 1.82, 1.85)]
    end
end
