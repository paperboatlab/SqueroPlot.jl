# Interactive scene serialization (`scene_spec`) and view updates (`apply_view!`).
# The frontend renders every Axis (2D) and Axis3 (3D) natively using @paperboat/shared while
# Cairo remains the sole exporter for true vector SVG/PDF/EPS/HTML and PNG artifacts.

const MARKER_CODE = Dict{Symbol, String}(
    :circle => "o", :rect => "s", :diamond => "d", :utriangle => "^", :dtriangle => "v",
    :rtriangle => ">", :ltriangle => "<", :cross => "+", :xcross => "x",
    :star5 => "*", :star4 => "*", :star6 => "*", :pentagon => "p", :hexagon => "h",
    :hline => "_", :vline => "|", :point => ".",
)

function _css_color(c)::String
    c === nothing && return "transparent"
    r = to_color(c)
    a = alpha(r)
    a <= 0 && return "transparent"
    R = clamp(round(Int, red(r) * 255), 0, 255)
    G = clamp(round(Int, green(r) * 255), 0, 255)
    B = clamp(round(Int, blue(r) * 255), 0, 255)
    a >= 0.999 && return @sprintf("#%02x%02x%02x", R, G, B)
    return @sprintf("rgba(%d,%d,%d,%.3f)", R, G, B, clamp(Float64(a), 0.0, 1.0))
end

function _linestyle_name(ls)::String
    ls === nothing && return "solid"
    ls isa AbstractString && (ls = get(DASH_STRINGS, ls, nothing))
    (ls === nothing || ls === :solid) && return "solid"
    ls === :dash && return "dashed"
    ls === :dot && return "dotted"
    ls === :dashdot && return "dashdot"
    ls === :dashdotdot && return "dashdot"
    return "solid"
end

function _marker_code(m)::String
    m === nothing && return ""
    sym = marker_symbol(m)
    return get(MARKER_CODE, sym, "o")
end

function _scale_name(f)::String
    f === identity && return "linear"
    f === log10 && return "log10"
    f === log2 && return "log2"
    f === log && return "ln"
    f === sqrt && return "sqrt"
    return "linear"
end

function _tex_string(t)::String
    is_empty_text(t) && return ""
    t isa RichText || return plaintext(t)
    buf = IOBuffer()
    for p in t.parts
        isempty(p.text) && continue
        if p.shift > 0.1
            print(buf, "^{", p.text, "}")
        elseif p.shift < -0.1
            print(buf, "_{", p.text, "}")
        else
            print(buf, p.text)
        end
    end
    return String(take!(buf))
end

const SUPERSCRIPTS = Dict(
    '-' => '⁻', '+' => '⁺', '0' => '⁰', '1' => '¹', '2' => '²', '3' => '³', '4' => '⁴',
    '5' => '⁵', '6' => '⁶', '7' => '⁷', '8' => '⁸', '9' => '⁹',
)

function _plain_tick(t)::String
    is_empty_text(t) && return ""
    t isa RichText || return plaintext(t)
    buf = IOBuffer()
    for p in t.parts
        if p.shift > 0.1
            for ch in p.text
                print(buf, get(SUPERSCRIPTS, ch, ch))
            end
        else
            print(buf, p.text)
        end
    end
    return String(take!(buf))
end

function _colormap_spec(cm)
    stops = to_colormap(cm)
    return [[round(Float64(red(c)), digits = 4), round(Float64(green(c)), digits = 4), round(Float64(blue(c)), digits = 4)] for c in stops]
end

function _align4!(io::IOBuffer)
    rem = position(io) % 4
    rem == 0 || write(io, zeros(UInt8, 4 - rem))
end

function _pack_f32(io::IOBuffer, values; inline_limit::Int = 64)
    n = length(values)
    n <= inline_limit && return [isfinite(v) ? Float64(v) : nothing for v in values]
    _align4!(io)
    off = position(io)
    for v in values
        write(io, Float32(v))
    end
    return Dict{String, Any}("buf" => true, "dtype" => "f32", "offset" => off, "length" => n)
end

function _pack_u32(io::IOBuffer, values; inline_limit::Int = 64)
    n = length(values)
    n <= inline_limit && return [Int(v) for v in values]
    _align4!(io)
    off = position(io)
    for v in values
        write(io, UInt32(v))
    end
    return Dict{String, Any}("buf" => true, "dtype" => "u32", "offset" => off, "length" => n)
end

function _pack_u8(io::IOBuffer, values::Vector{UInt8})
    _align4!(io)
    off = position(io)
    write(io, values)
    return Dict{String, Any}("buf" => true, "dtype" => "u8", "offset" => off, "length" => length(values))
end

function _finite_mask(vals)
    return [isfinite(v) ? Float64(v) : nothing for v in vals]
end

function _colors_spec(c, n::Int, a::Dict{Symbol, Any})
    resolved = resolve_colors(c, n, a)
    if resolved isa AbstractVector
        return [_css_color(one) for one in resolved]
    end
    return _css_color(resolved)
end

