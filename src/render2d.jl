# The 2D renderer: Axis, its plots, Colorbar and Label, drawn with Cairo in figure units
# (y down). Every path is vector; only large regular heatmaps and images are rasters.

# ---------------------------------------------------------------------------------------------
# Colours of plots

_crange(cr, values) = cr === :automatic || cr === nothing ? finite_extrema(values) : (Float64(cr[1]), Float64(cr[2]))

"""`(colormap, range, levels)` of a plot that maps values to colours, or `nothing`."""
function color_info(p::Plot{K}) where {K}
    a = getfield(p, :attrs)
    d = converted(p)
    if K === :heatmap
        return (colormap = a[:colormap], range = _crange(a[:colorrange], d.Z), levels = nothing)
    elseif K === :image
        eltype(d.img) <: Real || return nothing
        return (colormap = a[:colormap], range = _crange(a[:colorrange], d.img), levels = nothing)
    elseif K === :surface
        c = a[:color]
        values = c isa AbstractMatrix{<:Real} ? c : d.Z
        return (colormap = a[:colormap], range = _crange(a[:colorrange], values), levels = nothing)
    elseif K === :contourf
        levels = contour_levels(a[:levels], d.Z; filled = true)
        return (colormap = a[:colormap], range = (levels[1], levels[end]), levels = levels)
    elseif K === :contour
        levels = contour_levels(a[:levels], d.Z)
        return (colormap = a[:colormap], range = _crange(a[:colorrange], levels), levels = nothing)
    elseif haskey(a, :color) && a[:color] isa AbstractArray{<:Real} && haskey(a, :colormap)
        return (colormap = a[:colormap], range = _crange(get(a, :colorrange, :automatic), a[:color]), levels = nothing)
    end
    return nothing
end

"""One colour, or one per element when `color` is a vector (numbers go through the colormap)."""
function resolve_colors(color, n::Int, a::Dict{Symbol, Any})
    alpha = Float64(get(a, :alpha, 1.0))
    if color isa AbstractArray{<:Real}
        cmap = to_colormap(a[:colormap])
        r = _crange(get(a, :colorrange, :automatic), color)
        return [with_alpha(colormap_value(cmap, v, r), alpha) for v in vec(color)]
    elseif color isa AbstractVector && !(color isa Tuple)
        return [with_alpha(c, alpha) for c in color]
    end
    return with_alpha(color, alpha)
end

_at(c::AbstractVector, i) = c[mod1(i, length(c))]
_at(c, i) = c

# ---------------------------------------------------------------------------------------------
# Transform

struct T2
    fx::Any
    fy::Any
    x0::Float64
    x1::Float64
    y0::Float64
    y1::Float64
    r::Rect
    xrev::Bool
    yrev::Bool
end

const CLAMP = 1.0e6
function px(t::T2, x)
    v = t.fx(x)
    f = (v - t.x0) / (t.x1 - t.x0)
    t.xrev && (f = 1 - f)
    return clamp(t.r.x + f * t.r.w, -CLAMP, CLAMP)
end
function py(t::T2, y)
    v = t.fy(y)
    f = (v - t.y0) / (t.y1 - t.y0)
    t.yrev && (f = 1 - f)
    return clamp(t.r.y + t.r.h - f * t.r.h, -CLAMP, CLAMP)
end

# ---------------------------------------------------------------------------------------------
# Line styles and markers

const DASHES = Dict{Symbol, Vector{Float64}}(
    :dash => [4.0, 2.5], :dot => [1.0, 1.6], :dashdot => [4.0, 2.0, 1.0, 2.0],
    :dashdotdot => [4.0, 2.0, 1.0, 2.0, 1.0, 2.0],
)
const DASH_STRINGS = Dict("-" => nothing, "--" => :dash, ":" => :dot, "-." => :dashdot, "-.." => :dashdotdot, "." => :dot)

function set_linestyle(ctx::Ctx, ls, lw)
    if ls isa AbstractString
        haskey(DASH_STRINGS, ls) || throw(ArgumentError("unknown linestyle \"$ls\""))
        ls = DASH_STRINGS[ls]
    end
    if ls === nothing || ls === :solid
        set_dash(ctx, Float64[])
    elseif ls isa Symbol
        haskey(DASHES, ls) || throw(ArgumentError("unknown linestyle :$ls; use :solid, :dash, :dot, :dashdot or :dashdotdot"))
        set_dash(ctx, DASHES[ls] .* max(lw, 1.0))
    elseif ls isa AbstractVector
        set_dash(ctx, Float64.(ls) .* max(lw, 1.0))
    else
        throw(ArgumentError("unknown linestyle $(repr(ls))"))
    end
end

function set_stroke(ctx::Ctx, color, lw, ls = nothing)
    set_color(ctx, color)
    set_line_width(ctx, lw)
    set_linestyle(ctx, ls, lw)
    set_line_join(ctx, JOIN_ROUND)
    set_line_cap(ctx, ls === nothing || ls === :solid ? CAP_ROUND : CAP_BUTT)
end

"""Stroke a polyline in pixel space; NaN points break it."""
function polyline!(ctx::Ctx, xs, ys)
    on = false
    for i in eachindex(xs)
        x, y = xs[i], ys[i]
        if !(isfinite(x) && isfinite(y))
            on = false
            continue
        end
        on ? line_to(ctx, x, y) : move_to(ctx, x, y)
        on = true
    end
end

