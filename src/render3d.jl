# The 3D renderer. An Axis3 is an orthographic view of its data box, placed by azimuth and
# elevation (Makie's conventions and defaults). The three panels facing away from the camera get
# grids; ticks run along the outer edges; data primitives (surface faces, mesh triangles,
# segments, markers, text) are depth-sorted and painted back to front.

mutable struct Axis3State
    lims::NTuple{3, Tuple{Float64, Float64}}
    ticks::NTuple{3, Vector{Float64}}
    labels::NTuple{3, Vector{Any}}
    protrusions::NTuple{4, Float64}
end

function _extent3!(lo, hi, xs, k)
    for v in xs
        if v isa Real && isfinite(v)
            lo[k] = min(lo[k], v)
            hi[k] = max(hi[k], v)
        end
    end
end

function prepare3d(ax::Axis3)
    a = getfield(ax, :attrs)
    lo, hi = fill(Inf, 3), fill(-Inf, 3)
    for p in ax.plots
        getfield(p, :attrs)[:visible] || continue
        d = converted(p)
        K = kind(p)
        if K in (:surface, :wireframe)
            _extent3!(lo, hi, d.X, 1); _extent3!(lo, hi, d.Y, 2); _extent3!(lo, hi, d.Z, 3)
        elseif K === :mesh
            for k in 1:3
                _extent3!(lo, hi, view(d.V, :, k), k)
            end
        elseif hasproperty(d, :x) && hasproperty(d, :y)
            _extent3!(lo, hi, d.x, 1); _extent3!(lo, hi, d.y, 2)
            z = hasproperty(d, :z) && d.z !== nothing ? d.z : (0.0,)
            _extent3!(lo, hi, z, 3)
            K === :stem && _extent3!(lo, hi, (getfield(p, :attrs)[:offset],), 3)
        end
    end
    user = a[:limits]
    lims = ntuple(3) do k
        s = (:x, :y, :z)[k]
        auto = _auto_range(lo[k], hi[k], a[Symbol(s, :autolimitmargin)], false, identity)
        l, _ = _apply_user(auto, user[k], identity)
        l
    end
    ticks = Vector{Vector{Float64}}(undef, 3)
    labels = Vector{Vector{Any}}(undef, 3)
    for (k, s) in enumerate((:x, :y, :z))
        ticks[k], labels[k] = compute_ticks(a[Symbol(s, :ticks)], identity, a[Symbol(s, :tickformat)], lims[k]...)
    end
    top = a[:titlevisible] && !is_empty_text(a[:title]) ? a[:titlegap] + text_size(a[:title], a[:titlesize], a[:titlefont])[2] : 0.0
    return Axis3State(lims, (ticks[1], ticks[2], ticks[3]), (labels[1], labels[2], labels[3]), (0.0, 0.0, top, 0.0))
end

# ---------------------------------------------------------------------------------------------
# Camera

struct Cam
    lo::NTuple{3, Float64}
    hi::NTuple{3, Float64}
    half::NTuple{3, Float64}
    right::NTuple{3, Float64}
    up::NTuple{3, Float64}
    eye::NTuple{3, Float64}
    s::Float64
    cx::Float64
    cy::Float64
end

_n3(v) = (n = sqrt(v[1]^2 + v[2]^2 + v[3]^2); (v[1] / n, v[2] / n, v[3] / n))
_dot3(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
_cross3(a, b) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])

"""Data point → normalised box coordinates (each axis spans ±half[k])."""
function normal3(c::Cam, x, y, z)
    f(v, k) = ((v - c.lo[k]) / (c.hi[k] - c.lo[k]) * 2 - 1) * c.half[k]
    return (f(x, 1), f(y, 2), f(z, 3))