function _plot2d_spec(p::Plot{K}, ax::Axis, io::IOBuffer) where {K}
    a = getfield(p, :attrs)
    a[:visible] || return nothing
    d = converted(p)
    lbl = is_empty_text(a[:label]) ? "" : _tex_string(a[:label])
    base = Dict{String, Any}("kind" => string(K), "label" => lbl)

    if K in (:lines, :stairs, :scatter, :scatterlines)
        x, y = K === :stairs ? stair_points(d.x, d.y, a[:step]) : (d.x, d.y)
        base["x"] = _pack_f32(io, x)
        base["y"] = _pack_f32(io, y)
        if K !== :scatter
            base["linewidth"] = Float64(a[:linewidth])
            base["linestyle"] = _linestyle_name(a[:linestyle])
        end
        col = a[:color]
        if col isa AbstractArray{<:Real}
            base["color_values"] = _pack_f32(io, vec(col))
            base["colormap"] = _colormap_spec(a[:colormap])
            r = _crange(get(a, :colorrange, :automatic), col)
            base["colorrange"] = [r[1], r[2]]
            base["colors"] = [_css_color(one) for one in resolve_colors(col, length(x), a)]
            base["color"] = _css_color(_plot_color(p))
        elseif col isa AbstractVector && !(col isa Tuple)
            base["colors"] = [_css_color(with_alpha(one, a[:alpha])) for one in col]
            base["color"] = _css_color(_plot_color(p))
        else
            base["color"] = _css_color(with_alpha(col, a[:alpha]))
        end
        if K in (:scatter, :scatterlines)
            base["marker"] = _marker_code(a[:marker] isa AbstractVector ? first(a[:marker]) : a[:marker])
            ms = a[:markersize] isa AbstractVector ? Float64.(a[:markersize]) : Float64(a[:markersize])
            base["markersize"] = ms
            base["strokecolor"] = _css_color(a[:strokecolor])
            base["strokewidth"] = Float64(a[:strokewidth])
            if K === :scatterlines && a[:markercolor] !== :inherit
                base["markercolor"] = _colors_spec(a[:markercolor], length(x), a)
            end
        end
        return base
    elseif K === :linesegments
        base["x"] = _pack_f32(io, d.x)
        base["y"] = _pack_f32(io, d.y)
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        base["color"] = _colors_spec(a[:color], length(d.x), a)
        return base
    elseif K === :stem
        off = a[:offset]
        base_vals = off isa Real ? fill(Float64(off), length(d.x)) : Float64.(off)
        base["x"] = _pack_f32(io, d.x)
        base["y"] = _pack_f32(io, d.y)
        base["baseline"] = _pack_f32(io, base_vals)
        base["color"] = _css_color(with_alpha(_mid(a[:color]), a[:alpha]))
        stemc = a[:stemcolor] === :inherit ? a[:color] : a[:stemcolor]
        base["stemcolor"] = _colors_spec(stemc, length(d.x), a)
        trunkc = a[:trunkcolor] === :inherit ? (a[:color] isa AbstractVector ? :black : a[:color]) : a[:trunkcolor]
        base["trunkcolor"] = _css_color(with_alpha(trunkc, a[:alpha]))
        base["stemwidth"] = Float64(a[:stemwidth])
        base["stemlinestyle"] = _linestyle_name(a[:stemlinestyle])
        base["trunkwidth"] = Float64(a[:trunkwidth])
        base["trunklinestyle"] = _linestyle_name(a[:trunklinestyle])
        base["marker"] = _marker_code(a[:marker])
        base["markersize"] = Float64(a[:markersize] isa AbstractVector ? first(a[:markersize]) : a[:markersize])
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["strokewidth"] = Float64(a[:strokewidth])
        return base
    elseif K === :barplot || K === :hist
        rects = if K === :hist
            c, h, w = hist_bars(d.values, a[:bins], a[:normalization])
            r = [(c[i] - w[i] / 2 * (1 - a[:gap]), c[i] + w[i] / 2 * (1 - a[:gap]), Float64(a[:fillto]), h[i]) for i in eachindex(c)]
            a[:direction] === :x ? [(q[3], q[4], q[1], q[2]) for q in r] : r
        else
            bar_rects(d.x, d.y, a[:width], a[:gap], a[:fillto], a[:direction])
        end
        x0 = [r[1] for r in rects]
        x1 = [r[2] for r in rects]
        y0 = [r[3] for r in rects]
        y1 = [r[4] for r in rects]
        base["x0"] = _pack_f32(io, x0)
        base["x1"] = _pack_f32(io, x1)
        base["y0"] = _pack_f32(io, y0)
        base["y1"] = _pack_f32(io, y1)
        cols = _colors_spec(a[:color], length(rects), a)
        base["color"] = cols
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["strokewidth"] = Float64(a[:strokewidth])
        return base
    elseif K === :errorbars
        base["x"] = _pack_f32(io, d.x)
        base["y"] = _pack_f32(io, d.y)
        base["low"] = _pack_f32(io, d.low)
        base["high"] = _pack_f32(io, d.high)
        base["direction"] = string(a[:direction])
        base["linewidth"] = Float64(a[:linewidth])
        base["whiskerwidth"] = Float64(a[:whiskerwidth])
        base["color"] = _colors_spec(a[:color], length(d.x), a)
        return base
    elseif K === :band
        base["x"] = _pack_f32(io, d.x)
        base["lo"] = _pack_f32(io, d.lo)
        base["hi"] = _pack_f32(io, d.hi)
        base["color"] = _css_color(resolve_colors(a[:color], 1, a))
        return base
    elseif K === :area
        base["x"] = _pack_f32(io, d.x)
        base["y"] = _pack_f32(io, d.y)
        base["baseline"] = Float64(a[:baseline])
        c = resolve_colors(a[:color], 1, a)
        base["color"] = _css_color(c)
        base["fillcolor"] = _css_color(with_alpha(c, a[:fillalpha]))
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        return base
    elseif K === :heatmap
        cmap = to_colormap(a[:colormap])
        r = _crange(a[:colorrange], d.Z)
        nx, ny = size(d.Z)
        # Pack row-major from bottom (j = 1..ny) or column-major: keep (nx, ny) explicit.
        zflat = Float64[d.Z[i, j] for j in 1:ny for i in 1:nx]  # y-outer, x-inner (length = nx * ny)
        base["xe"] = _pack_f32(io, d.xe)
        base["ye"] = _pack_f32(io, d.ye)
        base["nx"] = nx
        base["ny"] = ny
        base["z"] = _pack_f32(io, zflat; inline_limit = 32)
        base["colormap"] = _colormap_spec(cmap)
        base["colorrange"] = [r[1], r[2]]
        base["nancolor"] = _css_color(a[:nan_color])
        base["interpolate"] = Bool(a[:interpolate])
        base["alpha"] = Float64(a[:alpha])
        return base
    elseif K === :image
        img = d.img
        nx, ny = size(img)
        xe = [Float64(d.x[1]) + (Float64(d.x[2]) - Float64(d.x[1])) * (i - 1) / nx for i in 1:(nx + 1)]
        ye = [Float64(d.y[1]) + (Float64(d.y[2]) - Float64(d.y[1])) * (j - 1) / ny for j in 1:(ny + 1)]
        base["xe"] = _pack_f32(io, xe)
        base["ye"] = _pack_f32(io, ye)
        base["nx"] = nx
        base["ny"] = ny
        base["interpolate"] = Bool(a[:interpolate])
        base["alpha"] = Float64(a[:alpha])
        if eltype(img) <: Real
            cmap = to_colormap(a[:colormap])
            r = _crange(a[:colorrange], img)
            zflat = Float64[img[i, j] for j in 1:ny for i in 1:nx]
            base["kind"] = "heatmap"
            base["z"] = _pack_f32(io, zflat; inline_limit = 32)
            base["colormap"] = _colormap_spec(cmap)
            base["colorrange"] = [r[1], r[2]]
            base["nancolor"] = "transparent"
        else
            rgba = UInt8[]
            sizehint!(rgba, 4 * nx * ny)
            for j in ny:-1:1, i in 1:nx
                c = with_alpha(img[i, j], a[:alpha])
                push!(rgba,
                    clamp(round(UInt8, red(c) * 255), 0, 255),
                    clamp(round(UInt8, green(c) * 255), 0, 255),
                    clamp(round(UInt8, blue(c) * 255), 0, 255),
                    clamp(round(UInt8, alpha(c) * 255), 0, 255),
                )
            end
            base["rgba"] = _pack_u8(io, rgba)
        end
        return base
    elseif K === :contour
        levels = contour_levels(a[:levels], d.Z)
        r = _crange(a[:colorrange], levels)
        cmap = to_colormap(a[:colormap])
        groups = Any[]
        for lv in levels
            c = a[:color] === nothing ? colormap_value(cmap, lv, r) : to_color(a[:color])
            segs = contour_segments(d.x, d.y, d.Z, lv)
            isempty(segs) && continue
            coords = Float64[]
            sizehint!(coords, 4 * length(segs))
            for (x1, y1, x2, y2) in segs
                push!(coords, x1, y1, x2, y2)
            end
            push!(groups, Dict{String, Any}(
                "level" => Float64(lv),
                "color" => _css_color(with_alpha(c, a[:alpha])),
                "coords" => _pack_f32(io, coords; inline_limit = 32),
            ))
        end
        base["groups"] = groups
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        return base
    elseif K === :contourf
        levels = contour_levels(a[:levels], d.Z; filled = true)
        cmap = to_colormap(a[:colormap])
        nb = length(levels) - 1
        colors = [_css_color(with_alpha(sample(cmap, nb == 1 ? 0.5 : (b - 1) / (nb - 1)), a[:alpha])) for b in 1:nb]
        polys = contourf_polygons(d.x, d.y, d.Z, levels)
        bands = [Any[] for _ in 1:nb]
        for (b, poly) in polys
            xy = Float64[]
            sizehint!(xy, 2 * length(poly))
            for q in poly
                push!(xy, q[1], q[2])
            end
            push!(bands[b], xy)
        end
        out_bands = Any[]
        for b in 1:nb
            isempty(bands[b]) && continue
            push!(out_bands, Dict{String, Any}("color" => colors[b], "polygons" => bands[b]))
        end
        base["levels"] = Float64.(levels)
        base["bands"] = out_bands
        return base
    elseif K === :hlines || K === :vlines
        base["values"] = _pack_f32(io, d.values)
        base["color"] = _colors_spec(a[:color], length(d.values), a)
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        if K === :hlines
            base["min"] = [Float64(_at(a[:xmin], i)) for i in eachindex(d.values)]
            base["max"] = [Float64(_at(a[:xmax], i)) for i in eachindex(d.values)]
        else
            base["min"] = [Float64(_at(a[:ymin], i)) for i in eachindex(d.values)]
            base["max"] = [Float64(_at(a[:ymax], i)) for i in eachindex(d.values)]
        end
        return base
    elseif K === :ablines
        base["a"] = _pack_f32(io, d.a)
        base["b"] = _pack_f32(io, d.b)
        base["color"] = _colors_spec(a[:color], length(d.a), a)
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        return base
    elseif K === :poly
        base["x"] = _pack_f32(io, d.x)
        base["y"] = _pack_f32(io, d.y)
        base["color"] = _css_color(resolve_colors(a[:color], 1, a))
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["strokewidth"] = Float64(a[:strokewidth])
        return base
    elseif K === :series || K === :multiline
        n = size(d.Y, 1)
        colors = series_colors(a[:color], n)
        x = Float64.(d.x)
        items = Any[]
        lbls = a[:labels]
        for s in 1:n
            push!(items, Dict{String, Any}(
                "y" => _pack_f32(io, view(d.Y, s, :)),
                "color" => _css_color(with_alpha(colors[s], a[:alpha])),
                "label" => lbls !== nothing && s <= length(lbls) ? _tex_string(lbls[s]) : "",
            ))
        end
        base["x"] = _pack_f32(io, x)
        base["series"] = items
        base["linewidth"] = Float64(a[:linewidth])
        base["linestyle"] = _linestyle_name(a[:linestyle])
        base["marker"] = _marker_code(a[:marker])
        base["markersize"] = Float64(a[:markersize])
        return base
    elseif K === :text
        texts = d.text === nothing ? a[:text] : d.text
        xs, ys = isempty(d.x) && a[:position] !== nothing ? ([Float64(a[:position][1])], [Float64(a[:position][2])]) : (d.x, d.y)
        entries = Any[]
        for i in eachindex(xs)
            s = texts isa AbstractVector ? texts[mod1(i, length(texts))] : texts
            c = _at(a[:color] isa AbstractVector ? a[:color] : [a[:color]], i)
            off = a[:offset]
            o = off isa AbstractVector ? off[mod1(i, length(off))] : off
            push!(entries, Dict{String, Any}(
                "x" => Float64(xs[i]), "y" => Float64(ys[i]),
                "text" => _plain_tick(s),
                "color" => _css_color(with_alpha(c, a[:alpha])),
                "fontsize" => Float64(_at(a[:fontsize], i)),
                "rotation" => Float64(_at(a[:rotation], i)),
                "offset" => [Float64(o[1]), Float64(o[2])],
                "halign" => string(a[:align][1]),
                "valign" => string(a[:align][2]),
            ))
        end
        base["items"] = entries
        return base
    elseif K === :annotation
        base["xt"] = d.xt; base["yt"] = d.yt
        base["x"] = d.x; base["y"] = d.y
        base["text"] = _plain_tick(a[:text])
        base["color"] = _css_color(to_color(a[:color]))
        base["fontsize"] = Float64(a[:fontsize])
        base["linewidth"] = Float64(a[:linewidth])
        base["arrowsize"] = Float64(a[:arrowsize])
        return base
    elseif K === :mesh && d.flat
        cols = mesh_vertex_colors(a, d)
        tris = Any[]
        for f in 1:size(d.F, 1)
            ids = d.F[f, :]
            c = mesh_face_color(a, cols, ids)
            push!(tris, Dict{String, Any}(
                "color" => _css_color(c),
                "x" => [Float64(d.V[k, 1]) for k in ids],
                "y" => [Float64(d.V[k, 2]) for k in ids],
            ))
        end
        base["kind"] = "mesh2d"
        base["triangles"] = tris
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["strokewidth"] = Float64(a[:strokewidth])
        return base
    end
    return nothing
