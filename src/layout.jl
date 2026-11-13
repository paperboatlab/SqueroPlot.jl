# Layout: every placed block is prepared (limits, ticks, the space its decorations need), then
# the grid is solved into rectangles. As in Makie, a block's "protrusions" (tick labels, axis
# labels, title) sit outside its inner rectangle, and columns/rows take the largest protrusion
# of their content, so the plot areas of a grid line up.

struct Rect
    x::Float64
    y::Float64
    w::Float64
    h::Float64
end

const NO_PROTRUSION = (0.0, 0.0, 0.0, 0.0)  # left, right, top, bottom

# ---------------------------------------------------------------------------------------------
# Extents of plots in scaled space

mutable struct Extent
    xlo::Float64
    xhi::Float64
    ylo::Float64
    yhi::Float64
    tight::Bool
end
Extent() = Extent(Inf, -Inf, Inf, -Inf, true)

function addx!(e::Extent, f, xs)
    for x in xs
        v = f(x)
        if v isa Real && isfinite(v)
            e.xlo = min(e.xlo, v)
            e.xhi = max(e.xhi, v)
        end
    end
end
function addy!(e::Extent, f, ys)
    for y in ys
        v = f(y)
        if v isa Real && isfinite(v)
            e.ylo = min(e.ylo, v)
            e.yhi = max(e.yhi, v)
        end
    end
end

_safe(f) = x -> (x isa Real && (f === identity || x > 0 || (f === sqrt && x >= 0))) ? f(x) : NaN

"""Grow `e` by the data of `p` (in the axis' scaled space)."""
function extend!(e::Extent, p::Plot{K}, fx, fy) where {K}
    attr(p, :visible) || return e
    d = converted(p)
    sx, sy = _safe(fx), _safe(fy)
    loose = true
    if K in (:lines, :scatter, :scatterlines, :linesegments, :stairs, :text, :poly, :area)
        addx!(e, sx, d.x)
        addy!(e, sy, d.y)
        K === :area && addy!(e, sy, (attr(p, :baseline),))
        K === :text && attr(p, :position) !== nothing && (addx!(e, sx, (attr(p, :position)[1],)); addy!(e, sy, (attr(p, :position)[2],)))
    elseif K === :stem
        addx!(e, sx, d.x)
        addy!(e, sy, d.y)
        off = attr(p, :offset)
        addy!(e, sy, off isa Real ? (off,) : off)
    elseif K in (:barplot, :hist)
        if K === :hist
            c, h, w = hist_bars(d.values, attr(p, :bins), attr(p, :normalization))
            rects = bar_rects(c, h, isempty(w) ? 1.0 : minimum(w), attr(p, :gap), attr(p, :fillto), attr(p, :direction))
        else
            rects = bar_rects(d.x, d.y, attr(p, :width), attr(p, :gap), attr(p, :fillto), attr(p, :direction))
        end
        for r in rects
            addx!(e, sx, (r[1], r[2]))
            addy!(e, sy, (r[3], r[4]))
        end
    elseif K === :errorbars
        if attr(p, :direction) === :y
            addx!(e, sx, d.x)
            addy!(e, sy, d.y .- d.low)
            addy!(e, sy, d.y .+ d.high)
        else
            addy!(e, sy, d.y)
            addx!(e, sx, d.x .- d.low)
            addx!(e, sx, d.x .+ d.high)
        end
    elseif K === :band
        addx!(e, sx, d.x)
        addy!(e, sy, d.lo)
        addy!(e, sy, d.hi)
    elseif K === :heatmap
        addx!(e, sx, d.xe)
        addy!(e, sy, d.ye)
        loose = false
    elseif K === :image
        addx!(e, sx, d.x)
        addy!(e, sy, d.y)
        loose = false
    elseif K in (:contour, :contourf)
        addx!(e, sx, d.x)
        addy!(e, sy, d.y)
        loose = false
    elseif K === :hlines
        addy!(e, sy, d.values)
    elseif K === :vlines
        addx!(e, sx, d.values)
    elseif K in (:series, :multiline)
        addx!(e, sx, d.x)
        addy!(e, sy, d.Y)
    elseif K in (:surface, :wireframe)
        addx!(e, sx, d.X)
        addy!(e, sy, d.Y)
        loose = false
    elseif K === :mesh
        addx!(e, sx, view(d.V, :, 1))
        addy!(e, sy, view(d.V, :, 2))
    elseif K === :annotation
        addx!(e, sx, (d.x, d.xt))
        addy!(e, sy, (d.y, d.yt))
    end
    loose && (e.tight = false)
    return e
