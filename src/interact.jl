# Interaction: pan, zoom and rotate change an axis' limits or camera, as a GUI does on drag and
# wheel. They work on the limits the figure would draw with now (so automatic limits become fixed
# ones) and move linked axes together. `axes_layout` tells a GUI where each axis is drawn.

"""
    axes_layout(fig) -> Vector{NamedTuple}

Where each axis is drawn, in figure units (`x`, `y` from the top-left, `w`, `h`), in the order of
`fig`'s axes (the `index` that `zoom!`/`pan!`/`rotate!` callers can keep), with `kind` (`:axis`
or `:axis3`) and the axis title. For hit-testing pointer events.
"""
function axes_layout(fig::Figure)
    states, rects = layout_figure(fig)
    out = NamedTuple[]
    for (i, ax) in enumerate(axes_of(fig))
        haskey(rects, ax) || continue
        r = rects[ax]
        push!(out, (index = i, kind = ax isa Axis3 ? :axis3 : :axis, x = r.x, y = r.y, w = r.w, h = r.h,
            title = plaintext(attr(ax, :title))))
    end
    return out
end

function _apply_x!(ax::Axis, lo, hi, reversed)
    for other in ax.xgroup
        l = Any[attr(other, :limits)...]
        l[1] = (lo, hi)
        other.attrs[:limits] = (l[1], l[2])
        other.attrs[:xreversed] = reversed
    end
end

function _apply_y!(ax::Axis, lo, hi, reversed)
    for other in ax.ygroup
        l = Any[attr(other, :limits)...]
        l[2] = (lo, hi)
        other.attrs[:limits] = (l[1], l[2])
        other.attrs[:yreversed] = reversed
    end
end

_unscale(f, a, b) = (g = inverse(f); (g(a), g(b)))

"""
    zoom!(ax, factor; around = (0.5, 0.5), x = true, y = true)

Zoom an `Axis` by `factor` (< 1 zooms in) about a point given as fractions of the plot area from
its left and bottom edges (where the pointer is). Log axes zoom in log space. For an `Axis3`,
the box's limits shrink or grow about their centre.
"""
function zoom!(ax::Axis, factor::Real; around = (0.5, 0.5), x::Bool = true, y::Bool = true)
    factor > 0 || throw(ArgumentError("zoom factor must be > 0"))
    st = prepare_figure(ax.figure)[ax]
    fx, fy = Float64(around[1]), Float64(around[2])
    if x
        x0, x1 = st.xlims
        st.xreversed && (fx = 1 - fx)
        c = x0 + fx * (x1 - x0)
        _apply_x!(ax, _unscale(attr(ax, :xscale), c - (c - x0) * factor, c + (x1 - c) * factor)..., st.xreversed)
    end
    if y
        y0, y1 = st.ylims
        st.yreversed && (fy = 1 - fy)
        c = y0 + fy * (y1 - y0)
        _apply_y!(ax, _unscale(attr(ax, :yscale), c - (c - y0) * factor, c + (y1 - c) * factor)..., st.yreversed)
    end
    return ax
end

function zoom!(ax::Axis3, factor::Real; kwargs...)
    factor > 0 || throw(ArgumentError("zoom factor must be > 0"))
    st = prepare3d(ax)
    lims = ntuple(3) do k
        lo, hi = st.lims[k]
        c = (lo + hi) / 2
        (c - (c - lo) * factor, c + (hi - c) * factor)
    end
    ax.attrs[:limits] = lims
    return ax
end

"""
    pan!(ax, dx, dy)

Move an `Axis`' view with the pointer: `dx`, `dy` are fractions of the plot area (positive: the
content moves right and up, as when dragging it). Linked axes move together.
"""
function pan!(ax::Axis, dx::Real, dy::Real)
    st = prepare_figure(ax.figure)[ax]
    x0, x1 = st.xlims
    y0, y1 = st.ylims
    sx = (st.xreversed ? -1 : 1) * dx * (x1 - x0)
    sy = (st.yreversed ? -1 : 1) * dy * (y1 - y0)
    dx == 0 || _apply_x!(ax, _unscale(attr(ax, :xscale), x0 - sx, x1 - sx)..., st.xreversed)
    dy == 0 || _apply_y!(ax, _unscale(attr(ax, :yscale), y0 - sy, y1 - sy)..., st.yreversed)
    return ax
end

"""`pan!(ax3, dx, dy)` on an `Axis3` turns the view, as dragging does (see `rotate!`)."""
pan!(ax::Axis3, dx::Real, dy::Real) = rotate!(ax, -dx * π, -dy * π / 2)

"""
    rotate!(ax3, dazimuth, delevation)

Turn an `Axis3`'s camera by the given angles (radians). The elevation stays within ±89°.
"""
function rotate!(ax::Axis3, daz::Real, del::Real)
    ax.attrs[:azimuth] = Float64(attr(ax, :azimuth)) + daz
    ax.attrs[:elevation] = clamp(Float64(attr(ax, :elevation)) + del, -0.49π, 0.49π)
    return ax
end