end

function _vertex_rgb_f32(colors, n::Int)::Vector{Float32}
    out = Vector{Float32}(undef, 3 * n)
    for i in 1:n
        c = colors isa AbstractVector ? _at(colors, i) : to_color(colors)
        out[3i - 2] = Float32(red(c))
        out[3i - 1] = Float32(green(c))
        out[3i] = Float32(blue(c))
    end
    return out
end

function _plot3d_spec(p::Plot{K}, io::IOBuffer) where {K}
    a = getfield(p, :attrs)
    a[:visible] || return nothing
    d = converted(p)
    lbl = is_empty_text(a[:label]) ? "" : _tex_string(a[:label])
    base = Dict{String, Any}("kind" => string(K), "label" => lbl)

    if K === :surface
        nx, ny = size(d.Z)
        n = nx * ny
        pos = Vector{Float32}(undef, 3 * n)
        valid = falses(nx, ny)
        k = 1
        for j in 1:ny, i in 1:nx
            xv, yv, zv = d.X[i, j], d.Y[i, j], d.Z[i, j]
            ok = isfinite(xv) && isfinite(yv) && isfinite(zv)
            valid[i, j] = ok
            pos[3k - 2] = ok ? Float32(xv) : 0f0
            pos[3k - 1] = ok ? Float32(yv) : 0f0
            pos[3k] = ok ? Float32(zv) : 0f0
            k += 1
        end
        idx = UInt32[]
        sizehint!(idx, 6 * max(0, nx - 1) * max(0, ny - 1))
        for j in 1:(ny - 1), i in 1:(nx - 1)
            v1 = (j - 1) * nx + (i - 1)
            v2 = v1 + 1
            v3 = v1 + nx
            v4 = v3 + 1
            if valid[i, j] && valid[i + 1, j] && valid[i + 1, j + 1]
                push!(idx, UInt32(v1), UInt32(v2), UInt32(v4))
            end
            if valid[i, j] && valid[i + 1, j + 1] && valid[i, j + 1]
                push!(idx, UInt32(v1), UInt32(v4), UInt32(v3))
            end
        end
        base["positions"] = _pack_f32(io, pos; inline_limit = 0)
        base["indices"] = _pack_u32(io, idx; inline_limit = 0)
        base["nx"] = nx; base["ny"] = ny
        base["alpha"] = Float64(a[:alpha])
        base["strokewidth"] = Float64(a[:strokewidth])
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["shading"] = string(a[:shading])
        c = a[:color]
        if c isa Union{Symbol, Colorant, AbstractString}
            base["color"] = _css_color(to_color(c))
        else
            values = c isa AbstractMatrix{<:Real} ? c : d.Z
            vals = Float32[valid[i, j] && isfinite(values[i, j]) ? Float32(values[i, j]) : 0f0 for j in 1:ny for i in 1:nx]
            r = _crange(a[:colorrange], values)
            base["values"] = _pack_f32(io, vals; inline_limit = 0)
            base["colorrange"] = [r[1], r[2]]
            base["colormap"] = _colormap_spec(a[:colormap])
        end
        return base
    elseif K === :wireframe
        nx, ny = size(d.Z)
        n = nx * ny
        pos = Vector{Float32}(undef, 3 * n)
        valid = falses(nx, ny)
        k = 1
        for j in 1:ny, i in 1:nx
            xv, yv, zv = d.X[i, j], d.Y[i, j], d.Z[i, j]
            ok = isfinite(xv) && isfinite(yv) && isfinite(zv)
            valid[i, j] = ok
            pos[3k - 2] = ok ? Float32(xv) : 0f0
            pos[3k - 1] = ok ? Float32(yv) : 0f0
            pos[3k] = ok ? Float32(zv) : 0f0
            k += 1
        end
        idx = UInt32[]
        for j in 1:ny, i in 1:(nx - 1)
            (valid[i, j] && valid[i + 1, j]) || continue
            v1 = (j - 1) * nx + (i - 1)
            push!(idx, UInt32(v1), UInt32(v1 + 1))
        end
        for j in 1:(ny - 1), i in 1:nx
            (valid[i, j] && valid[i, j + 1]) || continue
            v1 = (j - 1) * nx + (i - 1)
            push!(idx, UInt32(v1), UInt32(v1 + nx))
        end
        base["positions"] = _pack_f32(io, pos; inline_limit = 0)
        base["indices"] = _pack_u32(io, idx; inline_limit = 0)
        base["color"] = _css_color(resolve_colors(a[:color], 1, a))
        base["linewidth"] = Float64(a[:linewidth])
        return base
    elseif K === :mesh
        n = size(d.V, 1)
        pos = Vector{Float32}(undef, 3 * n)
        for i in 1:n
            pos[3i - 2] = Float32(d.V[i, 1])
            pos[3i - 1] = Float32(d.V[i, 2])
            pos[3i] = Float32(d.V[i, 3])
        end
        m = size(d.F, 1)
        idx = Vector{UInt32}(undef, 3 * m)
        for f in 1:m
            idx[3f - 2] = UInt32(d.F[f, 1] - 1)
            idx[3f - 1] = UInt32(d.F[f, 2] - 1)
            idx[3f] = UInt32(d.F[f, 3] - 1)
        end
        base["positions"] = _pack_f32(io, pos; inline_limit = 0)
        base["indices"] = _pack_u32(io, idx; inline_limit = 0)
        base["alpha"] = Float64(a[:alpha])
        base["strokewidth"] = Float64(a[:strokewidth])
        base["strokecolor"] = _css_color(a[:strokecolor])
        base["shading"] = string(a[:shading])
        c = a[:color]
        if c isa AbstractVector{<:Real}
            r = _crange(a[:colorrange], c)
            base["values"] = _pack_f32(io, c; inline_limit = 0)
            base["colorrange"] = [r[1], r[2]]
            base["colormap"] = _colormap_spec(a[:colormap])
        elseif c isa AbstractVector
            cols = resolve_colors(c, n, a)
            base["vertexcolors"] = _pack_f32(io, _vertex_rgb_f32(cols, n); inline_limit = 0)
        else
            base["color"] = _css_color(resolve_colors(c, 1, a))
        end
        return base
    elseif K in (:lines, :scatter, :scatterlines, :linesegments, :stem)
        n = length(d.x)
        z = hasproperty(d, :z) && d.z !== nothing ? d.z : zeros(Float64, n)
        pos = Vector{Float32}(undef, 3 * n)
        for i in 1:n
            pos[3i - 2] = Float32(d.x[i])
            pos[3i - 1] = Float32(d.y[i])
            pos[3i] = Float32(z[i])
        end
        base["positions"] = _pack_f32(io, pos; inline_limit = 0)
        cols = resolve_colors(a[:color], n, a)
        if cols isa AbstractVector
            base["vertexcolors"] = _pack_f32(io, _vertex_rgb_f32(cols, n); inline_limit = 0)
            base["color"] = _css_color(_plot_color(p))
        else
            base["color"] = _css_color(cols)
        end
        if haskey(a, :linewidth)
            base["linewidth"] = Float64(a[:linewidth])
        end
        if K in (:scatter, :scatterlines, :stem)
            base["markersize"] = Float64(a[:markersize] isa AbstractVector ? first(a[:markersize]) : a[:markersize])
            base["marker"] = _marker_code(a[:marker] isa AbstractVector ? first(a[:marker]) : a[:marker])
        end
        if K === :stem
            off = Float64(a[:offset] isa Real ? a[:offset] : 0.0)
            base["offset"] = off
        end
        return base
    end
    return nothing
