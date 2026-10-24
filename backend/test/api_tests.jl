# Integration tests against the real HTTP server (bound to 127.0.0.1 on a free port).

const ALL_RECORDS = NextLab.load_pendulum()
hidden_except(xs...) = Set(r.period_s for r in ALL_RECORDS if r.length_m > 0.411 && !(r.length_m in xs))

"Rewrite integral floats as integers, as a browser's JSON.stringify does (16.0 -> 16)."
jsify(x::AbstractDict) = Dict{String,Any}(String(k) => jsify(v) for (k, v) in x)
jsify(x::AbstractVector) = Any[jsify(v) for v in x]
jsify(x::Float64) = isinteger(x) && abs(x) < 1e15 ? Int(x) : x
jsify(x) = x

@testset "snapshot hashing: signed zero is canonical, real changes are detected" begin
    h = NextLab.content_hash
    nested(v) = Dict{String,Any}("a" => v, "record" => Dict{String,Any}("models" => Any[Dict{String,Any}("b" => v, "ys" => Any[v, 1.5])]))
    @test h(nested(-0.0)) == h(nested(0.0)) == h(nested(0))               # -0.0, 0.0 and integer 0 at any depth
    @test h(nested(0.0)) != h(nested(5e-324))                             # smallest nonzero change still detected
    @test h(nested(0.0)) != h(nested(1.0))
    @test h(Dict{String,Any}("x" => 16.0)) == h(Dict{String,Any}("x" => 16)) # browser rewriting of 16.0 still verifies
end

