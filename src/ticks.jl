# Tick locations and labels.
#
# `optimize_ticks` is adapted from PlotUtils.jl (MIT, © 2016 Thomas Breloff and contributors),
# which took it from Gadfly.jl (Daniel C. Jones): Wilkinson's scoring of tick sequences for
# simplicity, coverage, granularity and niceness. Makie's `WilkinsonTicks` calls the same code.

function _bounding_order_of_magnitude(xspan::Float64, base::Float64)
    a = 1
    while xspan < base^a
        a -= 1
    end
    b = 1
    while xspan > base^b
        b += 1
    end
    while a + 1 < b
        c = div(a + b, 2)
        if xspan < base^c
            b = c
        else
            a = c
        end
    end
    return b
end

function _postdecimal_digits(x::Float64)
    for i in floor(Int, log10(floatmin(Float64))):ceil(Int, log10(floatmax(Float64)))
        x == floor(x; digits = i) && return i
    end
    return 0
end

const WILKINSON_Q = [(1.0, 1.0), (5.0, 0.9), (2.0, 0.7), (2.5, 0.5), (3.0, 0.2)]

"""Wilkinson tick values inside `[lo, hi]` (strict span), roughly `k_ideal` of them."""
function optimize_ticks(lo::Float64, hi::Float64; k_min::Int = 2, k_max::Int = 10, k_ideal::Int = 5)
    if !(isfinite(lo) && isfinite(hi))
        return Float64[]
    elseif isapprox(lo, hi; rtol = 1000eps())
        return [lo]
    end
    Qv = [q[1] for q in WILKINSON_Q]
    Qs = [q[2] for q in WILKINSON_Q]
    wg, ws, wc, wn = 1 / 4, 1 / 6, 1 / 3, 1 / 4
    base = 10.0
    xspan = hi - lo
    z = _bounding_order_of_magnitude(xspan, base)
    num_digits = _bounding_order_of_magnitude(max(abs(lo), abs(hi)), base) + maximum(_postdecimal_digits(q) for q in Qv)
    high_score = -Inf
    best = Float64[]
    S = Vector{Float64}(undef, 2k_max)
    while 2k_max * base^(z + 1) > xspan
        sigdigits = max(1, num_digits - z)
        for k in k_min:(2k_max), (q, qscore) in zip(Qv, Qs)
            tickspan = q * base^z
            tickspan < eps() * max(abs(lo), abs(hi)) && continue
            span = (k - 1) * tickspan
            span < xspan && continue
            r_float = (hi - span) / tickspan
            isfinite(r_float) || continue
            r = ceil(Int, r_float)
            while r * tickspan <= lo
                for i in 0:(k - 1)
                    S[i + 1] = (r + i) * tickspan
                end
                S[1] = round(S[1]; sigdigits = sigdigits)
                S[k] = round(S[k]; sigdigits = sigdigits)
                viewmin = max(S[1], lo)
                viewmax = min(S[k], hi)
                len = 0
                for i in 1:k
                    if viewmin <= S[i] <= viewmax
                        len += 1
                        S[len] = S[i]
                    end
                end
                has_zero = r <= 0 && abs(r) < k
                s = has_zero ? 1.0 : 0.0
                g = 0 < len < 2k_ideal ? 1 - abs(len - k_ideal) / k_ideal : 0.0
                c = len > 1 ? 1.5xspan / ((len - 1) * tickspan) : 0.0
                score = wg * g + ws * s + wc * c + wn * qscore
                span > xspan && (score -= 10000)
                span >= 2xspan && (score -= 1000)
                if score > high_score && k_min <= len <= k_max
                    high_score = score
                    best = S[1:len]
                end
                r += 1
            end
        end
        z -= 1
    end
    if isinf(high_score)
        return collect(range(lo, hi; length = max(k_min, 2)))
    end
    # Clean the floating-point noise of multiples (0.30000000000000004 → 0.3).
    step = length(best) > 1 ? best[2] - best[1] : abs(best[1])
    digits = step > 0 ? max(0, -floor(Int, log10(step)) + 3) : 12
    return [round(v; digits = min(digits, 15)) for v in best]