end

# ---------------------------------------------------------------------------------------------
# Axis state

mutable struct AxisState
    xlims::Tuple{Float64, Float64}   # scaled space, lo < hi
    ylims::Tuple{Float64, Float64}
    xticks::Vector{Float64}          # data space
    xlabels::Vector{Any}
    yticks::Vector{Float64}
    ylabels::Vector{Any}
    xminor::Vector{Float64}
    yminor::Vector{Float64}
    protrusions::NTuple{4, Float64}
    xreversed::Bool
    yreversed::Bool
end

function _auto_range(lo, hi, margin, tight, f)
    if !(isfinite(lo) && isfinite(hi))
        a, b = f === identity || f === sqrt ? (0.0, 10.0) : (1.0, 10.0)
        return (_safe(f)(a), _safe(f)(b))
    end
    if lo == hi
        d = lo == 0 ? 0.5 : abs(lo) * 0.1
        return (lo - d, hi + d)
    end
    tight && return (lo, hi)
    span = hi - lo
    return (lo - margin[1] * span, hi + margin[2] * span)
end

function _apply_user(auto::Tuple{Float64, Float64}, user, f)
    user === nothing && return auto, false
    lo, hi = user
    sf = _safe(f)
    a = lo === nothing ? auto[1] : Float64(sf(lo))
    b = hi === nothing ? auto[2] : Float64(sf(hi))
    reversed = lo !== nothing && hi !== nothing && lo > hi
    a, b = minmax(a, b)
    a == b && (b = a + 1)
    return (a, b), reversed
end

"""Limits of one axis on its own (before linking), in scaled space."""
function own_limits(ax::Axis)
    fx, fy = attr(ax, :xscale), attr(ax, :yscale)
    inverse(fx); inverse(fy)
    e = Extent()
    for p in ax.plots
        extend!(e, p, fx, fy)
    end
    isempty(ax.plots) && (e.tight = false)
    xl = _auto_range(e.xlo, e.xhi, attr(ax, :xautolimitmargin), e.tight, fx)
    yl = _auto_range(e.ylo, e.yhi, attr(ax, :yautolimitmargin), e.tight, fy)
    ux, uy = attr(ax, :limits)
    xl, xrev = _apply_user(xl, ux, fx)
    yl, yrev = _apply_user(yl, uy, fy)
    return xl, yl, xrev, yrev
end

function _text_extent(labels, size, rotation = 0.0)
    w = h = 0.0
    for l in labels
        tw, th = text_size(l, size)
        if rotation == 0
            w = max(w, tw)
            h = max(h, th)
        else
            w = max(w, abs(tw * cos(rotation)) + abs(th * sin(rotation)))
            h = max(h, abs(tw * sin(rotation)) + abs(th * cos(rotation)))
        end
    end
    return w, h
end

function axis_protrusions(ax::Axis, st::AxisState)
    a = getfield(ax, :attrs)
    # x decorations (bottom, or top with xaxisposition = :top)
    xs = 0.0
    a[:xticksvisible] && (xs += a[:xticksize] * (1 - a[:xtickalign]))
    if a[:xticklabelsvisible] && !isempty(st.xlabels)
        _, h = _text_extent(st.xlabels, a[:xticklabelsize], a[:xticklabelrotation])
        xs += a[:xticklabelpad] + h
    end
    if a[:xlabelvisible] && !is_empty_text(a[:xlabel])
        xs += a[:xlabelpadding] + text_size(a[:xlabel], a[:xlabelsize])[2]
    end
    ys = 0.0
    a[:yticksvisible] && (ys += a[:yticksize] * (1 - a[:ytickalign]))
    if a[:yticklabelsvisible] && !isempty(st.ylabels)
        w, _ = _text_extent(st.ylabels, a[:yticklabelsize], a[:yticklabelrotation])
        ys += a[:yticklabelpad] + w
    end
    if a[:ylabelvisible] && !is_empty_text(a[:ylabel])
        ys += a[:ylabelpadding] + text_size(a[:ylabel], a[:ylabelsize])[2]
    end
    top = 0.0
    if a[:titlevisible] && !is_empty_text(a[:title])
        top += a[:titlegap] + text_size(a[:title], a[:titlesize], a[:titlefont])[2]
    end
    if a[:subtitlevisible] && !is_empty_text(a[:subtitle])
        top += (top == 0 ? a[:titlegap] : a[:subtitlegap]) + text_size(a[:subtitle], a[:subtitlesize])[2]
    end
    left, right = a[:yaxisposition] === :right ? (0.0, ys) : (ys, 0.0)
    bottom = xs
    if a[:xaxisposition] === :top
        top += xs
        bottom = 0.0
    end
    return (left, right, top, bottom)