function draw_polyline(ctx::Ctx, xs, ys, color, lw, ls)
    lw > 0 || return
    if color isa AbstractVector
        for i in 1:(length(xs) - 1)
            all(isfinite, (xs[i], ys[i], xs[i + 1], ys[i + 1])) || continue
            set_stroke(ctx, _at(color, i), lw, ls)
            move_to(ctx, xs[i], ys[i])
            line_to(ctx, xs[i + 1], ys[i + 1])
            stroke(ctx)
        end
        return
    end
    set_stroke(ctx, color, lw, ls)
    polyline!(ctx, xs, ys)
    stroke(ctx)
end

const MARKER_ALIASES = Dict{Any, Symbol}(
    'o' => :circle, :o => :circle, '●' => :circle, '+' => :cross, :+ => :cross, 'x' => :xcross, :x => :xcross,
    '×' => :xcross, '*' => :star5, :star => :star5, '^' => :utriangle, 'v' => :dtriangle, '<' => :ltriangle,
    '>' => :rtriangle, 'd' => :diamond, 's' => :rect, :square => :rect, '■' => :rect, '.' => :point, :triangle => :utriangle,
    '|' => :vline, '-' => :hline,
)
const MARKERS = Set([:circle, :rect, :diamond, :utriangle, :dtriangle, :ltriangle, :rtriangle, :cross, :xcross,
    :star5, :star4, :star6, :pentagon, :hexagon, :hline, :vline, :point])

function marker_symbol(m)
    m = get(MARKER_ALIASES, m, m)
    m isa Symbol && m in MARKERS && return m
    throw(ArgumentError("unknown marker $(repr(m)); use one of $(join(sort!(string.(collect(MARKERS))), ", "))"))
end

function _polygon!(ctx::Ctx, x, y, pts)
    move_to(ctx, x + pts[1][1], y + pts[1][2])
    for k in 2:length(pts)
        line_to(ctx, x + pts[k][1], y + pts[k][2])
    end
    close_path(ctx)
end

_regular(n, r, phase) = [(r * cos(phase + 2π * k / n), r * sin(phase + 2π * k / n)) for k in 0:(n - 1)]
function _star(n, r, inner, phase)
    pts = NTuple{2, Float64}[]
    for k in 0:(2n - 1)
        rr = iseven(k) ? r : r * inner
        a = phase + π * k / n
        push!(pts, (rr * cos(a), rr * sin(a)))
    end
    return pts
end
function _cross(r, w, angle)
    base = [(-w, -r), (w, -r), (w, -w), (r, -w), (r, w), (w, w), (w, r), (-w, r), (-w, w), (-r, w), (-r, -w), (-w, -w)]
    c, s = cos(angle), sin(angle)
    return [(c * x - s * y, s * x + c * y) for (x, y) in base]
end

"""Add the path of `marker` (size = full width, in units) centred at `(x, y)`."""
function marker_path!(ctx::Ctx, m::Symbol, x, y, size)
    r = size / 2
    if m === :circle
        new_sub_path(ctx)
        arc(ctx, x, y, r, 0, 2π)
        close_path(ctx)
    elseif m === :point
        new_sub_path(ctx)
        arc(ctx, x, y, r / 2, 0, 2π)
        close_path(ctx)
    elseif m === :rect
        rectangle(ctx, x - r * 0.9, y - r * 0.9, 1.8r, 1.8r)
    elseif m === :diamond
        _polygon!(ctx, x, y, [(0.0, -r), (r, 0.0), (0.0, r), (-r, 0.0)])
    elseif m === :utriangle
        _polygon!(ctx, x, y, _regular(3, r * 1.1, -π / 2))
    elseif m === :dtriangle
        _polygon!(ctx, x, y, _regular(3, r * 1.1, π / 2))
    elseif m === :ltriangle
        _polygon!(ctx, x, y, _regular(3, r * 1.1, π))
    elseif m === :rtriangle
        _polygon!(ctx, x, y, _regular(3, r * 1.1, 0.0))
    elseif m === :pentagon
        _polygon!(ctx, x, y, _regular(5, r, -π / 2))
    elseif m === :hexagon
        _polygon!(ctx, x, y, _regular(6, r, 0.0))
    elseif m === :star5
        _polygon!(ctx, x, y, _star(5, r * 1.1, 0.45, -π / 2))
    elseif m === :star4
        _polygon!(ctx, x, y, _star(4, r * 1.1, 0.4, -π / 2))
    elseif m === :star6
        _polygon!(ctx, x, y, _star(6, r * 1.1, 0.5, -π / 2))
    elseif m === :cross
        _polygon!(ctx, x, y, _cross(r, r / 4, 0.0))
    elseif m === :xcross
        _polygon!(ctx, x, y, _cross(r, r / 4, π / 4))
    elseif m === :hline
        rectangle(ctx, x - r, y - r / 5, 2r, 2r / 5)
    elseif m === :vline
        rectangle(ctx, x - r / 5, y - r, 2r / 5, 2r)
    end
end

function draw_markers(ctx::Ctx, xs, ys, marker, size, color, strokecolor, strokewidth)
    markers = marker isa AbstractVector ? [marker_symbol(m) for m in marker] : marker_symbol(marker)
    for i in eachindex(xs)
        x, y = xs[i], ys[i]
        (isfinite(x) && isfinite(y)) || continue
        new_path(ctx)
        marker_path!(ctx, _at(markers, i), x, y, Float64(_at(size, i)))
        set_color(ctx, _at(color, i))
        if strokewidth > 0
            fill_preserve(ctx)
            set_color(ctx, _at(strokecolor, i))
            set_line_width(ctx, strokewidth)
            set_dash(ctx, Float64[])
            stroke(ctx)
        else
            fillpath(ctx)
        end
    end
