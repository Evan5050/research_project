# Fail if any unrevealed pendulum period appears as a standalone number in the given files
# or directories (recursively). Used to check the frontend bundle and live API payloads.
#   julia --project=backend backend/scripts/scan_hidden.jl frontend/dist frontend/src
# Positive control: scanning data/pendulum/fastR2_Pendulum_source.csv must report hits.

using NextLab

records = NextLab.load_pendulum()
start = sort(unique(r.length_m for r in records))[1:NextLab.N_INITIAL_LENGTHS]
hidden = sort(unique(r.period_s for r in records if !(r.length_m in start)))
pattern = Regex("(?<![0-9.])(" * join(replace.(string.(hidden), "." => "\\."), "|") * ")(?![0-9])")

files(p) = isdir(p) ? [joinpath(d, f) for (d, _, fs) in walkdir(p) for f in fs] : [p]

hits = 0
for path in ARGS, f in files(path)
    for (i, line) in enumerate(eachline(f)), m in eachmatch(pattern, line)
        global hits += 1
        hits <= 20 && println("$f:$i: ", m.match)
    end
end
println(hits == 0 ? "OK: no unrevealed period values found" : "FOUND $hits unrevealed period value(s)")
exit(hits == 0 ? 0 : 1)