end

function _legend_entries_spec(lg::Legend)
    out = Any[]
    for (label, els) in legend_entries(lg)
        first_line = findfirst(e -> e isa LineElement, els)
        first_mark = findfirst(e -> e isa MarkerElement, els)
        first_poly = findfirst(e -> e isa PolyElement, els)
        entry = Dict{String, Any}("label" => _tex_string(label))
        if first_line !== nothing
            ea = els[first_line].attrs
            entry["line"] = Dict(
                "color" => _css_color(ea[:color]),
                "linestyle" => _linestyle_name(ea[:linestyle]),
                "linewidth" => Float64(ea[:linewidth]),
            )
        end
        if first_mark !== nothing
            ma = els[first_mark].attrs
            entry["marker"] = Dict(
                "shape" => _marker_code(ma[:marker]),
                "color" => _css_color(ma[:color]),
                "size" => Float64(ma[:markersize]),
                "strokecolor" => _css_color(ma[:strokecolor]),
                "strokewidth" => Float64(ma[:strokewidth]),
            )
        end
        if first_poly !== nothing
            pa = els[first_poly].attrs
            entry["patch"] = Dict(
                "color" => _css_color(pa[:color]),
                "strokecolor" => _css_color(pa[:strokecolor]),
                "strokewidth" => Float64(pa[:strokewidth]),
            )
        end
        push!(out, entry)
    end
    return out
