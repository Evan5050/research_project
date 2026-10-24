# Two-column numeric CSV parsing for uploaded data. Parsing only: no evaluation of content,
# no cleaning beyond reading numbers. Malformed rows are reported, never silently dropped.

const MAX_UPLOAD_BYTES = 2 * 1024 * 1024
const MAX_ROWS = 2_000
const MAX_CANDIDATES = 1_001

short(s; n = 40) = (t = string(s); length(t) > n ? first(t, n) * "…" : t)

"""
    json_float(v) -> Float64 or nothing

Convert a parsed JSON number to Float64, checking finiteness *after* conversion. JSON.jl
returns BigFloat/BigInt for out-of-range literals (1e999, 400-digit integers); those are
finite before conversion and ±Inf after. Non-numbers, Bools and failed conversions give `nothing`.
"""
function json_float(v)
    v isa Real && !(v isa Bool) || return nothing
    f = try
        Float64(v)
    catch
        return nothing
    end
    return isfinite(f) ? f : nothing
end

"""
    parse_upload_csv(text; x_column = nothing, y_column = nothing)
      -> (; ok, x, y, columns, x_column, y_column, errors)

Header row required. Columns are chosen by name or 1-based index; with exactly two
columns and none chosen, the first is x and the second y. Repeated x rows are kept.
`errors` holds (field, message) pairs with data-row numbers (row 1 = first row after the header).
"""
function parse_upload_csv(text::AbstractString; x_column = nothing, y_column = nothing)
    fail(field, msg) = (ok = false, x = Float64[], y = Float64[], columns = String[], x_column = "", y_column = "",
                        errors = [(field, msg)])
    ncodeunits(text) <= MAX_UPLOAD_BYTES || return fail("csv", "The file is larger than the 2 MB prototype limit.")
    isvalid(String(text)) || return fail("csv", "The file is not valid UTF-8 text.")
    isempty(strip(text)) && return fail("csv", "The file is empty.")
    f = try
        CSV.File(IOBuffer(String(text)); types = String, on_error = :collect)
    catch e
        return fail("csv", "The file could not be read as CSV: " * short(sprint(showerror, e); n = 120))
    end
    columns = String.(propertynames(f))
    length(columns) >= 2 || return fail("csv", "Expected a header row and at least two columns; found $(length(columns)).")
    length(f) <= MAX_ROWS || return fail("csv", "The file has $(length(f)) data rows; the prototype limit is $MAX_ROWS.")
    length(f) >= 1 || return fail("csv", "The file has a header but no data rows.")

    function pick(sel, default, field)
        sel === nothing && return length(columns) == 2 ? (default, nothing) :
            (0, "The file has $(length(columns)) columns; choose the x and y columns.")
        if sel isa Integer && !(sel isa Bool)
            1 <= sel <= length(columns) || return (0, "Column $sel does not exist (the file has $(length(columns)) columns).")
            return (Int(sel), nothing)
        elseif sel isa AbstractString
            i = findfirst(==(sel), columns)
            i === nothing && return (0, "No column named \"$(short(sel))\". Columns: $(join(short.(columns), ", ")).")
            return (i, nothing)
        end
        return (0, "Choose a column by name or 1-based number.")
    end
    xi, xe = pick(x_column, 1, "x_column")
    yi, ye = pick(y_column, 2, "y_column")
    errors = Tuple{String,String}[]
    xe === nothing || push!(errors, ("x_column", xe))
    ye === nothing || push!(errors, ("y_column", ye))
    xi != 0 && xi == yi && push!(errors, ("y_column", "x and y must be different columns."))
    isempty(errors) || return (ok = false, x = Float64[], y = Float64[], columns = columns, x_column = "", y_column = "", errors = errors)

    for p in CSV.problems(f)
        where = p.row == 0 ? "File" : "Data row $(p.row)"
        push!(errors, ("csv", "$where: " * (p.kind == :short_row ? "too few fields." :
                                           p.kind == :long_row ? "too many fields." :
                                           p.kind in (:unclosed_quote, :invalid_quoted_field) ? "malformed quoting." :
                                           "unreadable value.")))
    end
    x, y = Float64[], Float64[]
    for (i, r) in enumerate(f)
        xs, ys = r[xi], r[yi]
        xv = xs === missing ? nothing : tryparse(Float64, strip(xs))
        yv = ys === missing ? nothing : tryparse(Float64, strip(ys))
        if xv === nothing || !isfinite(xv) || xv <= 0
            push!(errors, ("csv", "Data row $i: x (\"$(short(coalesce(xs, "")))\") must be a positive finite number."))
        end
        if yv === nothing || !isfinite(yv)
            push!(errors, ("csv", "Data row $i: y (\"$(short(coalesce(ys, "")))\") must be a finite number."))
        end
        xv === nothing || yv === nothing || (push!(x, xv); push!(y, yv))
    end
    length(errors) > 50 && (errors = vcat(errors[1:50], [("csv", "… $(length(errors) - 50) more problems not shown.")]))
    if isempty(errors) && length(unique(x)) < 3
        push!(errors, ("csv", "At least 3 distinct x values are needed to compare models; found $(length(unique(x)))."))
    end
    return (ok = isempty(errors), x = isempty(errors) ? x : Float64[], y = isempty(errors) ? y : Float64[],
            columns = columns, x_column = columns[xi], y_column = columns[yi], errors = errors)
end

"Evenly spaced feasible settings from user bounds; returns (grid, errors)."
function feasible_grid(lo, hi, n)
    errors = Tuple{String,String}[]
    lo, hi = json_float(lo), json_float(hi)
    lo !== nothing && lo > 0 || push!(errors, ("bounds.lo", "Lower bound must be a positive finite number."))
    hi === nothing && push!(errors, ("bounds.hi", "Upper bound must be a finite number."))
    lo !== nothing && hi !== nothing && lo >= hi && push!(errors, ("bounds.hi", "Upper bound must be greater than the lower bound."))
    n isa Integer && !(n isa Bool) && 2 <= n <= MAX_CANDIDATES ||
        push!(errors, ("bounds.n", "Number of settings must be a whole number from 2 to $MAX_CANDIDATES."))
    isempty(errors) || return (Float64[], errors)
    return (collect(range(lo, hi; length = Int(n))), errors)
end