end

function fill_polygon(ctx::Ctx, xs, ys, color; seam::Bool = false, strokecolor = nothing, strokewidth = 0.0)
    length(xs) < 3 && return
    new_path(ctx)
    polyline!(ctx, xs, ys)
    close_path(ctx)
    set_color(ctx, color)
    if strokewidth > 0 && strokecolor !== nothing
        fill_preserve(ctx)
        set_stroke(ctx, strokecolor, strokewidth)
        stroke(ctx)
    elseif seam
        # Cover the antialiasing seam between neighbouring cells with a hairline of the same colour.
        fill_preserve(ctx)
        set_line_width(ctx, 0.6)
        set_dash(ctx, Float64[])
        set_line_join(ctx, JOIN_ROUND)
        stroke(ctx)
    else
        fillpath(ctx)
    end
end

# ---------------------------------------------------------------------------------------------
# Plots

function draw2d(ctx::Ctx, p::Plot{K}, t::T2) where {K}
    a = getfield(p, :attrs)
    a[:visible] || return
    d = converted(p)
    if K in (:lines, :stairs, :linesegments)
        x, y = K === :stairs ? stair_points(d.x, d.y, a[:step]) : (d.x, d.y)
        xs, ys = [px(t, v) for v in x], [py(t, v) for v in y]
        color = resolve_colors(a[:color], length(xs), a)
        if K === :linesegments
            for i in 1:2:(length(xs) - 1)
                draw_polyline(ctx, xs[i:(i + 1)], ys[i:(i + 1)], _at(color, i), a[:linewidth], a[:linestyle])
            end
        else
            draw_polyline(ctx, xs, ys, color, a[:linewidth], a[:linestyle])
        end
    elseif K === :scatter
        xs, ys = [px(t, v) for v in d.x], [py(t, v) for v in d.y]
        draw_markers(ctx, xs, ys, a[:marker], a[:markersize], resolve_colors(a[:color], length(xs), a),
            to_color(a[:strokecolor]), a[:strokewidth])
    elseif K === :scatterlines
        xs, ys = [px(t, v) for v in d.x], [py(t, v) for v in d.y]
        color = resolve_colors(a[:color], length(xs), a)
        draw_polyline(ctx, xs, ys, color, a[:linewidth], a[:linestyle])
        mc = a[:markercolor] === :inherit ? color : resolve_colors(a[:markercolor], length(xs), a)
        draw_markers(ctx, xs, ys, a[:marker], a[:markersize], mc, to_color(a[:strokecolor]), a[:strokewidth])
    elseif K === :stem
        color = resolve_colors(a[:color], length(d.x), a)
        stemc = a[:stemcolor] === :inherit ? color : resolve_colors(a[:stemcolor], length(d.x), a)
        trunkc = a[:trunkcolor] === :inherit ? (color isa AbstractVector ? to_color(:black) : color) : to_color(a[:trunkcolor])
        off = a[:offset]
        base(i) = off isa Real ? Float64(off) : Float64(off[i])
        xs, ys = [px(t, v) for v in d.x], [py(t, v) for v in d.y]
        bs = [py(t, base(i)) for i in eachindex(d.x)]
        if length(xs) > 1
            order = sortperm(d.x)
            draw_polyline(ctx, xs[order], bs[order], trunkc, a[:trunkwidth], a[:trunklinestyle])
        end
        for i in eachindex(xs)
            draw_polyline(ctx, [xs[i], xs[i]], [bs[i], ys[i]], _at(stemc, i), a[:stemwidth], a[:stemlinestyle])
        end
        draw_markers(ctx, xs, ys, a[:marker], a[:markersize], color, to_color(a[:strokecolor]), a[:strokewidth])
    elseif K === :barplot || K === :hist
        if K === :hist
            c, h, w = hist_bars(d.values, a[:bins], a[:normalization])
            rects = [(c[i] - w[i] / 2 * (1 - a[:gap]), c[i] + w[i] / 2 * (1 - a[:gap]), Float64(a[:fillto]), h[i]) for i in eachindex(c)]
            a[:direction] === :x && (rects = [(r[3], r[4], r[1], r[2]) for r in rects])
        else
            rects = bar_rects(d.x, d.y, a[:width], a[:gap], a[:fillto], a[:direction])
        end
        color = resolve_colors(a[:color], length(rects), a)
        for (i, (x0, x1, y0, y1)) in enumerate(rects)
            X0, X1, Y0, Y1 = px(t, x0), px(t, x1), py(t, y0), py(t, y1)
            all(isfinite, (X0, X1, Y0, Y1)) || continue
            fill_polygon(ctx, [X0, X1, X1, X0], [Y0, Y0, Y1, Y1], _at(color, i);
                strokecolor = to_color(a[:strokecolor]), strokewidth = a[:strokewidth])
        end
    elseif K === :errorbars
        color = resolve_colors(a[:color], length(d.x), a)
        ww = a[:whiskerwidth] / 2
        for i in eachindex(d.x)
            if a[:direction] === :y
                X, Y0, Y1 = px(t, d.x[i]), py(t, d.y[i] - d.low[i]), py(t, d.y[i] + d.high[i])
                draw_polyline(ctx, [X, X], [Y0, Y1], _at(color, i), a[:linewidth], nothing)
                if ww > 0
                    draw_polyline(ctx, [X - ww, X + ww], [Y0, Y0], _at(color, i), a[:linewidth], nothing)
                    draw_polyline(ctx, [X - ww, X + ww], [Y1, Y1], _at(color, i), a[:linewidth], nothing)
                end
            else
                Y, X0, X1 = py(t, d.y[i]), px(t, d.x[i] - d.low[i]), px(t, d.x[i] + d.high[i])
                draw_polyline(ctx, [X0, X1], [Y, Y], _at(color, i), a[:linewidth], nothing)
                if ww > 0
                    draw_polyline(ctx, [X0, X0], [Y - ww, Y + ww], _at(color, i), a[:linewidth], nothing)
                    draw_polyline(ctx, [X1, X1], [Y - ww, Y + ww], _at(color, i), a[:linewidth], nothing)
                end
            end
        end
    elseif K === :band
        xs = [[px(t, v) for v in d.x]; reverse([px(t, v) for v in d.x])]
        ys = [[py(t, v) for v in d.hi]; reverse([py(t, v) for v in d.lo])]
        fill_polygon(ctx, xs, ys, resolve_colors(a[:color], 1, a))
    elseif K === :area
        color = resolve_colors(a[:color], 1, a)
        xs = [px(t, v) for v in d.x]
        ys = [py(t, v) for v in d.y]
        b = py(t, a[:baseline])
        if !isempty(xs)
            fill_polygon(ctx, [xs; xs[end]; xs[1]], [ys; b; b], with_alpha(color, a[:fillalpha]))
            draw_polyline(ctx, xs, ys, color, a[:linewidth], a[:linestyle])
        end
    elseif K === :heatmap
        draw_heatmap(ctx, p, d, t)
    elseif K === :image
        draw_image(ctx, p, d, t)
    elseif K === :contour
        levels = contour_levels(a[:levels], d.Z)
        r = _crange(a[:colorrange], levels)
        cmap = to_colormap(a[:colormap])
        for lv in levels
            c = a[:color] === nothing ? colormap_value(cmap, lv, r) : to_color(a[:color])
            set_stroke(ctx, with_alpha(c, a[:alpha]), a[:linewidth], a[:linestyle])
            new_path(ctx)
            for (x1, y1, x2, y2) in contour_segments(d.x, d.y, d.Z, lv)
                move_to(ctx, px(t, x1), py(t, y1))
                line_to(ctx, px(t, x2), py(t, y2))
            end
            stroke(ctx)
        end
    elseif K === :contourf
        levels = contour_levels(a[:levels], d.Z; filled = true)
        cmap = to_colormap(a[:colormap])
        nb = length(levels) - 1
        colors = [with_alpha(sample(cmap, nb == 1 ? 0.5 : (b - 1) / (nb - 1)), a[:alpha]) for b in 1:nb]
        # One path per band (cells never overlap): a few large paths instead of one per cell.
        bands = [Vector{NTuple{2, Float64}}[] for _ in 1:nb]
        for (b, poly) in contourf_polygons(d.x, d.y, d.Z, levels)
            push!(bands[b], poly)
        end
        for b in 1:nb
            isempty(bands[b]) && continue
            new_path(ctx)
            for poly in bands[b]
                polyline!(ctx, [px(t, q[1]) for q in poly], [py(t, q[2]) for q in poly])
                close_path(ctx)
            end
            set_color(ctx, colors[b])
            fill_preserve(ctx)
            set_line_width(ctx, 0.6)    # the same colour over the antialiasing seams between cells
            set_dash(ctx, Float64[])
            set_line_join(ctx, JOIN_ROUND)
            stroke(ctx)
        end
    elseif K === :text
        draw_text_plot(ctx, p, d, t)
    elseif K === :hlines
        color = resolve_colors(a[:color], length(d.values), a)
        for (i, v) in enumerate(d.values)
            Y = py(t, v)
            draw_polyline(ctx, [t.r.x + _at(a[:xmin], i) * t.r.w, t.r.x + _at(a[:xmax], i) * t.r.w], [Y, Y], _at(color, i), a[:linewidth], a[:linestyle])
        end
    elseif K === :vlines
        color = resolve_colors(a[:color], length(d.values), a)
        for (i, v) in enumerate(d.values)
            X = px(t, v)
            draw_polyline(ctx, [X, X], [t.r.y + t.r.h - _at(a[:ymin], i) * t.r.h, t.r.y + t.r.h - _at(a[:ymax], i) * t.r.h], _at(color, i), a[:linewidth], a[:linestyle])
        end
    elseif K === :ablines
        color = resolve_colors(a[:color], length(d.a), a)
        gx = inverse(getfield(p, :axis).attrs[:xscale])
        xs = [gx(v) for v in range(t.x0, t.x1; length = 64)]
        for i in eachindex(d.a)
            draw_polyline(ctx, [px(t, x) for x in xs], [py(t, d.a[i] + d.b[i] * x) for x in xs], _at(color, i), a[:linewidth], a[:linestyle])
        end
    elseif K === :poly
        fill_polygon(ctx, [px(t, v) for v in d.x], [py(t, v) for v in d.y], resolve_colors(a[:color], 1, a);
            strokecolor = to_color(a[:strokecolor]), strokewidth = a[:strokewidth])
    elseif K === :series || K === :multiline
        n = size(d.Y, 1)
        colors = series_colors(a[:color], n)
        xs = [px(t, v) for v in d.x]
        for s in 1:n
            ys = [py(t, v) for v in view(d.Y, s, :)]
            draw_polyline(ctx, xs, ys, with_alpha(colors[s], a[:alpha]), a[:linewidth], a[:linestyle])
            a[:marker] === nothing || draw_markers(ctx, xs, ys, a[:marker], a[:markersize], colors[s], colors[s], 0.0)
        end
    elseif K === :surface
        values = a[:color] isa AbstractMatrix{<:Real} ? a[:color] : d.Z
        cmap = to_colormap(a[:colormap])
        r = _crange(a[:colorrange], values)
        nx, ny = size(d.Z)
        for i in 1:(nx - 1), j in 1:(ny - 1)
            v = (values[i, j] + values[i + 1, j] + values[i + 1, j + 1] + values[i, j + 1]) / 4
            c = a[:color] isa Union{Symbol, Colorant, AbstractString} ? to_color(a[:color]) : colormap_value(cmap, v, r)
            fill_polygon(ctx, [px(t, d.X[i, j]), px(t, d.X[i + 1, j]), px(t, d.X[i + 1, j + 1]), px(t, d.X[i, j + 1])],
                [py(t, d.Y[i, j]), py(t, d.Y[i + 1, j]), py(t, d.Y[i + 1, j + 1]), py(t, d.Y[i, j + 1])],
                with_alpha(c, a[:alpha]); seam = a[:strokewidth] == 0, strokecolor = to_color(a[:strokecolor]), strokewidth = a[:strokewidth])
        end
    elseif K === :wireframe
        color = resolve_colors(a[:color], 1, a)
        nx, ny = size(d.Z)
        for i in 1:nx
            draw_polyline(ctx, [px(t, d.X[i, j]) for j in 1:ny], [py(t, d.Y[i, j]) for j in 1:ny], color, a[:linewidth], a[:linestyle])
        end
        for j in 1:ny
            draw_polyline(ctx, [px(t, d.X[i, j]) for i in 1:nx], [py(t, d.Y[i, j]) for i in 1:nx], color, a[:linewidth], a[:linestyle])
        end
    elseif K === :mesh
        colors = mesh_vertex_colors(a, d)
        for f in 1:size(d.F, 1)
            ids = d.F[f, :]
            c = mesh_face_color(a, colors, ids)
            fill_polygon(ctx, [px(t, d.V[k, 1]) for k in ids], [py(t, d.V[k, 2]) for k in ids], c; seam = a[:strokewidth] == 0,
                strokecolor = to_color(a[:strokecolor]), strokewidth = a[:strokewidth])
        end
    elseif K === :annotation
        draw_annotation(ctx, p, d, t)
    end
    return nothing