end
"""Normalised point → screen `(x, y, depth)`; larger depth is nearer the camera."""
screen(c::Cam, n) = (c.cx + c.s * _dot3(n, c.right), c.cy - c.s * _dot3(n, c.up), _dot3(n, c.eye))
project(c::Cam, x, y, z) = screen(c, normal3(c, x, y, z))
inside3(c::Cam, n) = abs(n[1]) <= c.half[1] * 1.0001 && abs(n[2]) <= c.half[2] * 1.0001 && abs(n[3]) <= c.half[3] * 1.0001

function camera(ax::Axis3, st::Axis3State, r::Rect, margins)
    a = getfield(ax, :attrs)
    lo = ntuple(k -> st.lims[k][1], 3)
    hi = ntuple(k -> st.lims[k][2], 3)
    asp = a[:aspect]
    half = if asp === :data
        spans = ntuple(k -> hi[k] - lo[k], 3)
        m = maximum(spans)
        ntuple(k -> spans[k] / m, 3)
    elseif asp === :equal
        (1.0, 1.0, 1.0)
    else
        m = maximum(asp)
        ntuple(k -> Float64(asp[k]) / m, 3)
    end
    az, el = Float64(a[:azimuth]), Float64(a[:elevation])
    eye = (cos(el) * cos(az), cos(el) * sin(az), sin(el))
    fwd = (-eye[1], -eye[2], -eye[3])
    rt = _cross3(fwd, (0.0, 0.0, 1.0))
    rt = sqrt(_dot3(rt, rt)) < 1e-9 ? (1.0, 0.0, 0.0) : _n3(rt)
    up = _n3(_cross3(rt, fwd))
    xs, ys = Float64[], Float64[]
    for sx in (-1, 1), sy in (-1, 1), sz in (-1, 1)
        n = (sx * half[1], sy * half[2], sz * half[3])
        push!(xs, _dot3(n, rt))
        push!(ys, -_dot3(n, up))
    end
    bw, bh = maximum(xs) - minimum(xs), maximum(ys) - minimum(ys)
    ml, mr, mt, mb = margins
    s = max(1.0, min((r.w - ml - mr) / bw, (r.h - mt - mb) / bh))
    cx = r.x + ml + (r.w - ml - mr) / 2 - s * (maximum(xs) + minimum(xs)) / 2
    cy = r.y + mt + (r.h - mt - mb) / 2 - s * (maximum(ys) + minimum(ys)) / 2
    return Cam(lo, hi, half, rt, up, eye, s, cx, cy)
end

# ---------------------------------------------------------------------------------------------
# Primitives

struct Poly3
    xs::Vector{Float64}
    ys::Vector{Float64}
    color::RGBAf
    strokecolor::RGBAf
    strokewidth::Float64
end
struct Seg3
    x1::Float64
    y1::Float64
    x2::Float64
    y2::Float64
    color::RGBAf
    lw::Float64
    ls::Any
end
struct Mark3
    x::Float64
    y::Float64
    marker::Symbol
    size::Float64
    color::RGBAf
    strokecolor::RGBAf
    strokewidth::Float64
end
struct Text3
    x::Float64
    y::Float64
    text::Any
    size::Float64
    font::Symbol
    color::RGBAf
    align::Tuple{Any, Any}
    rotation::Float64
end

const Prim3 = Union{Poly3, Seg3, Mark3, Text3}

function _shade(c::RGBAf, n, cam::Cam, shading)
    (shading === NoShading || shading === false) && return c
    nn = sqrt(_dot3(n, n))
    nn < 1e-12 && return c
    light = _n3((cam.eye[1] + 0.6cam.up[1] - 0.3cam.right[1], cam.eye[2] + 0.6cam.up[2] - 0.3cam.right[2], cam.eye[3] + 0.6cam.up[3] - 0.3cam.right[3]))
    f = 0.55 + 0.45 * abs(_dot3(n, light)) / nn
    return RGBAf(red(c) * f, green(c) * f, blue(c) * f, alpha(c))
end