end

function _legend_spec(lg::Legend)
    a = getfield(lg, :attrs)
    a[:visible] || return nothing
    entries = _legend_entries_spec(lg)
    isempty(entries) && return nothing
    return Dict{String, Any}(
        "title" => is_empty_text(a[:title]) ? "" : _tex_string(a[:title]),
        "position" => string(a[:position]),
        "orientation" => string(a[:orientation]),
        "framevisible" => Bool(a[:framevisible]),
        "backgroundcolor" => _css_color(a[:backgroundcolor]),
        "framecolor" => _css_color(a[:framecolor]),
        "entries" => entries,
    )
end

function _colorbar_spec(cb::Colorbar, st::ColorbarState)
    a = getfield(cb, :attrs)
    return Dict{String, Any}(
        "kind" => "colorbar",
        "label" => a[:labelvisible] && !is_empty_text(a[:label]) ? _tex_string(a[:label]) : "",
        "limits" => [st.lims[1], st.lims[2]],
        "colormap" => [[round(Float64(red(c)), digits = 4), round(Float64(green(c)), digits = 4), round(Float64(blue(c)), digits = 4)] for c in st.cmap],
        "ticks" => Float64.(st.ticks),
        "ticklabels" => [_plain_tick(l) for l in st.labels],
        "levels" => st.levels === nothing ? nothing : Float64.(st.levels),
        "vertical" => Bool(a[:vertical]),
        "flipaxis" => Bool(a[:flipaxis]),
    )