end

function _mean_color(cs)
    n = length(cs)
    return RGBAf(sum(red, cs) / n, sum(green, cs) / n, sum(blue, cs) / n, sum(alpha, cs) / n)
end

function mesh_vertex_colors(a, d)
    c = a[:color]
    if c isa AbstractVector{<:Real}
        length(c) == size(d.V, 1) || throw(DimensionMismatch("mesh: $(length(c)) colour values for $(size(d.V, 1)) vertices"))
    end
    return resolve_colors(c, size(d.V, 1), a)
end

"""A face's colour: numbers per vertex are averaged and then mapped (not the mapped colours averaged)."""
function mesh_face_color(a, colors, ids)
    c = a[:color]
    if c isa AbstractVector{<:Real}
        r = _crange(get(a, :colorrange, :automatic), c)
        v = sum(Float64(c[k]) for k in ids) / length(ids)
        return with_alpha(colormap_value(to_colormap(a[:colormap]), v, r), get(a, :alpha, 1.0))
    end
    return colors isa AbstractVector ? _mean_color(colors[ids]) : colors
end

function _uniform(e::Vector{Float64})
    length(e) < 3 && return true
    s = e[2] - e[1]
    return all(i -> isapprox(e[i + 1] - e[i], s; rtol = 1e-6), 1:(length(e) - 1))