@testset "NextLab API" begin
    server = NextLab.start_server(; port = 0)
    base = "http://127.0.0.1:$(HTTP.port(server))"
    decoded(r) = (s = String(copy(r.body)); (r.status, isempty(s) ? nothing : JSON.parse(s), s))
    get_(path) = decoded(HTTP.get(base * path; status_exception = false))
    post(path, body) = decoded(HTTP.post(base * path, ["Content-Type" => "application/json"],
                                         body isa AbstractString ? body : JSON.json(body); status_exception = false))
    fields(b) = Set(f["field"] for f in b["fields"])
    try
        @testset "health and readiness" begin
            st, b, _ = get_("/api/health")
            @test st == 200 && b["status"] == "ok" && b["julia_version"] == string(VERSION)
            st, b, _ = get_("/api/ready")
            @test st == 200 && b["ready"] == true
            @test get_("/api/nope")[1] == 404
        end

        @testset "demo loop: start -> analyze -> recommend -> reveal -> compare -> update -> export" begin
            st, start, text = post("/api/demo/start", Dict())
            @test st == 200
            @test isempty(intersect(Set(numbers_in(text)), hidden_except()))
            ctx = start["context"]
            @test start["counts"]["observations"] == 9 && start["counts"]["lengths_measured"] == 3
            @test ctx["candidate_x"] == [0.809, 1.485, 2.437, 4.0, 8.0, 16.0]

            st, an, _ = post("/api/analyze", Dict("context" => ctx))
            @test st == 200 && an["status"] == "ok" && an["revision"] == start["revision"]
            @test length(an["curves"]["x"]) >= 101 && an["curves"]["ensemble"] !== nothing
            @test 0.101 in an["curves"]["x"] && 0.411 in an["curves"]["x"]          # measured-range ends are exact grid points
            @test an["analysis"]["data"]["revision"] isa String

            st, rec, text = post("/api/recommend", Dict("context" => ctx))
            @test st == 200
            @test isempty(intersect(Set(numbers_in(text)), hidden_except()))   # no unrevealed y anywhere
            snap = rec["snapshot"]
            @test snap["record"]["x"] == 16.0
            @test snap["context_revision"] == start["revision"]
            @test length(snap["snapshot_id"]) == 64
            @test snap["selection"]["kind"] == "space_filling"
            @test all(m -> haskey(m, "support") && haskey(m, "predicted_y"), snap["record"]["models"])
            @test snap["diagnostic_state"]["status"] == "ok"

            st, rv, text = post("/api/demo/reveal", Dict("context" => jsify(ctx), "snapshot" => jsify(snap)))
            @test st == 200                                                    # browser-style JSON accepted
            @test [o["y"] for o in rv["observations"]] == [7.68, 8.01, 7.68]
            @test isempty(intersect(Set(numbers_in(text)), hidden_except(16.0)))   # only the selected setting
            @test rv["refit_performed"] == false
            @test rv["revision"] == start["revision"]                          # reveal itself refits nothing
            cmp = rv["comparison"]
            @test cmp["observed_mean"] ≈ (7.68 + 8.01 + 7.68) / 3
            @test cmp["closest_model"] == "sqrt"
            sq = only(m for m in cmp["models"] if m["id"] == "sqrt")
            @test sq["predicted_y"] == only(m["predicted_y"] for m in snap["record"]["models"] if m["id"] == "sqrt")

            ctx2 = rv["updated_context"]
            st, an2, _ = post("/api/analyze", Dict("context" => ctx2))
            @test st == 200 && an2["revision"] == rv["updated_revision"] != start["revision"]
            @test an2["analysis"]["data"]["n_observations"] == 12

            # The old snapshot is no longer pending once the data changed.
            st, b, _ = post("/api/demo/reveal", Dict("context" => ctx2, "snapshot" => snap))
            @test st == 409 && "snapshot.context_revision" in fields(b)

            st, ex, text = post("/api/export", Dict("context" => ctx2, "history" => [Dict("snapshot" => snap, "updated" => true)]))
            rec = ex["record"]
            @test st == 200 && rec["format"] == "nextlab-experiment-record-2" && length(ex["record_id"]) == 64
            @test rec["run_type"] == "recorded_data_replay"
            @test rec["source"]["provenance"]["collected_by_nextlab_user"] == false
            @test occursin("fastR2", rec["source"]["provenance"]["documentation_url"])
            cyc = rec["cycles"][1]
            @test cyc["order"] == 1 && cyc["snapshot_id"] == snap["snapshot_id"] && cyc["refit_after_observation"] == true
            @test cyc["comparison"]["closest_model"] == "sqrt"
            # Frozen predictions are the pre-observation values, not the refitted ones.
            @test [m["predicted_y"] for m in cyc["frozen_predictions"]] == [m["predicted_y"] for m in snap["record"]["models"]]
            @test Set(o["origin"] for o in rec["observations"]) == Set(["recorded_initial_subset", "revealed_recorded_value"])
            @test count(o -> o["cycle"] == 1, rec["observations"]) == 3
            @test [m["formula"] for m in rec["method"]["models"]] == ["y = a·x + b", "y = a·√x + b", "y = a·x² + b"]
            @test isempty(intersect(Set(numbers_in(text)), hidden_except(16.0)))   # no unrevealed recorded values
            lines = split(strip(ex["observations_csv"]), "\n")
            @test lines[1] == "Pendulum length (m),Reported period (s),origin,cycle" && length(lines) == 13

            # Reset issues a new session: the old snapshot is rejected even with identical data.
            st, again, _ = post("/api/demo/start", Dict())
            @test again["context"]["session_id"] != ctx["session_id"]
            @test again["revision"] != start["revision"]
            st, b, _ = post("/api/demo/reveal", Dict("context" => again["context"], "snapshot" => snap))
            @test st == 409 && "snapshot.session_id" in fields(b)

            # Tampering: altered prediction or a different selected x does not verify.
            bad = deepcopy(snap); bad["record"]["models"][2]["predicted_y"] = 7.79
            @test post("/api/demo/reveal", Dict("context" => ctx, "snapshot" => bad))[1] == 422
            bad = deepcopy(snap); bad["record"]["x"] = 8.0
            @test post("/api/demo/reveal", Dict("context" => ctx, "snapshot" => bad))[1] == 422
            # Manual entry is not allowed in demo mode.
            @test post("/api/observe", Dict("context" => ctx, "snapshot" => snap, "y" => [8.0]))[1] == 422
        end

        @testset "context validation gives field-level errors" begin
            ctx = post("/api/demo/start", Dict())[2]["context"]
            c = deepcopy(ctx); c["observed"][1]["x"] = -1
            st, b, _ = post("/api/analyze", Dict("context" => c))
            @test st == 422 && "context.observed[1].x" in fields(b)
            c = deepcopy(ctx); c["observed"][2]["y"] = "0.67"
            @test "context.observed[2].y" in fields(post("/api/analyze", Dict("context" => c))[2])
            c = deepcopy(ctx); c["observed"][1]["y"] = 0.5                      # not the recorded value
            @test "context.observed" in fields(post("/api/analyze", Dict("context" => c))[2])
            c = deepcopy(ctx); c["revealed_x"] = [3.0]
            @test "context.revealed_x[1]" in fields(post("/api/analyze", Dict("context" => c))[2])
            c = deepcopy(ctx); c["response_sd"] = 0
            @test "context.response_sd" in fields(post("/api/analyze", Dict("context" => c))[2])
            c = deepcopy(ctx); c["session_id"] = "x"
            @test "context.session_id" in fields(post("/api/analyze", Dict("context" => c))[2])
            @test post("/api/analyze", "{not json")[1] == 400
            @test post("/api/analyze", Dict())[1] == 422
            big = "{\"pad\":\"" * repeat("a", 2 * 1024 * 1024 + 10) * "\"}"
            @test post("/api/analyze", big)[1] == 413
        end

        @testset "upload: CSV parsed in Julia, malformed input rejected with row numbers" begin
            csv = "﻿\"length (m)\",period\r\n0.2,0.9\r\n0.2,0.92\r\n\"0.4\",1.27\r\n0.8,1.8\r\n0.8,1.79\r\n"
            st, up, text = post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 0.1, "hi" => 1.6, "n" => 16),
                                                   "x_unit" => "m", "y_unit" => "s"))
            @test st == 200
            @test up["columns"] == ["length (m)", "period"]
            @test up["counts"]["observations"] == 5 && up["counts"]["settings"] == 3   # repeats kept
            uctx = up["context"]
            st, rec, _ = post("/api/recommend", Dict("context" => uctx))
            @test st == 200 && rec["snapshot"] !== nothing
            x = rec["snapshot"]["record"]["x"]
            @test x in uctx["candidate_x"] && !(x in (0.2, 0.4, 0.8))
            st, ob, _ = post("/api/observe", Dict("context" => uctx, "snapshot" => rec["snapshot"], "y" => [1.5, 1.52]))
            @test st == 200 && length(ob["observations"]) == 2 && all(o -> o["x"] == x, ob["observations"])
            @test ob["refit_performed"] == false && length(ob["updated_context"]["observed"]) == 7
            overflow = replace(JSON.json(Dict("context" => uctx, "snapshot" => rec["snapshot"], "y" => [12345.678])), "12345.678" => "1e999")
            st, b, _ = post("/api/observe", overflow)
            @test st == 422 && "y[1]" in fields(b)                             # 1e999 parses to Inf
            @test "y[1]" in fields(post("/api/observe", Dict("context" => uctx, "snapshot" => rec["snapshot"], "y" => ["a"]))[2])
            @test post("/api/demo/reveal", Dict("context" => uctx, "snapshot" => rec["snapshot"]))[1] == 422

            msgs(b) = join((f["message"] for f in b["fields"]), " | ")
            st, b, _ = post("/api/upload", Dict("csv" => "x,y\n1,2\n3\n4,5\n6,7\n", "bounds" => Dict("lo" => 1, "hi" => 8, "n" => 5)))
            @test st == 422 && occursin("Data row 2: too few fields", msgs(b))
            st, b, _ = post("/api/upload", Dict("csv" => "x,y\n1,2\n2,abc\n4,5\n", "bounds" => Dict("lo" => 1, "hi" => 8, "n" => 5)))
            @test st == 422 && occursin("Data row 2: y", msgs(b))
            st, b, _ = post("/api/upload", Dict("csv" => "x,y\n1,2\n1,3\n2,5\n", "bounds" => Dict("lo" => 1, "hi" => 8, "n" => 5)))
            @test st == 422 && occursin("At least 3 distinct x", msgs(b))
            st, b, _ = post("/api/upload", Dict("csv" => "x,y\n1,2\n2,3\n4,5\n", "bounds" => Dict("lo" => 5, "hi" => 1, "n" => 5)))
            @test st == 422 && "bounds.hi" in fields(b)
            st, b, _ = post("/api/upload", Dict("csv" => "x,y\n1,2\n2,3\n4,5\n"))
            @test st == 422 && "bounds" in fields(b)
            st, b, _ = post("/api/upload", Dict("csv" => "a,b,c\n1,2,3\n2,3,4\n4,5,6\n", "bounds" => Dict("lo" => 1, "hi" => 8, "n" => 5)))
            @test st == 422 && "x_column" in fields(b)
            st, b, _ = post("/api/upload", Dict("csv" => "a,b,c\n1,2,3\n2,3,4\n4,5,6\n", "x_column" => "a", "y_column" => 3,
                                               "bounds" => Dict("lo" => 1, "hi" => 8, "n" => 5)))
            @test st == 200 && b["y_column"] == "c"
            @test post("/api/feasible", Dict("lo" => 0.5, "hi" => 1.5, "n" => 3))[2]["candidate_x"] == [0.5, 1.0, 1.5]
            @test "bounds.lo" in fields(post("/api/feasible", Dict("lo" => -1, "hi" => 1, "n" => 3))[2])
        end

        @testset "out-of-range JSON numbers are field errors, never Inf or HTTP 500" begin
            # Regression: JSON.jl parses these as BigFloat/BigInt, which used to pass `isfinite`
            # and become ±Inf (or 0) only after Float64 conversion.
            raw(body, placeholder, literal) = replace(JSON.json(body), placeholder => literal)
            huge_int = "1" * repeat("0", 400)
            ctx = post("/api/demo/start", Dict())[2]["context"]
            csv = "x,y\n0.2,0.9\n0.4,1.27\n0.8,1.8\n"
            up = post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 0.1, "hi" => 1.6, "n" => 16)))[2]
            uctx = up["context"]
            snap = post("/api/recommend", Dict("context" => uctx))[2]["snapshot"]
            for lit in ("1e999", "-1e999", huge_int, "-" * huge_int)
                obs = deepcopy(uctx); obs["observed"][1]["y"] = 12345.678
                st, b, _ = post("/api/analyze", raw(Dict("context" => obs), "12345.678", lit))
                @test st == 422 && "context.observed[1].y" in fields(b)
                obs = deepcopy(uctx); obs["observed"][1]["x"] = 12345.678
                st, b, _ = post("/api/analyze", raw(Dict("context" => obs), "12345.678", lit))
                @test st == 422 && "context.observed[1].x" in fields(b)
                cands = deepcopy(uctx); cands["candidate_x"][1] = 12345.678
                st, b, _ = post("/api/analyze", raw(Dict("context" => cands), "12345.678", lit))
                @test st == 422 && "context.candidate_x[1]" in fields(b)
                sd = deepcopy(uctx); sd["response_sd"] = 12345.678
                st, b, _ = post("/api/analyze", raw(Dict("context" => sd), "12345.678", lit))
                @test st == 422 && "context.response_sd" in fields(b)
                rv = deepcopy(ctx); rv["revealed_x"] = [12345.678]
                st, b, _ = post("/api/analyze", raw(Dict("context" => rv), "12345.678", lit))
                @test st == 422 && "context.revealed_x[1]" in fields(b)
                st, b, _ = post("/api/observe", raw(Dict("context" => uctx, "snapshot" => snap, "y" => [12345.678]), "12345.678", lit))
                @test st == 422 && "y[1]" in fields(b)
                st, b, _ = post("/api/feasible", raw(Dict("lo" => 0.5, "hi" => 12345.678, "n" => 3), "12345.678", lit))
                @test st == 422 && "bounds.hi" in fields(b)
                st, b, _ = post("/api/upload", raw(Dict("csv" => csv, "response_sd" => 12345.678,
                                                       "bounds" => Dict("lo" => 0.1, "hi" => 1.6, "n" => 16)), "12345.678", lit))
                @test st == 422 && "response_sd" in fields(b)
                st, b, _ = post("/api/upload", raw(Dict("csv" => csv, "candidate_x" => [12345.678]), "12345.678", lit))
                @test st == 422 && "candidate_x[1]" in fields(b)
            end
            # A tiny positive exponent underflows to 0 on conversion: not a positive x or bound.
            obs = deepcopy(uctx); obs["observed"][1]["x"] = 12345.678
            st, b, _ = post("/api/analyze", raw(Dict("context" => obs), "12345.678", "1e-999"))
            @test st == 422 && "context.observed[1].x" in fields(b)
            st, b, _ = post("/api/feasible", raw(Dict("lo" => 12345.678, "hi" => 1, "n" => 3), "12345.678", "1e-999"))
            @test st == 422 && "bounds.lo" in fields(b)
            # Normal numbers, including integers and exponent notation, are unchanged.
            st, b, _ = post("/api/observe", raw(Dict("context" => uctx, "snapshot" => snap, "y" => [12345.678, 2]), "12345.678", "1.5e0"))
            @test st == 200 && [o["y"] for o in b["observations"]] == [1.5, 2.0]
            @test post("/api/feasible", Dict("lo" => 1, "hi" => 2, "n" => 3))[2]["candidate_x"] == [1.0, 1.5, 2.0]
        end

        @testset "upload workflow: preview, feasible settings, manual entry, export" begin
            st, pv, _ = post("/api/upload/preview", Dict("csv" => "﻿run,\"temp (K)\",rate\r\n1,300,0.5\r\n2,310,\"0.61\"\r\n3,320\r\n"))
            @test st == 200 && pv["columns"] == ["run", "temp (K)", "rate"] && pv["n_rows"] == 3
            @test pv["column_info"][2]["min"] == 300.0 && pv["column_info"][2]["max"] == 320.0
            @test any(p -> occursin("Data row 3: too few fields", p["message"]), pv["problems"])

            csv = "dose,response\n1,2.1\n1,2.3\n2,2.9\n4,4.2\n4,4.0\n"
            st, up, _ = post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 1, "hi" => 4, "step" => 0.5),
                                                "candidate_x" => [6, 2.5], "x_label" => "Dose", "x_unit" => "mg",
                                                "y_label" => "Response", "y_unit" => "a.u.", "source_name" => "dose.csv"))
            @test st == 200
            u = up["context"]
            @test u["candidate_x"] == [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 6.0]            # union, deduplicated
            @test up["counts"]["candidates_outside_observed_range"] == 1 && up["counts"]["settings"] == 3
            @test u["x_label"] == "Dose" && u["source_name"] == "dose.csv" && u["revealed_x"] == []
            @test "bounds.step" in fields(post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 1, "hi" => 4, "step" => 0.001)))[2])
            @test "bounds.step" in fields(post("/api/upload", Dict("csv" => csv, "bounds" => Dict("lo" => 1, "hi" => 4, "step" => 0)))[2])
            @test post("/api/feasible", Dict("lo" => 1, "hi" => 2, "step" => 0.5, "candidate_x" => [1.5, 3]))[2]["candidate_x"] == [1.0, 1.5, 2.0, 3.0]

            rec = post("/api/recommend", Dict("context" => u))[2]
            snap = rec["snapshot"]
            st, ob, _ = post("/api/observe", Dict("context" => u, "snapshot" => snap, "y" => [5.1, 5.3]))
            @test st == 200 && ob["refit_performed"] == false
            st, ex, _ = post("/api/export", Dict("context" => ob["updated_context"], "history" => [Dict("snapshot" => snap, "updated" => false)]))
            r = ex["record"]
            @test r["run_type"] == "user_uploaded_data" && r["source"]["name"] == "dose.csv"
            @test count(o -> o["origin"] == "entered_manually" && o["cycle"] == 1, r["observations"]) == 2
            @test count(o -> o["origin"] == "uploaded_file", r["observations"]) == 5
            @test r["cycles"][1]["refit_after_observation"] == false
            @test r["variables"]["x"]["unit"] == "mg" && r["noise_assumption"]["stated_response_sd"] === nothing
            @test startswith(ex["observations_csv"], "Dose (mg),Response (a.u.),origin,cycle\n")

            # Regression: constant responses give coefficients of -0.0, and browsers serialize -0
            # as 0. An unaltered snapshot must still verify after that round trip.
            cu = post("/api/upload", Dict("csv" => "x,y\n1,3\n1,3\n2,3\n2,3\n4,3\n", "bounds" => Dict("lo" => 1, "hi" => 4, "step" => 0.3)))[2]["context"]
            csnap = post("/api/recommend", Dict("context" => cu))[2]["snapshot"]
            @test any(m -> m["a"] === -0.0, csnap["record"]["models"])           # precondition: a negative zero is present
            @test post("/api/observe", Dict("context" => jsify(cu), "snapshot" => jsify(csnap), "y" => [3]))[1] == 200
            # The context revision uses the same canonical form: a -0.0 response survives the round trip.
            zu = post("/api/upload", Dict("csv" => "x,y\n1,-0.0\n2,0.5\n4,1.0\n", "candidate_x" => [3]))[2]
            @test zu["context"]["observed"][1]["y"] === -0.0
            @test post("/api/analyze", Dict("context" => jsify(zu["context"])))[2]["revision"] == zu["revision"]

            r = HTTP.get(base * "/api/sample.csv"; status_exception = false)
            @test r.status == 200 && startswith(String(copy(r.body)), "length_m,period_s\n0.101,0.72\n")
        end

        @testset "benchmark summary with reproduction metadata" begin
            st, b, _ = get_("/api/benchmark")
            @test st == 200
            @test b["meta"]["method_version"] == "nextlab-core-1"
            @test b["results_match_current_method"] == true && b["current_method_version"] == NextLab.METHOD_VERSION
            @test length(b["paired"]) == 48 && all(r -> r["n_settings"] == 8, b["paired"])
            @test Set(v["baseline"] for v in b["verdicts"]) == Set(["random", "preplanned_even", "endpoint_maximin"])
            @test occursin("run_benchmark.jl full 100", b["reproduce"]["command"])
            r = HTTP.get(base * "/api/benchmark/files/paired.csv"; status_exception = false)
            @test r.status == 200 && startswith(String(copy(r.body)), "condition,")
            @test HTTP.get(base * "/api/benchmark/files/..%2Fmeta.json"; status_exception = false).status == 404
            @test HTTP.get(base * "/api/benchmark/files/Project.toml"; status_exception = false).status == 404
        end
    finally
        close(server)
    end
end