end

function _axis2d_spec(ax::Axis, st::AxisState, axis_id::Int, io::IOBuffer, link_ids::IdDict{Any, Int})
    a = getfield(ax, :attrs)
    fx, fy = a[:xscale], a[:yscale]
    gx, gy = inverse(fx), inverse(fy)
    xl = (gx(st.xlims[1]), gx(st.xlims[2]))
    yl = (gy(st.ylims[1]), gy(st.ylims[2]))
    plots = Any[]
    for p in ax.plots
        ps = _plot2d_spec(p, ax, io)
        ps === nothing || push!(plots, ps)
    end
    legends = Any[]
    for lg in ax.legends
        ls = _legend_spec(lg)
        ls === nothing || push!(legends, ls)
    end
    return Dict{String, Any}(
        "kind" => "axis",
        "index" => axis_id,
        "title" => a[:titlevisible] ? _tex_string(a[:title]) : "",
        "subtitle" => a[:subtitlevisible] ? _tex_string(a[:subtitle]) : "",
        "titlealign" => string(a[:titlealign]),
        "xlabel" => a[:xlabelvisible] ? _tex_string(a[:xlabel]) : "",
        "ylabel" => a[:ylabelvisible] ? _tex_string(a[:ylabel]) : "",
        "limits" => [xl[1], xl[2], yl[1], yl[2]],
        "xscale" => _scale_name(fx),
        "yscale" => _scale_name(fy),
        "xreversed" => Bool(st.xreversed),
        "yreversed" => Bool(st.yreversed),
        "yaxisposition" => string(a[:yaxisposition]),
        "xaxisposition" => string(a[:xaxisposition]),
        "backgroundcolor" => _css_color(a[:backgroundcolor]),
        "xgridvisible" => Bool(a[:xgridvisible]),
        "ygridvisible" => Bool(a[:ygridvisible]),
        "xticksvisible" => Bool(a[:xticksvisible]),
        "yticksvisible" => Bool(a[:yticksvisible]),
        "xticklabelsvisible" => Bool(a[:xticklabelsvisible]),
        "yticklabelsvisible" => Bool(a[:yticklabelsvisible]),
        "xticks" => Float64.(st.xticks),
        "xticklabels" => [_plain_tick(l) for l in st.xlabels],
        "yticks" => Float64.(st.yticks),
        "yticklabels" => [_plain_tick(l) for l in st.ylabels],
        "topspinevisible" => Bool(a[:topspinevisible]),
        "rightspinevisible" => Bool(a[:rightspinevisible]),
        "leftspinevisible" => Bool(a[:leftspinevisible]),
        "bottomspinevisible" => Bool(a[:bottomspinevisible]),
        "linkX" => get(link_ids, ax.xgroup, nothing),
        "linkY" => get(link_ids, ax.ygroup, nothing),
        "aspect" => a[:aspect] isa DataAspect ? "data" : a[:aspect] isa AxisAspect ? a[:aspect].ratio : nothing,
        "legends" => legends,
        "plots" => plots,
    )