end

function draw_heatmap(ctx::Ctx, p::Plot, d, t::T2)
    a = getfield(p, :attrs)
    cmap = to_colormap(a[:colormap])
    r = _crange(a[:colorrange], d.Z)
    nan = to_color(a[:nan_color])
    nx, ny = size(d.Z)
    colorof(v) = with_alpha(colormap_value(cmap, v, r; nan_color = nan), a[:alpha])
    linear = t.fx === identity || getfield(p, :axis).attrs[:xscale] === identity
    linear &= getfield(p, :axis).attrs[:yscale] === identity
    if linear && _uniform(d.xe) && _uniform(d.ye) && (nx * ny > 2500 || a[:interpolate])
        pixels = Matrix{UInt32}(undef, ny, nx)
        for i in 1:nx, j in 1:ny
            pixels[ny - j + 1, i] = argb32(colorof(d.Z[i, j]))
        end
        X0, X1 = px(t, d.xe[1]), px(t, d.xe[end])
        Y0, Y1 = py(t, d.ye[1]), py(t, d.ye[end])
        X0 > X1 && (pixels = pixels[:, end:-1:1]; (X0, X1) = (X1, X0))
        Y1 > Y0 && (pixels = pixels[end:-1:1, :]; (Y0, Y1) = (Y1, Y0))
        draw_raster(ctx, pixels, X0, Y1, X1 - X0, Y0 - Y1; smooth = a[:interpolate])
        return
    end
    for i in 1:nx, j in 1:ny
        X0, X1 = px(t, d.xe[i]), px(t, d.xe[i + 1])
        Y0, Y1 = py(t, d.ye[j]), py(t, d.ye[j + 1])
        all(isfinite, (X0, X1, Y0, Y1)) || continue
        c = colorof(d.Z[i, j])
        alpha(c) == 0 && continue
        new_path(ctx)
        rectangle(ctx, min(X0, X1) - 0.25, min(Y0, Y1) - 0.25, abs(X1 - X0) + 0.5, abs(Y1 - Y0) + 0.5)
        set_color(ctx, c)
        fillpath(ctx)
    end