end

function prepare_axes!(states::IdDict{Any, Any}, axes::Vector{Axis})
    own = Dict{Any, Any}()
    for ax in axes
        own[ax] = own_limits(ax)
    end
    for ax in axes
        xl, yl, xrev, yrev = own[ax]
        for other in ax.xgroup
            haskey(own, other) || continue
            o = own[other][1]
            xl = (min(xl[1], o[1]), max(xl[2], o[2]))
        end
        for other in ax.ygroup
            haskey(own, other) || continue
            o = own[other][2]
            yl = (min(yl[1], o[1]), max(yl[2], o[2]))
        end
        a = getfield(ax, :attrs)
        fx, fy = a[:xscale], a[:yscale]
        gx, gy = inverse(fx), inverse(fy)
        xt, xlab = compute_ticks(a[:xticks], fx, a[:xtickformat], gx(xl[1]), gx(xl[2]))
        yt, ylab = compute_ticks(a[:yticks], fy, a[:ytickformat], gy(yl[1]), gy(yl[2]))
        xmin = a[:xminorticksvisible] || a[:xminorgridvisible] ? minor_ticks(xt, a[:xminorticks], gx(xl[1]), gx(xl[2]), fx) : Float64[]
        ymin = a[:yminorticksvisible] || a[:yminorgridvisible] ? minor_ticks(yt, a[:yminorticks], gy(yl[1]), gy(yl[2]), fy) : Float64[]
        st = AxisState(xl, yl, xt, xlab, yt, ylab, xmin, ymin, NO_PROTRUSION, a[:xreversed] ⊻ xrev, a[:yreversed] ⊻ yrev)
        st.protrusions = axis_protrusions(ax, st)
        states[ax] = st
    end
    return states
end

# ---------------------------------------------------------------------------------------------
# Other blocks

mutable struct ColorbarState
    lims::Tuple{Float64, Float64}
    cmap::Vector{RGBAf}
    levels::Union{Nothing, Vector{Float64}}
    ticks::Vector{Float64}
    labels::Vector{Any}
    protrusions::NTuple{4, Float64}
end

function prepare(cb::Colorbar)
    a = getfield(cb, :attrs)
    cmap_spec, lims, levels = a[:colormap], a[:limits], a[:levels]
    if cb.plot !== nothing
        info = color_info(cb.plot)
        info === nothing && throw(ArgumentError("a Colorbar needs a plot with a colour map (heatmap, surface, contourf, coloured scatter, …)"))
        cmap_spec = info.colormap
        lims === nothing && (lims = info.range)
        levels === nothing && (levels = info.levels)
    end
    lims === nothing && (lims = (0.0, 1.0))
    lo, hi = Float64(lims[1]), Float64(lims[2])
    lo == hi && (hi = lo + 1)
    ticks, labels = compute_ticks(a[:ticks], a[:scale], a[:tickformat], lo, hi)
    st = ColorbarState((lo, hi), to_colormap(cmap_spec), levels === nothing ? nothing : _vec(levels), ticks, labels, NO_PROTRUSION)
    out = 0.0
    a[:ticksvisible] && (out += a[:ticksize])
    if a[:vertical]
        if a[:ticklabelsvisible] && !isempty(labels)
            w, h = _text_extent(labels, a[:ticklabelsize])
            out += a[:ticklabelpad] + w
        end
        a[:labelvisible] && !is_empty_text(a[:label]) && (out += a[:labelpadding] + text_size(a[:label], a[:labelsize])[2])
        st.protrusions = a[:flipaxis] ? (0.0, out, 0.0, 0.0) : (out, 0.0, 0.0, 0.0)
    else
        if a[:ticklabelsvisible] && !isempty(labels)
            _, h = _text_extent(labels, a[:ticklabelsize])
            out += a[:ticklabelpad] + h
        end
        a[:labelvisible] && !is_empty_text(a[:label]) && (out += a[:labelpadding] + text_size(a[:label], a[:labelsize])[2])
        st.protrusions = a[:flipaxis] ? (0.0, 0.0, 0.0, out) : (0.0, 0.0, out, 0.0)
    end
    return st