end

"""
    WilkinsonTicks(k_ideal; k_min = 3, k_max = 10)

Nice tick values (Wilkinson's algorithm), about `k_ideal` of them. The default for every axis.
"""
struct WilkinsonTicks
    k_ideal::Int
    k_min::Int
    k_max::Int
end
WilkinsonTicks(k_ideal::Integer = 5; k_min::Integer = 3, k_max::Integer = 10) = WilkinsonTicks(k_ideal, k_min, k_max)

"""`LinearTicks(n)`: `n` evenly spaced ticks between the limits (not rounded)."""
struct LinearTicks
    n::Int
end

tick_values(t::WilkinsonTicks, lo, hi) = optimize_ticks(Float64(lo), Float64(hi); k_min = t.k_min, k_max = t.k_max, k_ideal = t.k_ideal)
tick_values(t::LinearTicks, lo, hi) = collect(range(Float64(lo), Float64(hi); length = max(t.n, 2)))
tick_values(t::AbstractVector{<:Real}, lo, hi) = Float64[v for v in t]
tick_values(t::Tuple{AbstractVector, AbstractVector}, lo, hi) = Float64[v for v in t[1]]
tick_values(::Nothing, lo, hi) = Float64[]

# ---------------------------------------------------------------------------------------------
# Labels

const MINUS = '−'

_unminus(s::String) = replace(s, '-' => MINUS)

const SUPERSCRIPT_DIGITS = Dict(zip("0123456789-", "⁰¹²³⁴⁵⁶⁷⁸⁹⁻"))

function _plain(v::Float64, digits::Int)
    s = @sprintf("%.*f", digits, v)
    s = startswith(s, "-") && all(c -> c in "0.-", s) ? s[2:end] : s  # no "-0.0"
    return _unminus(s)
end

"""Fewest decimals that keep every value exact (to 1e-9 relative) and the labels distinct."""
function _decimals(values::Vector{Float64})
    for d in 0:12
        ok = all(values) do v
            r = round(v; digits = d)
            abs(r - v) <= 1e-9 * max(1.0, abs(v))
        end
        ok && return d
    end
    return 12
end

"""Labels for tick `values`, as Makie's default (`Showoff`-style plain decimals, Unicode minus)."""
function format_ticks(values::Vector{Float64})
    isempty(values) && return Any[]
    big = maximum(abs, values)
    small = minimum(v -> v == 0 ? Inf : abs(v), values)
    if big >= 1e6 || (isfinite(small) && small < 1e-4)
        return Any[_scientific(v) for v in values]
    end
    d = _decimals(values)
    return Any[_plain(v, d) for v in values]
end

function _scientific(v::Float64)
    v == 0 && return "0"
    e = floor(Int, log10(abs(v)))
    m = v / 10.0^e
    mant = _plain(round(m; digits = 3), _decimals([round(m; digits = 3)]))
    return rich(mant == "1" ? "" : mant == "−1" ? "−" : mant * "×", "10", superscript(_unminus(string(e))))
end

"""`10ⁿ` labels for log ticks at powers of `base`."""
function _power_label(v::Float64, base::Float64)
    e = log(base, v)
    if isapprox(e, round(e); atol = 1e-9)
        b = base == ℯ ? "e" : string(Int(base))
        return rich(b, superscript(_unminus(string(Int(round(e))))))
    end
    return _plain(v, _decimals([v]))
end

"""A user `tickformat`: a function of the values, or a `"{:.2f}"`-style format string."""
function apply_format(fmt, values::Vector{Float64})
    if fmt isa Function
        # invokelatest: the function may be newer than the caller (a kernel session defines it).
        return Any[l for l in Base.invokelatest(fmt, values)]
    elseif fmt isa AbstractString
        m = match(r"\{:([^}]*)\}", fmt)
        m === nothing && return Any[fmt for _ in values]
        spec = m.captures[1]
        f = _printf_format("%" * spec)
        return Any[_unminus(replace(fmt, m.match => f(v))) for v in values]
    end
    return format_ticks(values)
end