end

function draw_image(ctx::Ctx, p::Plot, d, t::T2)
    a = getfield(p, :attrs)
    img = d.img
    nx, ny = size(img)
    if eltype(img) <: Real
        cmap = to_colormap(a[:colormap])
        r = _crange(a[:colorrange], img)
        colorof = v -> with_alpha(colormap_value(cmap, v, r), a[:alpha])
    else
        colorof = c -> with_alpha(c, a[:alpha])
    end
    pixels = Matrix{UInt32}(undef, ny, nx)
    for i in 1:nx, j in 1:ny
        pixels[ny - j + 1, i] = argb32(colorof(img[i, j]))
    end
    X0, X1 = px(t, d.x[1]), px(t, d.x[2])
    Y0, Y1 = py(t, d.y[1]), py(t, d.y[2])
    X0 > X1 && (pixels = pixels[:, end:-1:1]; (X0, X1) = (X1, X0))
    Y1 > Y0 && (pixels = pixels[end:-1:1, :]; (Y0, Y1) = (Y1, Y0))
    draw_raster(ctx, pixels, X0, Y1, X1 - X0, Y0 - Y1; smooth = a[:interpolate])
end

function _align_pair(align)
    h, v = align
    v = v === :baseline ? :baseline : v
    return h, v
end

function draw_text_plot(ctx::Ctx, p::Plot, d, t)
    a = getfield(p, :attrs)
    texts = d.text === nothing ? a[:text] : d.text
    if isempty(d.x)
        pos = a[:position]
        pos === nothing && return
        xs, ys = [Float64(pos[1])], [Float64(pos[2])]
    else
        xs, ys = d.x, d.y
    end
    h, v = _align_pair(a[:align])
    for i in eachindex(xs)
        s = texts isa AbstractVector ? texts[mod1(i, length(texts))] : texts
        off = a[:offset]
        o = off isa AbstractVector ? off[mod1(i, length(off))] : off
        X, Y = t isa T2 ? (px(t, xs[i]), py(t, ys[i])) : t(i)
        draw_text(ctx, s, X + o[1], Y - o[2]; size = _at(a[:fontsize], i), font = a[:font],
            color = with_alpha(_at(a[:color] isa AbstractVector ? a[:color] : [a[:color]], i), a[:alpha]),
            halign = h, valign = v, rotation = _at(a[:rotation], i))
    end
end

function draw_arrow(ctx::Ctx, x0, y0, x1, y1, color, lw, head)
    set_stroke(ctx, color, lw)
    move_to(ctx, x0, y0)
    line_to(ctx, x1, y1)
    stroke(ctx)
    ang = atan(y1 - y0, x1 - x0)
    new_path(ctx)
    move_to(ctx, x1, y1)
    line_to(ctx, x1 - head * cos(ang - 0.4), y1 - head * sin(ang - 0.4))
    line_to(ctx, x1 - head * cos(ang + 0.4), y1 - head * sin(ang + 0.4))
    close_path(ctx)
    set_color(ctx, color)
    fillpath(ctx)
end

function draw_annotation(ctx::Ctx, p::Plot, d, t::T2)
    a = getfield(p, :attrs)
    tx, ty = px(t, d.xt), py(t, d.yt)
    x, y = px(t, d.x), py(t, d.y)
    w, h = text_size(a[:text], a[:fontsize])
    draw_text(ctx, a[:text], tx, ty; size = a[:fontsize], color = a[:color], halign = :center, valign = :center)
    dx, dy = x - tx, y - ty
    len = hypot(dx, dy)
    len < 1 && return
    # leave the text's box along the arrow's direction
    s = min(abs(dx) > 0 ? (w / 2 + 4) / abs(dx) : Inf, abs(dy) > 0 ? (h / 2 + 4) / abs(dy) : Inf)
    s >= 1 && return
    draw_arrow(ctx, tx + dx * s, ty + dy * s, x - dx / len * 2, y - dy / len * 2, to_color(a[:color]), a[:linewidth], a[:arrowsize])
end

# ---------------------------------------------------------------------------------------------
# Axis