function _sub3(a, b)
    return (a[1] - b[1], a[2] - b[2], a[3] - b[3])
end

function _face!(prims, cam::Cam, ns, color, a)
    all(n -> all(isfinite, n), ns) || return
    all(n -> inside3(cam, n), ns) || return
    pts = [screen(cam, n) for n in ns]
    depth = sum(p[3] for p in pts) / length(pts)
    normal = length(ns) == 4 ? _cross3(_sub3(ns[3], ns[1]), _sub3(ns[4], ns[2])) : _cross3(_sub3(ns[2], ns[1]), _sub3(ns[3], ns[1]))
    c = _shade(color, normal, cam, a[:shading])
    sw = Float64(a[:strokewidth])
    push!(prims, (depth, Poly3([p[1] for p in pts], [p[2] for p in pts], c, sw > 0 ? to_color(a[:strokecolor]) : c, sw)))
end

function _segments!(prims, cam::Cam, xs, ys, zs, color, lw, ls)
    for i in 1:(length(xs) - 1)
        n1, n2 = normal3(cam, xs[i], ys[i], zs[i]), normal3(cam, xs[i + 1], ys[i + 1], zs[i + 1])
        (all(isfinite, n1) && all(isfinite, n2) && inside3(cam, n1) && inside3(cam, n2)) || continue
        p1, p2 = screen(cam, n1), screen(cam, n2)
        push!(prims, ((p1[3] + p2[3]) / 2, Seg3(p1[1], p1[2], p2[1], p2[2], to_color(_at(color, i)), lw, ls)))
    end
end

function _markers!(prims, cam::Cam, xs, ys, zs, marker, size, color, strokecolor, strokewidth)
    m = marker isa AbstractVector ? [marker_symbol(x) for x in marker] : marker_symbol(marker)
    for i in eachindex(xs)
        n = normal3(cam, xs[i], ys[i], zs[i])
        (all(isfinite, n) && inside3(cam, n)) || continue
        p = screen(cam, n)
        push!(prims, (p[3] + 1e-6, Mark3(p[1], p[2], _at(m, i), Float64(_at(size, i)), to_color(_at(color, i)), to_color(strokecolor), Float64(strokewidth))))
    end
end