end

function _axis3d_spec(ax::Axis3, st::Axis3State, axis_id::Int, io::IOBuffer)
    a = getfield(ax, :attrs)
    lo = (st.lims[1][1], st.lims[2][1], st.lims[3][1])
    hi = (st.lims[1][2], st.lims[2][2], st.lims[3][2])
    asp = a[:aspect]
    half = if asp === :data
        spans = (hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
        m = max(maximum(spans), 1e-12)
        (spans[1] / m, spans[2] / m, spans[3] / m)
    elseif asp === :equal
        (1.0, 1.0, 1.0)
    else
        m = max(maximum(asp), 1e-12)
        (Float64(asp[1]) / m, Float64(asp[2]) / m, Float64(asp[3]) / m)
    end
    plots = Any[]
    for p in ax.plots
        ps = _plot3d_spec(p, io)
        ps === nothing || push!(plots, ps)
    end
    legends = Any[]
    for lg in ax.legends
        ls = _legend_spec(lg)
        ls === nothing || push!(legends, ls)
    end
    return Dict{String, Any}(
        "kind" => "axis3",
        "index" => axis_id,
        "title" => a[:titlevisible] ? _tex_string(a[:title]) : "",
        "xlabel" => a[:xlabelvisible] ? _tex_string(a[:xlabel]) : "",
        "ylabel" => a[:ylabelvisible] ? _tex_string(a[:ylabel]) : "",
        "zlabel" => a[:zlabelvisible] ? _tex_string(a[:zlabel]) : "",
        "limits" => [lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]],
        "half" => [half[1], half[2], half[3]],
        "azimuth" => Float64(a[:azimuth]),
        "elevation" => Float64(a[:elevation]),
        "perspectiveness" => Float64(a[:perspectiveness]),
        "backgroundcolor" => _css_color(a[:backgroundcolor]),
        "xticks" => Float64.(st.ticks[1]),
        "xticklabels" => [_plain_tick(l) for l in st.labels[1]],
        "yticks" => Float64.(st.ticks[2]),
        "yticklabels" => [_plain_tick(l) for l in st.labels[2]],
        "zticks" => Float64.(st.ticks[3]),
        "zticklabels" => [_plain_tick(l) for l in st.labels[3]],
        "xgridvisible" => Bool(a[:xgridvisible]),
        "ygridvisible" => Bool(a[:ygridvisible]),
        "zgridvisible" => Bool(a[:zgridvisible]),
        "legends" => legends,
        "plots" => plots,
    )
end

function _track_spec(n::Int, sizes::Dict{Int, Any}, is_fixed_content::AbstractVector{Bool})
    out = Any[]
    for i in 1:n
        s = get(sizes, i, Auto())
        if s isa Fixed
            push!(out, Dict("kind" => "fixed", "value" => Float64(s.x)))
        elseif s isa Relative
            push!(out, Dict("kind" => "relative", "value" => Float64(s.x)))
        elseif is_fixed_content[i]
            push!(out, Dict("kind" => "auto", "value" => 1.0))
        else
            push!(out, Dict("kind" => "fr", "value" => s isa Auto ? Float64(s.ratio) : 1.0))
        end
    end
    return out
end

function _layout_spec(g::GridLayout, states::IdDict{Any, Any}, axis_ids::IdDict{Any, Int},
        link_ids::IdDict{Any, Int}, io::IOBuffer, fig::Figure)
    nc, nr = max(g.ncols, 1), max(g.nrows, 1)
    row_single_plot = falses(nr)
    col_single_plot = falses(nc)
    row_single_chrome = falses(nr)
    col_single_chrome = falses(nc)
    row_any_plot = falses(nr)
    col_any_plot = falses(nc)
    items = Any[]

    for c in g.content
        rows = _resolve(c.rows, nr)
        cols = _resolve(c.cols, nc)
        item = c.item
        chrome = item isa Label || item isa Colorbar || item isa Legend
        if chrome
            length(rows) == 1 && (row_single_chrome[first(rows)] = true)
            length(cols) == 1 && (col_single_chrome[first(cols)] = true)
        else
            for r in rows
                1 <= r <= nr && (row_any_plot[r] = true)
            end
            for k in cols
                1 <= k <= nc && (col_any_plot[k] = true)
            end
            length(rows) == 1 && (row_single_plot[first(rows)] = true)
            length(cols) == 1 && (col_single_plot[first(cols)] = true)
        end
        block = if item isa GridLayout
            _layout_spec(item, states, axis_ids, link_ids, io, fig)
        elseif item isa Axis && haskey(states, item)
            _axis2d_spec(item, states[item], axis_ids[item], io, link_ids)
        elseif item isa Axis3 && haskey(states, item)
            _axis3d_spec(item, states[item], axis_ids[item], io)
        elseif item isa Colorbar && haskey(states, item)
            _colorbar_spec(item, states[item])
        elseif item isa Label
            a = getfield(item, :attrs)
            a[:visible] ? Dict{String, Any}(
                "kind" => "label",
                "text" => _tex_string(a[:text]),
                "fontsize" => Float64(a[:fontsize]),
                "bold" => a[:font] === :bold,
                "color" => _css_color(a[:color]),
                "rotation" => Float64(a[:rotation]),
            ) : nothing
        elseif item isa Legend
            ls = _legend_spec(item)
            ls === nothing ? nothing : merge(Dict{String, Any}("kind" => "legend"), ls)
        else
            nothing
        end
        block === nothing && continue
        push!(items, Dict{String, Any}(
            "row" => first(rows),
            "rowEnd" => last(rows) + 1,
            "col" => first(cols),
            "colEnd" => last(cols) + 1,
            "block" => block,
        ))
    end

    row_only_chrome = [(!row_single_plot[r] && row_single_chrome[r]) || !row_any_plot[r] for r in 1:nr]
    col_only_chrome = [(!col_single_plot[k] && col_single_chrome[k]) || !col_any_plot[k] for k in 1:nc]
    colgap = something(g.colgap, Float64(fig.theme[:colgap]))
    rowgap = something(g.rowgap, Float64(fig.theme[:rowgap]))
    return Dict{String, Any}(
        "kind" => "grid",
        "nrows" => nr,
        "ncols" => nc,
        "colgap" => Float64(colgap),
        "rowgap" => Float64(rowgap),
        "cols" => _track_spec(nc, g.colsizes, col_only_chrome),
        "rows" => _track_spec(nr, g.rowsizes, row_only_chrome),
        "items" => items,
    )