function draw_block(ctx::Ctx, ax::Axis, r::Rect, st::AxisState)
    a = getfield(ax, :attrs)
    t = T2(_safe(a[:xscale]), _safe(a[:yscale]), st.xlims..., st.ylims..., r, st.xreversed, st.yreversed)
    bg = to_color(a[:backgroundcolor])
    if alpha(bg) > 0
        new_path(ctx)
        rectangle(ctx, r.x, r.y, r.w, r.h)
        set_color(ctx, bg)
        fillpath(ctx)
    end
    inx(X) = r.x - 0.5 <= X <= r.x + r.w + 0.5
    iny(Y) = r.y - 0.5 <= Y <= r.y + r.h + 0.5
    # grid
    for (vis, vals, color, width, style) in (
            (a[:xminorgridvisible], st.xminor, a[:xminorgridcolor], a[:xgridwidth], a[:xgridstyle]),
            (a[:xgridvisible], st.xticks, a[:xgridcolor], a[:xgridwidth], a[:xgridstyle]))
        vis || continue
        for v in vals
            X = px(t, v)
            inx(X) && draw_polyline(ctx, [X, X], [r.y, r.y + r.h], to_color(color), width, style)
        end
    end
    for (vis, vals, color, width, style) in (
            (a[:yminorgridvisible], st.yminor, a[:yminorgridcolor], a[:ygridwidth], a[:ygridstyle]),
            (a[:ygridvisible], st.yticks, a[:ygridcolor], a[:ygridwidth], a[:ygridstyle]))
        vis || continue
        for v in vals
            Y = py(t, v)
            iny(Y) && draw_polyline(ctx, [r.x, r.x + r.w], [Y, Y], to_color(color), width, style)
        end
    end
    # plots, clipped to the plot area
    gsave(ctx)
    new_path(ctx)
    rectangle(ctx, r.x, r.y, r.w, r.h)
    clip(ctx)
    for p in ax.plots
        draw2d(ctx, p, t)
    end
    grestore(ctx)
    # spines
    sw, sc = a[:spinewidth], to_color(a[:spinecolor])
    for (vis, x0, y0, x1, y1) in ((a[:leftspinevisible], r.x, r.y, r.x, r.y + r.h),
            (a[:rightspinevisible], r.x + r.w, r.y, r.x + r.w, r.y + r.h),
            (a[:topspinevisible], r.x, r.y, r.x + r.w, r.y),
            (a[:bottomspinevisible], r.x, r.y + r.h, r.x + r.w, r.y + r.h))
        vis || continue
        set_stroke(ctx, sc, sw)
        set_line_cap(ctx, CAP_SQUARE)
        move_to(ctx, x0, y0)
        line_to(ctx, x1, y1)
        stroke(ctx)
    end
    # x axis
    top = a[:xaxisposition] === :top
    yb = top ? r.y : r.y + r.h
    dir = top ? -1.0 : 1.0
    out = a[:xticksvisible] ? a[:xticksize] * (1 - a[:xtickalign]) : 0.0
    if a[:xticksvisible]
        tin = a[:xticksize] * a[:xtickalign]
        for (vals, size) in ((st.xticks, a[:xticksize]), (a[:xminorticksvisible] ? st.xminor : Float64[], a[:xminorticksize]))
            for v in vals
                X = px(t, v)
                inx(X) || continue
                f = size / a[:xticksize]
                draw_polyline(ctx, [X, X], [yb - dir * tin * f, yb + dir * out * f], to_color(a[:xtickcolor]), a[:xtickwidth], nothing)
            end
        end
    end
    yl = yb + dir * out
    if a[:xticklabelsvisible] && !isempty(st.xlabels)
        rot = Float64(a[:xticklabelrotation])
        for (v, l) in zip(st.xticks, st.xlabels)
            X = px(t, v)
            inx(X) || continue
            draw_text(ctx, l, X, yl + dir * a[:xticklabelpad]; size = a[:xticklabelsize], color = a[:xticklabelcolor],
                halign = rot == 0 ? :center : rot > 0 ? :right : :left, valign = top ? :bottom : (rot == 0 ? :top : :center), rotation = rot)
        end
        yl += dir * (a[:xticklabelpad] + _text_extent(st.xlabels, a[:xticklabelsize], rot)[2])
    end
    if a[:xlabelvisible] && !is_empty_text(a[:xlabel])
        draw_text(ctx, a[:xlabel], r.x + r.w / 2, yl + dir * a[:xlabelpadding]; size = a[:xlabelsize], font = a[:xlabelfont],
            color = a[:xlabelcolor], halign = :center, valign = top ? :bottom : :top)
    end
    # y axis
    right = a[:yaxisposition] === :right
    xb = right ? r.x + r.w : r.x
    sgn = right ? 1.0 : -1.0
    yout = a[:yticksvisible] ? a[:yticksize] * (1 - a[:ytickalign]) : 0.0
    if a[:yticksvisible]
        tin = a[:yticksize] * a[:ytickalign]
        for (vals, size) in ((st.yticks, a[:yticksize]), (a[:yminorticksvisible] ? st.yminor : Float64[], a[:yminorticksize]))
            for v in vals
                Y = py(t, v)
                iny(Y) || continue
                f = size / a[:yticksize]
                draw_polyline(ctx, [xb - sgn * tin * f, xb + sgn * yout * f], [Y, Y], to_color(a[:ytickcolor]), a[:ytickwidth], nothing)
            end
        end
    end
    xl = xb + sgn * yout
    if a[:yticklabelsvisible] && !isempty(st.ylabels)
        for (v, l) in zip(st.yticks, st.ylabels)
            Y = py(t, v)
            iny(Y) || continue
            draw_text(ctx, l, xl + sgn * a[:yticklabelpad], Y; size = a[:yticklabelsize], color = a[:yticklabelcolor],
                halign = right ? :left : :right, valign = :center, rotation = Float64(a[:yticklabelrotation]))
        end
        xl += sgn * (a[:yticklabelpad] + _text_extent(st.ylabels, a[:yticklabelsize], Float64(a[:yticklabelrotation]))[1])
    end
    if a[:ylabelvisible] && !is_empty_text(a[:ylabel])
        draw_text(ctx, a[:ylabel], xl + sgn * a[:ylabelpadding], r.y + r.h / 2; size = a[:ylabelsize], font = a[:ylabelfont],
            color = a[:ylabelcolor], halign = :center, valign = right ? :top : :bottom, rotation = π / 2)
    end
    # title and subtitle
    ytitle = top ? yl - a[:titlegap] : r.y - a[:titlegap]
    tx = a[:titlealign] === :left ? r.x : a[:titlealign] === :right ? r.x + r.w : r.x + r.w / 2
    if a[:subtitlevisible] && !is_empty_text(a[:subtitle])
        draw_text(ctx, a[:subtitle], tx, ytitle; size = a[:subtitlesize], font = a[:subtitlefont], color = a[:subtitlecolor],
            halign = a[:titlealign], valign = :bottom)
        ytitle -= text_size(a[:subtitle], a[:subtitlesize])[2] + a[:subtitlegap]
    end
    if a[:titlevisible] && !is_empty_text(a[:title])
        draw_text(ctx, a[:title], tx, ytitle; size = a[:titlesize], font = a[:titlefont], color = a[:titlecolor],
            halign = a[:titlealign], valign = :bottom)
    end
    for lg in ax.legends
        draw_axislegend(ctx, lg, r)
    end
