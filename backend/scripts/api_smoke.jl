# Smoke check against a running NextLab server:
#   julia --project=backend backend/scripts/api_smoke.jl http://127.0.0.1:8080
# load demo -> analyze -> recommend -> reveal selected recorded setting -> compare with
# frozen predictions -> update (analyze) -> export. Also scans payloads for unrevealed periods.

using HTTP, JSON, NextLab

base = isempty(ARGS) ? "http://127.0.0.1:8080" : ARGS[1]
function post(path, body)
    r = HTTP.post(base * path, ["Content-Type" => "application/json"], JSON.json(body); status_exception = false)
    s = String(copy(r.body))
    r.status == 200 || error("$path -> HTTP $(r.status): $s")
    return JSON.parse(s), s
end

recs = NextLab.load_pendulum()
hidden(except = ()) = Set(r.period_s for r in recs if r.length_m > 0.411 && !(r.length_m in except))
nums(x::Number, a) = push!(a, Float64(x)); nums(x::AbstractDict, a) = (foreach(v -> nums(v, a), values(x)); a)
nums(x::AbstractVector, a) = (foreach(v -> nums(v, a), x); a); nums(_, a) = a
leaks(text, except = ()) = intersect(Set(nums(JSON.parse(text), Float64[])), hidden(except))
check(label, ok) = (println(ok ? "PASS " : "FAIL ", label); ok || (global failures += 1))
failures = 0

start, t = post("/api/demo/start", Dict())
check("start: 9 observations at 3 lengths, 6 candidates, no unrevealed periods",
      start["counts"]["observations"] == 9 && length(start["context"]["candidate_x"]) == 6 && isempty(leaks(t)))
ctx = start["context"]
an, _ = post("/api/analyze", Dict("context" => ctx))
check("analyze: status ok, revision $(first(an["revision"], 12)) matches start", an["status"] == "ok" && an["revision"] == start["revision"])
rec, t = post("/api/recommend", Dict("context" => ctx))
snap = rec["snapshot"]
check("recommend: snapshot $(first(snap["snapshot_id"], 12)) at x = $(snap["record"]["x"]) m ($(snap["selection"]["kind"])), no unrevealed periods",
      snap !== nothing && isempty(leaks(t)))
for m in snap["record"]["models"]
    println("      frozen: $(rpad(m["name"], 21)) predicts $(round(m["predicted_y"]; sigdigits = 4)) s, support $(m["support"])")
end
rv, t = post("/api/demo/reveal", Dict("context" => ctx, "snapshot" => snap))
x = snap["record"]["x"]
check("reveal: only the selected recorded length $x m", all(o -> o["x"] == x, rv["observations"]) && isempty(leaks(t, (x,))))
check("reveal did not refit or change the revision", rv["refit_performed"] == false && rv["revision"] == start["revision"])
c = rv["comparison"]
println("      revealed mean $(round(c["observed_mean"]; sigdigits = 4)) s; closest frozen prediction: $(c["closest_model"])")
for m in c["models"]
    println("      $(rpad(m["name"], 21)) error $(round(m["error"]; sigdigits = 3)) s",
            m["error_in_mean_sds"] === nothing ? "" : " ($(round(m["error_in_mean_sds"]; sigdigits = 3)) mean-SDs)")
end
an2, _ = post("/api/analyze", Dict("context" => rv["updated_context"]))
check("update: explicit refit on 12 observations, new revision", an2["analysis"]["data"]["n_observations"] == 12 && an2["revision"] == rv["updated_revision"])
ex, t = post("/api/export", Dict("context" => rv["updated_context"], "history" => [Dict("snapshot" => snap, "updated" => true)]))
check("export: replay record with frozen cycle, revealed values, no unrevealed periods",
      ex["record"]["format"] == "nextlab-experiment-record-2" && ex["record"]["run_type"] == "recorded_data_replay" &&
      ex["record"]["cycles"][1]["comparison"] !== nothing && isempty(leaks(t, (x,))))
stale = HTTP.post(base * "/api/demo/reveal", ["Content-Type" => "application/json"],
                  JSON.json(Dict("context" => rv["updated_context"], "snapshot" => snap)); status_exception = false)
check("stale snapshot after update rejected (HTTP $(stale.status))", stale.status == 409)
println(failures == 0 ? "\nSmoke check passed." : "\n$failures check(s) failed.")
exit(failures == 0 ? 0 : 1)
