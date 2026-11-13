# Contours. Lines: marching squares with linear interpolation (saddles resolved by the cell
# mean). Filled bands: each grid cell is split into two triangles, and each triangle is clipped
# against the band's [lo, hi] (exact for the piecewise-linear field).

"""The contour levels for `levels` (a count or explicit values) over `z`."""
function contour_levels(levels, Z; filled::Bool = false)
    lo, hi = finite_extrema(Z)
    if levels isa Integer
        lo == hi && return filled ? [lo, hi + 1] : [lo]
        if filled
            return collect(range(lo, hi; length = levels + 1))
        end
        return collect(range(lo, hi; length = levels + 2))[2:(end - 1)]
    end
    return sort!(_vec(levels))
end

_lerp(a, b, t) = a + (b - a) * t

"""Iso-line segments `(x1, y1, x2, y2)` of `Z` at `level`."""
function contour_segments(x::Vector{Float64}, y::Vector{Float64}, Z::Matrix{Float64}, level::Float64)
    segs = NTuple{4, Float64}[]
    nx, ny = size(Z)
    for i in 1:(nx - 1), j in 1:(ny - 1)
        v = (Z[i, j], Z[i + 1, j], Z[i + 1, j + 1], Z[i, j + 1])
        all(isfinite, v) || continue
        p = ((x[i], y[j]), (x[i + 1], y[j]), (x[i + 1], y[j + 1]), (x[i], y[j + 1]))
        case = (v[1] > level) + 2 * (v[2] > level) + 4 * (v[3] > level) + 8 * (v[4] > level)
        (case == 0 || case == 15) && continue
        # crossing on edge k (between corner k and k+1)
        edge(k) = begin
            a, b = k, mod1(k + 1, 4)
            t = (level - v[a]) / (v[b] - v[a])
            (_lerp(p[a][1], p[b][1], t), _lerp(p[a][2], p[b][2], t))
        end
        crossings = [k for k in 1:4 if (v[k] > level) != (v[mod1(k + 1, 4)] > level)]
        if length(crossings) == 2
            a, b = edge(crossings[1]), edge(crossings[2])
            push!(segs, (a[1], a[2], b[1], b[2]))
        elseif length(crossings) == 4
            centre = sum(v) / 4 > level
            # Saddle: pair edges so the high corners connect through the centre (or not).
            # Case 5 has corners 1 and 3 high, case 10 corners 2 and 4.
            pairs = (case == 5) == centre ? ((1, 2), (3, 4)) : ((1, 4), (2, 3))
            for (ea, eb) in pairs
                a, b = edge(ea), edge(eb)
                push!(segs, (a[1], a[2], b[1], b[2]))
            end
        end
    end
    return segs
end

"""Clip a polygon (vertices with values) to `value >= lo` (`keep_above`) or `value <= hi`."""
function _clip(poly::Vector{NTuple{3, Float64}}, level::Float64, keep_above::Bool)
    out = NTuple{3, Float64}[]
    n = length(poly)
    n == 0 && return out
    inside(q) = keep_above ? q[3] >= level : q[3] <= level
    for k in 1:n
        a = poly[k]
        b = poly[mod1(k + 1, n)]
        ia, ib = inside(a), inside(b)
        ia && push!(out, a)
        if ia != ib
            t = (level - a[3]) / (b[3] - a[3])
            push!(out, (_lerp(a[1], b[1], t), _lerp(a[2], b[2], t), level))
        end
    end
    return out
end

"""Filled-contour polygons: `(band index, [(x, y), …])` for bands between consecutive `levels`."""
function contourf_polygons(x::Vector{Float64}, y::Vector{Float64}, Z::Matrix{Float64}, levels::Vector{Float64})
    out = Tuple{Int, Vector{NTuple{2, Float64}}}[]
    nb = length(levels) - 1
    nb < 1 && return out
    band_of(v) = clamp(searchsortedlast(levels, v), 1, nb)
    nx, ny = size(Z)
    for i in 1:(nx - 1), j in 1:(ny - 1)
        c = ((x[i], y[j], Z[i, j]), (x[i + 1], y[j], Z[i + 1, j]), (x[i + 1], y[j + 1], Z[i + 1, j + 1]), (x[i], y[j + 1], Z[i, j + 1]))
        all(q -> isfinite(q[3]), c) || continue
        vals = (c[1][3], c[2][3], c[3][3], c[4][3])
        (maximum(vals) < levels[1] || minimum(vals) > levels[end]) && continue
        b1 = band_of(minimum(vals))
        if b1 == band_of(maximum(vals)) && minimum(vals) >= levels[1] && maximum(vals) <= levels[end]
            push!(out, (b1, [(q[1], q[2]) for q in c]))
            continue
        end
        for tri in ((c[1], c[2], c[3]), (c[1], c[3], c[4]))
            lo3, hi3 = extrema(q[3] for q in tri)
            for b in max(1, band_of(lo3)):min(nb, band_of(hi3))
                poly = _clip(_clip(collect(tri), levels[b], true), levels[b + 1], false)
                length(poly) >= 3 && push!(out, (b, [(q[1], q[2]) for q in poly]))
            end
        end
    end
    return out
end
