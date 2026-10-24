# Run the declared benchmark (docs/BENCHMARK.md) and write machine-readable results.
#   julia --project=backend --threads=auto backend/scripts/run_benchmark.jl smoke 5
#   julia --project=backend --threads=auto backend/scripts/run_benchmark.jl full 100

using NextLab, CSV, JSON, SHA
const B = NextLab.Benchmark

tag = ARGS[1]
nseeds = parse(Int, ARGS[2])
root = normpath(joinpath(@__DIR__, "..", ".."))
outdir = joinpath(root, "results", "benchmark_$tag")
mkpath(outdir)

protocol_text = split(read(joinpath(root, "docs", "BENCHMARK.md"), String), "## Results")[1]
git(cmd) = try readchomp(Cmd(`git -C $root $cmd`)) catch; "unavailable" end

elapsed = @elapsed runs = B.run_benchmark(1:nseeds)
summary = B.summarize(runs)
pairs = B.paired(runs)
choices = B.nextlab_choice_counts(runs)

CSV.write(joinpath(outdir, "runs.csv"), runs)
CSV.write(joinpath(outdir, "summary.csv"), summary)
CSV.write(joinpath(outdir, "paired.csv"), pairs)
CSV.write(joinpath(outdir, "nextlab_choices.csv"), choices)
meta = (protocol_version = B.PROTOCOL_VERSION, method_version = NextLab.METHOD_VERSION, tag = tag,
        seeds = "1:$nseeds", n_conditions = length(B.CONDITIONS), policies = collect(String.(B.POLICIES)),
        n_run_rows = length(runs), n_predictor_failed = count(r -> r.predictor_failed, runs),
        n_nextlab_failures = count(r -> r.nextlab_failure, runs),
        protocol_sha256 = bytes2hex(sha256(protocol_text)),
        git_commit = git(`rev-parse HEAD`),
        git_worktree_dirty_outside_results = !isempty(git(`status --porcelain -- . :!results`)),
        julia_version = string(VERSION), threads = Threads.nthreads(), runtime_seconds = elapsed,
        preplanned_sequences = B.PLANS, tie_tolerance = B.TIE_TOL, bootstrap_resamples = B.BOOT_B,
        target = "RMSE of the support-weighted ensemble predicted mean vs the noiseless generating relationship at 200 held-out test inputs")
JSON.json(joinpath(outdir, "meta.json"), meta; pretty = true)

println("Wrote $(length(runs)) run rows to $outdir in $(round(elapsed; digits = 1)) s; ",
        "$(meta.n_predictor_failed) predictor failures, $(meta.n_nextlab_failures) NextLab step failures.")
println("\nPrimary endpoint (8 settings, 24 observations): mean paired RMSE difference NextLab − baseline [95% bootstrap interval]  W/T/L")
for c in B.CONDITIONS
    println("C$(c.index) $(c.truth.id) sd=$(c.sd) $(c.layout.id)")
    for p in pairs
        p.condition == c.index && p.n_settings == B.N_FINAL || continue
        println("   vs $(rpad(p.baseline, 17)) $(round(p.mean_diff; sigdigits = 3)) [$(round(p.ci95_lo; sigdigits = 3)), $(round(p.ci95_hi; sigdigits = 3))]  $(p.wins)/$(p.ties)/$(p.losses)  $(p.verdict)")
    end
end