function primitives3d(p::Plot{K}, cam::Cam) where {K}
    prims = Tuple{Float64, Prim3}[]
    a = getfield(p, :attrs)
    a[:visible] || return prims
    d = converted(p)
    if K === :surface
        values = a[:color] isa AbstractMatrix{<:Real} ? a[:color] : d.Z
        single = a[:color] isa Union{Symbol, Colorant, AbstractString}
        cmap = to_colormap(a[:colormap])
        r = _crange(a[:colorrange], values)
        nx, ny = size(d.Z)
        for i in 1:(nx - 1), j in 1:(ny - 1)
            idx = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            ns = [normal3(cam, d.X[q...], d.Y[q...], d.Z[q...]) for q in idx]
            v = sum(values[q...] for q in idx) / 4
            c = single ? to_color(a[:color]) : colormap_value(cmap, v, r; nan_color = to_color(a[:nan_color]))
            _face!(prims, cam, ns, with_alpha(c, a[:alpha]), a)
        end
    elseif K === :mesh
        colors = mesh_vertex_colors(a, d)
        for f in 1:size(d.F, 1)
            ids = d.F[f, :]
            ns = [normal3(cam, d.V[k, 1], d.V[k, 2], d.V[k, 3]) for k in ids]
            c = mesh_face_color(a, colors, ids)
            _face!(prims, cam, ns, c, a)
        end
    elseif K === :wireframe
        color = resolve_colors(a[:color], 1, a)
        nx, ny = size(d.Z)
        for i in 1:nx
            _segments!(prims, cam, d.X[i, :], d.Y[i, :], d.Z[i, :], color, a[:linewidth], a[:linestyle])
        end
        for j in 1:ny
            _segments!(prims, cam, d.X[:, j], d.Y[:, j], d.Z[:, j], color, a[:linewidth], a[:linestyle])
        end
    elseif K in (:lines, :stairs, :scatterlines, :linesegments)
        z = d.z === nothing ? zeros(length(d.x)) : d.z
        color = resolve_colors(a[:color], length(d.x), a)
        if K === :linesegments
            for i in 1:2:(length(d.x) - 1)
                _segments!(prims, cam, d.x[i:(i + 1)], d.y[i:(i + 1)], z[i:(i + 1)], [_at(color, i)], a[:linewidth], a[:linestyle])
            end
        else
            _segments!(prims, cam, d.x, d.y, z, color, a[:linewidth], a[:linestyle])
        end
        if K === :scatterlines
            mc = a[:markercolor] === :inherit ? color : resolve_colors(a[:markercolor], length(d.x), a)
            _markers!(prims, cam, d.x, d.y, z, a[:marker], a[:markersize], mc, a[:strokecolor], a[:strokewidth])
        end
    elseif K === :scatter
        z = d.z === nothing ? zeros(length(d.x)) : d.z
        _markers!(prims, cam, d.x, d.y, z, a[:marker], a[:markersize], resolve_colors(a[:color], length(d.x), a), a[:strokecolor], a[:strokewidth])
    elseif K === :stem
        z = d.z === nothing ? zeros(length(d.x)) : d.z
        color = resolve_colors(a[:color], length(d.x), a)
        stemc = a[:stemcolor] === :inherit ? color : resolve_colors(a[:stemcolor], length(d.x), a)
        off = Float64(a[:offset])
        for i in eachindex(d.x)
            _segments!(prims, cam, [d.x[i], d.x[i]], [d.y[i], d.y[i]], [off, z[i]], [_at(stemc, i)], a[:stemwidth], a[:stemlinestyle])
        end
        _markers!(prims, cam, d.x, d.y, z, a[:marker], a[:markersize], color, a[:strokecolor], a[:strokewidth])
    elseif K === :text
        z = d.z === nothing ? zeros(length(d.x)) : d.z
        texts = d.text === nothing ? a[:text] : d.text
        for i in eachindex(d.x)
            n = normal3(cam, d.x[i], d.y[i], z[i])
            all(isfinite, n) || continue
            q = screen(cam, n)
            s = texts isa AbstractVector ? texts[mod1(i, length(texts))] : texts
            o = a[:offset]
            push!(prims, (q[3] + 1e-6, Text3(q[1] + o[1], q[2] - o[2], s, Float64(_at(a[:fontsize], i)), a[:font],
                with_alpha(a[:color], a[:alpha]), a[:align], Float64(a[:rotation]))))
        end
    else
        throw(ArgumentError("$K is not drawn in an Axis3"))
    end
    return prims
end

function draw_prim(ctx::Ctx, p::Poly3)
    fill_polygon(ctx, p.xs, p.ys, p.color; seam = p.strokewidth == 0, strokecolor = p.strokewidth > 0 ? p.strokecolor : nothing,
        strokewidth = p.strokewidth)
end
draw_prim(ctx::Ctx, s::Seg3) = draw_polyline(ctx, [s.x1, s.x2], [s.y1, s.y2], s.color, s.lw, s.ls)
draw_prim(ctx::Ctx, m::Mark3) = draw_markers(ctx, [m.x], [m.y], m.marker, m.size, m.color, m.strokecolor, m.strokewidth)
draw_prim(ctx::Ctx, t::Text3) = draw_text(ctx, t.text, t.x, t.y; size = t.size, font = t.font, color = t.color,
    halign = t.align[1], valign = t.align[2], rotation = t.rotation)

# ---------------------------------------------------------------------------------------------
# The axis