function _printf_format(spec::String)
    m = match(r"^%(\.\d+)?([fegd])$", spec)
    m === nothing && throw(ArgumentError("unsupported tick format \"{:$(spec[2:end])}\"; use {:.Nf}, {:.Ne}, {:.Ng} or {:d}"))
    prec = m.captures[1] === nothing ? nothing : parse(Int, m.captures[1][2:end])
    kind = m.captures[2]
    if kind == "d"
        return v -> string(round(Int, v))
    elseif kind == "f"
        p = something(prec, 6)
        return v -> @sprintf("%.*f", p, v)
    elseif kind == "e"
        p = something(prec, 6)
        return v -> @sprintf("%.*e", p, v)
    else
        p = something(prec, 6)
        return v -> @sprintf("%.*g", p, v)
    end
end

"""Scale functions an axis accepts, and their inverses."""
const SCALES = Dict{Any, Function}(identity => identity, log10 => exp10, log2 => exp2, log => exp, sqrt => (x -> x^2))
is_log(scale) = scale === log10 || scale === log2 || scale === log
log_base(scale) = scale === log10 ? 10.0 : scale === log2 ? 2.0 : ℯ

function inverse(scale)
    haskey(SCALES, scale) || throw(ArgumentError("unsupported axis scale $scale; use identity, log10, log2, log or sqrt"))
    return SCALES[scale]
end

"""
`(values, labels)` for an axis over `[lo, hi]` (data space) with `scale`, the user's `ticks`
spec (`automatic`, a vector, `(values, labels)`, `WilkinsonTicks`, `LinearTicks`) and `format`.
"""
function compute_ticks(ticks, scale, format, lo::Real, hi::Real)
    lo, hi = minmax(Float64(lo), Float64(hi))
    if ticks isa Tuple{AbstractVector, AbstractVector}
        values = Float64[v for v in ticks[1]]
        keep = [lo - 1e-9 * abs(hi - lo) <= v <= hi + 1e-9 * abs(hi - lo) for v in values]
        return values[keep], Any[l for l in ticks[2]][keep]
    end
    ticks === :automatic && (ticks = WilkinsonTicks(5))
    if is_log(scale) && ticks isa WilkinsonTicks
        values = _log_ticks(lo, hi, log_base(scale), ticks)
        labels = format === :automatic ? Any[_power_label(v, log_base(scale)) for v in values] : apply_format(format, values)
        return values, labels
    end
    values = tick_values(ticks, lo, hi)
    values = filter(v -> lo - 1e-9 * abs(hi - lo) <= v <= hi + 1e-9 * abs(hi - lo), values)
    labels = format === :automatic ? format_ticks(values) : apply_format(format, values)
    return values, labels
end

function _log_ticks(lo, hi, base, t::WilkinsonTicks)
    (lo > 0 && hi > 0) || return Float64[]
    elo, ehi = log(base, lo), log(base, hi)
    if floor(ehi) - ceil(elo) >= 1
        exps = ceil(Int, elo - 1e-9):floor(Int, ehi + 1e-9)
        step = max(1, ceil(Int, length(exps) / t.k_max))
        return [base^e for e in exps[1]:step:exps[end]]
    end
    # Less than a decade or two: ordinary nice values inside the range.
    return optimize_ticks(lo, hi; k_min = 2, k_max = t.k_max, k_ideal = 4)
end

"""Minor tick values between the major `values` (`n` intervals each)."""
function minor_ticks(values::Vector{Float64}, n::Int, lo, hi, scale)
    length(values) < 2 && return Float64[]
    out = Float64[]
    if is_log(scale)
        base = log_base(scale)
        for e in floor(Int, log(base, lo)):ceil(Int, log(base, hi))
            for k in 2:(Int(base) - 1)
                v = k * base^e
                lo <= v <= hi && push!(out, v)
            end
        end
        return out
    end
    step = values[2] - values[1]
    first = values[1] - step
    while first + step <= values[end] + step
        for k in 1:(n - 1)
            v = first + k * step / n
            lo <= v <= hi && push!(out, v)
        end
        first += step
    end
    return out
end