end

protrusions(::Any, st) = hasproperty(st, :protrusions) ? st.protrusions : NO_PROTRUSION
protrusions(::GridLayout, st) = NO_PROTRUSION

"""The inner size a block asks for, `nothing` where it fills its cell."""
function intrinsic(b::Block, st; tell::Bool = true)
    a = getfield(b, :attrs)
    w = get(a, :width, nothing)
    h = get(a, :height, nothing)
    if b isa Colorbar
        a[:vertical] ? (w = something(w, a[:size])) : (h = something(h, a[:size]))
    elseif b isa Label
        tw, th = text_size(a[:text], a[:fontsize], a[:font])
        r = Float64(a[:rotation])
        rw, rh = abs(tw * cos(r)) + abs(th * sin(r)), abs(tw * sin(r)) + abs(th * cos(r))
        p = a[:padding]
        w = something(w, rw + p[1] + p[2])
        h = something(h, rh + p[3] + p[4])
    elseif b isa Legend
        w = something(w, st.size[1])
        h = something(h, st.size[2])
    end
    # What the layout is told (grid sizes) can be less than the block's own size (its placement).
    tell && w isa Real && !a[:tellwidth] && (w = nothing)
    tell && h isa Real && !a[:tellheight] && (h = nothing)
    return (w === nothing ? nothing : Float64(w), h === nothing ? nothing : Float64(h))
end
intrinsic(::GridLayout, st; tell::Bool = true) = (nothing, nothing)

function placed_items(g::GridLayout, out = Any[])
    for c in g.content
        push!(out, c.item)
        c.item isa GridLayout && placed_items(c.item, out)
    end
    return out
end

"""Prepare every placed block of `fig`; returns `IdDict(block => state)`."""
function prepare_figure(fig::Figure)
    states = IdDict{Any, Any}()
    placed = placed_items(fig.layout)
    is_placed(b) = any(x -> x === b, placed)
    prepare_axes!(states, Axis[b for b in fig.content if b isa Axis && is_placed(b)])
    for b in fig.content
        is_placed(b) || continue
        if b isa Axis3
            states[b] = prepare3d(b)
        elseif b isa Colorbar
            states[b] = prepare(b)
        elseif b isa Legend
            states[b] = prepare(b)
        elseif b isa Label
            states[b] = (protrusions = NO_PROTRUSION,)
        end
    end
    return states
end

# ---------------------------------------------------------------------------------------------
# Solving the grid

function _sizes(n::Int, sizes::Dict{Int, Any}, determined::Vector{Union{Nothing, Float64}}, avail::Float64)
    out = zeros(n)
    flexible = Float64[]
    fixed = 0.0
    ratios = zeros(n)
    for i in 1:n
        s = get(sizes, i, Auto())
        if s isa Fixed
            out[i] = s.x
        elseif s isa Relative
            out[i] = s.x * avail
        elseif s isa Auto && s.trydetermine && determined[i] !== nothing
            out[i] = determined[i]
        else
            ratios[i] = s isa Auto ? s.ratio : 1.0
            continue
        end
        fixed += out[i]
    end
    total = sum(ratios)
    rest = max(0.0, avail - fixed)
    if total > 0
        for i in 1:n
            ratios[i] > 0 && (out[i] = rest * ratios[i] / total)
        end
        return out, 0.0
    end
    return out, rest
end

function _align(inner::Rect, w, h, halign, valign)
    w === nothing && h === nothing && return inner
    ww = w === nothing ? inner.w : min(w, inner.w)
    hh = h === nothing ? inner.h : min(h, inner.h)
    fx = halign isa Real ? Float64(halign) : halign === :left ? 0.0 : halign === :right ? 1.0 : 0.5
    fy = valign isa Real ? 1 - Float64(valign) : valign === :top ? 0.0 : valign === :bottom ? 1.0 : 0.5
    return Rect(inner.x + (inner.w - ww) * fx, inner.y + (inner.h - hh) * fy, ww, hh)
end