function _dir2(cam::Cam, v)
    dx, dy = _dot3(v, cam.right), -_dot3(v, cam.up)
    n = hypot(dx, dy)
    return n < 1e-9 ? (0.0, 1.0) : (dx / n, dy / n)
end

_halign(dx) = dx > 0.35 ? :left : dx < -0.35 ? :right : :center
_valign(dy) = dy > 0.35 ? :top : dy < -0.35 ? :bottom : :center

function draw_block(ctx::Ctx, ax::Axis3, r::Rect, st::Axis3State)
    a = getfield(ax, :attrs)
    bg = to_color(a[:backgroundcolor])
    if alpha(bg) > 0
        new_path(ctx)
        rectangle(ctx, r.x, r.y, r.w, r.h)
        set_color(ctx, bg)
        fillpath(ctx)
    end
    names = (:x, :y, :z)
    lw = maximum(_text_extent(st.labels[k], a[Symbol(names[k], :ticklabelsize)])[1] for k in 1:3)
    lh = maximum(text_size("0", a[Symbol(n, :labelsize)])[2] for n in names)
    margins = (lw + lh + 24.0, lw * 0.6 + 16.0, 8.0, lh * 2 + 30.0)
    cam = camera(ax, st, r, margins)
    lo, hi = cam.lo, cam.hi
    # Which side of each axis faces away from the camera
    back = ntuple(k -> cam.eye[k] < 0 ? hi[k] : lo[k], 3)
    front = ntuple(k -> cam.eye[k] < 0 ? lo[k] : hi[k], 3)
    P(x, y, z) = project(cam, x, y, z)
    # panels
    panels = (
        (:yzpanel, (back[1], lo[2], lo[3]), (back[1], hi[2], lo[3]), (back[1], hi[2], hi[3]), (back[1], lo[2], hi[3])),
        (:xzpanel, (lo[1], back[2], lo[3]), (hi[1], back[2], lo[3]), (hi[1], back[2], hi[3]), (lo[1], back[2], hi[3])),
        (:xypanel, (lo[1], lo[2], back[3]), (hi[1], lo[2], back[3]), (hi[1], hi[2], back[3]), (lo[1], hi[2], back[3])),
    )
    for (name, corners...) in panels
        a[Symbol(name, :visible)] || continue
        c = to_color(a[Symbol(name, :color)])
        alpha(c) > 0 || continue
        pts = [P(q...) for q in corners]
        fill_polygon(ctx, [q[1] for q in pts], [q[2] for q in pts], c)
    end
    # grids on the back panels
    for (k, s) in enumerate(names)
        a[Symbol(s, :gridvisible)] || continue
        gc, gw = to_color(a[Symbol(s, :gridcolor)]), a[Symbol(s, :gridwidth)]
        for v in st.ticks[k], j in 1:3
            j == k && continue
            # a line at coordinate k = v on the panel perpendicular to j, spanning the third axis
            m = 6 - k - j
            p0, p1 = zeros(3), zeros(3)
            p0[k] = p1[k] = v
            p0[j] = p1[j] = back[j]
            p0[m], p1[m] = lo[m], hi[m]
            q0, q1 = P(p0...), P(p1...)
            draw_polyline(ctx, [q0[1], q1[1]], [q0[2], q1[2]], gc, gw, nothing)
        end
    end
    # spines: the edges of the three back panels
    sw, sc = a[:spinewidth], to_color(a[:spinecolor])
    for (name, corners...) in panels
        a[Symbol(names[name === :yzpanel ? 1 : name === :xzpanel ? 2 : 3], :spinesvisible)] || continue
        pts = [P(q...) for q in corners]
        set_stroke(ctx, sc, sw)
        polyline!(ctx, [[q[1] for q in pts]; pts[1][1]], [[q[2] for q in pts]; pts[1][2]])
        stroke(ctx)
    end
    # data
    prims = Tuple{Float64, Prim3}[]
    for p in ax.plots
        append!(prims, primitives3d(p, cam))
    end
    sort!(prims; by = first)
    for (_, prim) in prims
        draw_prim(ctx, prim)
    end
    # ticks and labels along the outer edges
    centre = ((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
    zcorner = let c1 = (back[1], front[2]), c2 = (front[1], back[2])
        P(c1..., lo[3])[1] <= P(c2..., lo[3])[1] ? c1 : c2
    end
    for (k, s) in enumerate(names)
        # edge endpoints and the outward direction (in data-direction space)
        if k == 1
            e0, e1 = (lo[1], front[2], back[3]), (hi[1], front[2], back[3])
            out = (0.0, sign(front[2] - centre[2]), sign(back[3] - centre[3]))
        elseif k == 2
            e0, e1 = (front[1], lo[2], back[3]), (front[1], hi[2], back[3])
            out = (sign(front[1] - centre[1]), 0.0, sign(back[3] - centre[3]))
        else
            e0, e1 = (zcorner[1], zcorner[2], lo[3]), (zcorner[1], zcorner[2], hi[3])
            out = (sign(zcorner[1] - centre[1]), sign(zcorner[2] - centre[2]), 0.0)
        end
        dx, dy = _dir2(cam, (out[1] * cam.half[1], out[2] * cam.half[2], out[3] * cam.half[3]))
        tsz = a[Symbol(s, :ticksvisible)] ? a[Symbol(s, :ticksize)] : 0.0
        pad = a[Symbol(s, :ticklabelpad)]
        maxext = 0.0
        for (v, l) in zip(st.ticks[k], st.labels[k])
            q = collect(e0)
            q[k] = v
            sp = P(q...)
            tsz > 0 && draw_polyline(ctx, [sp[1], sp[1] + dx * tsz], [sp[2], sp[2] + dy * tsz], to_color(a[Symbol(s, :tickcolor)]), a[Symbol(s, :tickwidth)], nothing)
            if a[Symbol(s, :ticklabelsvisible)]
                draw_text(ctx, l, sp[1] + dx * (tsz + pad), sp[2] + dy * (tsz + pad); size = a[Symbol(s, :ticklabelsize)],
                    color = a[Symbol(s, :ticklabelcolor)], halign = _halign(dx), valign = _valign(dy))
                w, h = text_size(l, a[Symbol(s, :ticklabelsize)])
                maxext = max(maxext, abs(dx) * w + abs(dy) * h)
            end
        end
        if a[Symbol(s, :labelvisible)] && !is_empty_text(a[Symbol(s, :label)])
            m0, m1 = P(e0...), P(e1...)
            mx, my = (m0[1] + m1[1]) / 2, (m0[2] + m1[2]) / 2
            off = tsz + pad + maxext + 8
            if k == 3
                rot = π / 2
            else
                rot = atan(-(m1[2] - m0[2]), m1[1] - m0[1])
                rot > π / 2 && (rot -= π)
                rot < -π / 2 && (rot += π)
            end
            draw_text(ctx, a[Symbol(s, :label)], mx + dx * off, my + dy * off; size = a[Symbol(s, :labelsize)],
                font = a[Symbol(s, :labelfont)], color = a[Symbol(s, :labelcolor)], halign = :center,
                valign = k == 3 ? (dx < 0 ? :bottom : :top) : (dy >= 0 ? :top : :bottom), rotation = rot)
        end
    end
    if a[:titlevisible] && !is_empty_text(a[:title])
        tx = a[:titlealign] === :left ? r.x : a[:titlealign] === :right ? r.x + r.w : r.x + r.w / 2
        draw_text(ctx, a[:title], tx, r.y - a[:titlegap]; size = a[:titlesize], font = a[:titlefont], color = a[:titlecolor],
            halign = a[:titlealign], valign = :bottom)
    end
    for lg in ax.legends
        draw_axislegend(ctx, lg, r)
    end
end
