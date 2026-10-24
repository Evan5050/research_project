# Built-in pendulum dataset (fastR2 `Pendulum`) and its provenance.
# See data/README.md for the source, licence and limitations.

const DATA_DIR = normpath(joinpath(@__DIR__, "..", "..", "data"))
const PENDULUM_SOURCE_CSV = joinpath(DATA_DIR, "pendulum", "fastR2_Pendulum_source.csv")
const PENDULUM_DERIVED_CSV = joinpath(DATA_DIR, "pendulum", "pendulum_length_period.csv")

"One recorded row. `delta_length` is the stated length accuracy (m), not period uncertainty."
struct PendulumRecord
    length_m::Float64
    period_s::Float64
    delta_length_m::Float64
end

const PENDULUM_PROVENANCE = (
    name = "fastR2 Pendulum",
    description = "Pendulum length and reported period. The source describes each period " *
                  "as measured by averaging over several swings.",
    credit = "Calvin College physics students under Professor Steve Plath " *
             "(as credited in the fastR2 documentation).",
    collected_by_nextlab_user = false,
    documentation_url = "https://rpruim.github.io/fastR2/reference/Pendulum.html",
    source_file_url = "https://raw.githubusercontent.com/rpruim/fastR2/main/data/pendulum.rda",
    package_metadata_url = "https://github.com/rpruim/fastR2/blob/main/DESCRIPTION",
    source_file_sha256 = "4f288cadb6ad611b1eeb52ea92fd4d13b62356a0a490a28701e2add05de8c39a",
    package_license = "GPL (>= 2), as declared by the fastR2 package",
    x = (column = "length", label = "Pendulum length", unit = "m"),
    y = (column = "period", label = "Reported period (average over several swings)", unit = "s"),
    limitations = [
        "Periods are reported averages over several swings, not individual swing timings.",
        "delta.length is the stated length accuracy; it is not period uncertainty and is not plotted as a vertical error bar.",
        "The initial fitting method treats length as exact.",
        "No detailed collection protocol beyond the source documentation is known; swing amplitude and the number of swings averaged are not stated.",
        "The 16 m setting is a historical recorded measurement, not a suggestion that a trainee can build that apparatus.",
    ],
)

"""
    load_pendulum(path = PENDULUM_SOURCE_CSV) -> Vector{PendulumRecord}

Read the untouched source snapshot, checking its exact column names.
"""
function load_pendulum(path::AbstractString = PENDULUM_SOURCE_CSV)
    f = CSV.File(path)
    cols = propertynames(f)
    cols == [:length, :period, Symbol("delta.length")] ||
        error("unexpected pendulum columns $(cols); expected length, period, delta.length")
    return [PendulumRecord(Float64(r.length), Float64(r.period), Float64(r[Symbol("delta.length")]))
            for r in f]
end

"""
    validate_pendulum(records) -> records

Throw unless the snapshot has 27 records at nine distinct lengths, three records per
length, and positive finite lengths and periods.
"""
function validate_pendulum(records::AbstractVector{PendulumRecord})
    length(records) == 27 || error("expected 27 records, found $(length(records))")
    for r in records
        (isfinite(r.length_m) && r.length_m > 0) || error("non-positive or non-finite length $(r.length_m)")
        (isfinite(r.period_s) && r.period_s > 0) || error("non-positive or non-finite period $(r.period_s)")
    end
    lengths = unique(r.length_m for r in records)
    length(lengths) == 9 || error("expected 9 distinct lengths, found $(length(lengths))")
    for L in lengths
        n = count(r -> r.length_m == L, records)
        n == 3 || error("expected 3 records at length $L, found $n")
    end
    return records
end