function _aspect(ax::Axis, st::AxisState, r::Rect)
    asp = attr(ax, :aspect)
    asp === nothing && return r
    ratio = asp isa DataAspect ? (st.xlims[2] - st.xlims[1]) / (st.ylims[2] - st.ylims[1]) :
            asp isa AxisAspect ? asp.ratio : Float64(asp)
    (isfinite(ratio) && ratio > 0) || return r
    if r.w / r.h > ratio
        return _align(r, r.h * ratio, nothing, attr(ax, :halign), attr(ax, :valign))
    end
    return _align(r, nothing, r.w / ratio, attr(ax, :halign), attr(ax, :valign))
end

"""Solve `g` inside `R`; push `(item, inner rect)` for every block into `out`."""
function solve!(out::Vector{Any}, g::GridLayout, R::Rect, states::IdDict{Any, Any}, fig::Figure)
    nc, nr = g.ncols, g.nrows
    (nc == 0 || nr == 0) && return out
    colgap = something(g.colgap, Float64(fig.theme[:colgap]))
    rowgap = something(g.rowgap, Float64(fig.theme[:rowgap]))
    pl, pr, pt, pb = zeros(nc), zeros(nc), zeros(nr), zeros(nr)
    colw = Vector{Union{Nothing, Float64}}(nothing, nc)
    rowh = Vector{Union{Nothing, Float64}}(nothing, nr)
    spans = [(_resolve(c.rows, nr), _resolve(c.cols, nc)) for c in g.content]
    for (c, (rows, cols)) in zip(g.content, spans)
        st = get(states, c.item, nothing)
        c.item isa GridLayout || st !== nothing || continue
        p = c.item isa GridLayout ? NO_PROTRUSION : protrusions(c.item, st)
        pl[first(cols)] = max(pl[first(cols)], p[1])
        pr[last(cols)] = max(pr[last(cols)], p[2])
        pt[first(rows)] = max(pt[first(rows)], p[3])
        pb[last(rows)] = max(pb[last(rows)], p[4])
        w, h = intrinsic(c.item, st)
        length(cols) == 1 && w !== nothing && (colw[first(cols)] = max(something(colw[first(cols)], 0.0), w))
        length(rows) == 1 && h !== nothing && (rowh[first(rows)] = max(something(rowh[first(rows)], 0.0), h))
    end
    gapw(i) = get(g.colgaps, i, colgap)
    gaph(i) = get(g.rowgaps, i, rowgap)
    availw = R.w - sum(pl) - sum(pr) - sum(gapw(i) for i in 1:(nc - 1); init = 0.0)
    availh = R.h - sum(pt) - sum(pb) - sum(gaph(i) for i in 1:(nr - 1); init = 0.0)
    widths, restw = _sizes(nc, g.colsizes, colw, max(availw, 0.0))
    heights, resth = _sizes(nr, g.rowsizes, rowh, max(availh, 0.0))
    xs = zeros(nc)
    x = R.x + restw / 2
    for i in 1:nc
        x += pl[i]
        xs[i] = x
        x += widths[i] + pr[i] + (i < nc ? gapw(i) : 0.0)
    end
    ys = zeros(nr)
    y = R.y + resth / 2
    for i in 1:nr
        y += pt[i]
        ys[i] = y
        y += heights[i] + pb[i] + (i < nr ? gaph(i) : 0.0)
    end
    for (c, (rows, cols)) in zip(g.content, spans)
        r1, r2, c1, c2 = first(rows), last(rows), first(cols), last(cols)
        inner = Rect(xs[c1], ys[r1], xs[c2] + widths[c2] - xs[c1], ys[r2] + heights[r2] - ys[r1])
        if c.item isa GridLayout
            solve!(out, c.item, inner, states, fig)
            continue
        end
        st = get(states, c.item, nothing)
        st === nothing && continue
        w, h = intrinsic(c.item, st; tell = false)
        a = getfield(c.item, :attrs)
        rect = _align(inner, w, h, get(a, :halign, :center), get(a, :valign, :center))
        c.item isa Axis && (rect = _aspect(c.item, st, rect))
        push!(out, (c.item, rect))
    end
    return out
end

"""Prepared states and inner rectangles for every placed block of `fig`."""
function layout_figure(fig::Figure)
    states = prepare_figure(fig)
    l, r, b, t = fig.padding
    rects = solve!(Any[], fig.layout, Rect(l, t, fig.size[1] - l - r, fig.size[2] - t - b), states, fig)
    return states, IdDict{Any, Any}(item => rect for (item, rect) in rects)
end