end

# ---------------------------------------------------------------------------------------------
# Colorbar and Label

function draw_block(ctx::Ctx, cb::Colorbar, r::Rect, st::ColorbarState)
    a = getfield(cb, :attrs)
    lo, hi = st.lims
    vertical = a[:vertical]
    frac(v) = (v - lo) / (hi - lo)
    if st.levels !== nothing
        lv = st.levels
        nb = length(lv) - 1
        for b in 1:nb
            c = sample(st.cmap, nb == 1 ? 0.5 : (b - 1) / (nb - 1))
            f0, f1 = clamp(frac(lv[b]), 0, 1), clamp(frac(lv[b + 1]), 0, 1)
            new_path(ctx)
            if vertical
                rectangle(ctx, r.x, r.y + r.h * (1 - f1), r.w, r.h * (f1 - f0) + 0.3)
            else
                rectangle(ctx, r.x + r.w * f0, r.y, r.w * (f1 - f0) + 0.3, r.h)
            end
            set_color(ctx, c)
            fillpath(ctx)
        end
    else
        n = length(st.cmap)
        stops = [((k - 1) / (n - 1), st.cmap[k]) for k in 1:n]
        new_path(ctx)
        rectangle(ctx, r.x, r.y, r.w, r.h)
        vertical ? linear_gradient(ctx, 0, r.y + r.h, 0, r.y, stops) : linear_gradient(ctx, r.x, 0, r.x + r.w, 0, stops)
        fillpath(ctx)
    end
    set_stroke(ctx, a[:spinecolor], a[:spinewidth])
    rectangle(ctx, r.x, r.y, r.w, r.h)
    stroke(ctx)
    flip = a[:flipaxis]
    ts = a[:ticksvisible] ? a[:ticksize] : 0.0
    if vertical
        xb = flip ? r.x + r.w : r.x
        s = flip ? 1.0 : -1.0
        for (v, l) in zip(st.ticks, st.labels)
            Y = r.y + r.h * (1 - frac(v))
            ts > 0 && draw_polyline(ctx, [xb, xb + s * ts], [Y, Y], to_color(a[:tickcolor]), a[:tickwidth], nothing)
            a[:ticklabelsvisible] && draw_text(ctx, l, xb + s * (ts + a[:ticklabelpad]), Y; size = a[:ticklabelsize],
                color = a[:ticklabelcolor], halign = flip ? :left : :right, valign = :center)
        end
        if a[:labelvisible] && !is_empty_text(a[:label])
            w = a[:ticklabelsvisible] && !isempty(st.labels) ? _text_extent(st.labels, a[:ticklabelsize])[1] + a[:ticklabelpad] : 0.0
            draw_text(ctx, a[:label], xb + s * (ts + w + a[:labelpadding]), r.y + r.h / 2; size = a[:labelsize],
                font = a[:labelfont], color = a[:labelcolor], halign = :center, valign = flip ? :top : :bottom, rotation = π / 2)
        end
    else
        yb = flip ? r.y + r.h : r.y
        s = flip ? 1.0 : -1.0
        for (v, l) in zip(st.ticks, st.labels)
            X = r.x + r.w * frac(v)
            ts > 0 && draw_polyline(ctx, [X, X], [yb, yb + s * ts], to_color(a[:tickcolor]), a[:tickwidth], nothing)
            a[:ticklabelsvisible] && draw_text(ctx, l, X, yb + s * (ts + a[:ticklabelpad]); size = a[:ticklabelsize],
                color = a[:ticklabelcolor], halign = :center, valign = flip ? :top : :bottom)
        end
        if a[:labelvisible] && !is_empty_text(a[:label])
            h = a[:ticklabelsvisible] && !isempty(st.labels) ? _text_extent(st.labels, a[:ticklabelsize])[2] + a[:ticklabelpad] : 0.0
            draw_text(ctx, a[:label], r.x + r.w / 2, yb + s * (ts + h + a[:labelpadding]); size = a[:labelsize],
                font = a[:labelfont], color = a[:labelcolor], halign = :center, valign = flip ? :top : :bottom)
        end
    end
end

function draw_block(ctx::Ctx, lb::Label, r::Rect, st)
    a = getfield(lb, :attrs)
    a[:visible] || return
    p = a[:padding]
    x = r.x + p[1] + (r.w - p[1] - p[2]) / 2
    y = r.y + p[4] + (r.h - p[3] - p[4]) / 2
    draw_text(ctx, a[:text], x, y; size = a[:fontsize], font = a[:font], color = a[:color], halign = :center,
        valign = :center, rotation = Float64(a[:rotation]))
end