end

"""
    scene_spec(fig) -> (Dict{String, Any}, Vector{UInt8})

Serialize `fig`'s solved layout, 2D/3D axes, limits, ticks, labels, colorbars, legends, and derived
plot primitives for interactive frontend rendering alongside a single little-endian binary payload
for large typed arrays.
"""
function scene_spec(fig::Figure)
    states, _ = layout_figure(fig)
    axes = axes_of(fig)
    axis_ids = IdDict{Any, Int}(ax => i for (i, ax) in enumerate(axes))
    link_ids = IdDict{Any, Int}()
    next_link = 0
    for ax in axes
        ax isa Axis || continue
        for grp in (ax.xgroup, ax.ygroup)
            length(grp) > 1 || continue
            haskey(link_ids, grp) || (link_ids[grp] = (next_link += 1))
        end
    end
    io = IOBuffer()
    layout = _layout_spec(fig.layout, states, axis_ids, link_ids, io, fig)
    spec = Dict{String, Any}(
        "id" => figure_id(fig),
        "title" => title(fig),
        "width" => round(Int, fig.size[1]),
        "height" => round(Int, fig.size[2]),
        "background" => _css_color(fig.backgroundcolor),
        "layout" => layout,
    )
    return spec, take!(io)
end

function _pair2(v)
    return (Float64(v[1]), Float64(v[2]))
end

function _limpair(cur)
    return cur isa Tuple && length(cur) == 2 ? cur : (nothing, nothing)
end

"""
    apply_view!(fig, view_state) -> fig

Apply frontend interactive axis view overrides (`axes` map or list with `index`, `limits`,
`azimuth`, `elevation`, `perspectiveness`, grid flags) onto a cloned `Figure` before export.
"""
function apply_view!(fig::Figure, view_state)
    view_state isa AbstractDict || return fig
    axes = axes_of(fig)
    entries = get(view_state, "axes", view_state)
    items = entries isa AbstractVector ? entries :
            entries isa AbstractDict ? values(entries) : ()
    for patch in items
        patch isa AbstractDict || continue
        idx = Int(get(patch, "index", 0))
        1 <= idx <= length(axes) || continue
        ax = axes[idx]
        if ax isa Axis
            lims = get(patch, "limits", nothing)
            if lims !== nothing && length(lims) == 4
                xl = (Float64(lims[1]), Float64(lims[2]))
                yl = (Float64(lims[3]), Float64(lims[4]))
                for other in ax.xgroup
                    cur = _limpair(attr(other, :limits))
                    other.attrs[:limits] = (xl, cur[2])
                end
                for other in ax.ygroup
                    cur = _limpair(attr(other, :limits))
                    other.attrs[:limits] = (cur[1], yl)
                end
            end
            haskey(patch, "xgridvisible") && (ax.attrs[:xgridvisible] = Bool(patch["xgridvisible"]))
            haskey(patch, "ygridvisible") && (ax.attrs[:ygridvisible] = Bool(patch["ygridvisible"]))
        elseif ax isa Axis3
            lims = get(patch, "limits", nothing)
            if lims !== nothing && length(lims) == 6
                ax.attrs[:limits] = (_pair2(lims[1:2]), _pair2(lims[3:4]), _pair2(lims[5:6]))
            end
            haskey(patch, "azimuth") && (ax.attrs[:azimuth] = Float64(patch["azimuth"]))
            haskey(patch, "elevation") && (ax.attrs[:elevation] = clamp(Float64(patch["elevation"]), -0.499π, 0.499π))
            haskey(patch, "perspectiveness") && (ax.attrs[:perspectiveness] = Float64(patch["perspectiveness"]))
            for g in (:xgridvisible, :ygridvisible, :zgridvisible)
                k = string(g)
                haskey(patch, k) && (ax.attrs[g] = Bool(patch[k]))
            end
        end
    end
    return fig
end
