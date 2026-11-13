# Legends: a block in the layout (`Legend(fig[1, 2], ax)`) or inside an axis (`axislegend(ax)`).
# Entries come from the axis' plots that have a `label`, or are given as elements and labels.

abstract type LegendElement end

"""`LineElement(; color, linestyle, linewidth)`: a line sample in a legend."""
struct LineElement <: LegendElement
    attrs::Dict{Symbol, Any}
end
LineElement(; color = :black, linestyle = nothing, linewidth = 1.5) =
    LineElement(Dict{Symbol, Any}(:color => color, :linestyle => linestyle, :linewidth => linewidth))

"""`MarkerElement(; marker, color, markersize, strokecolor, strokewidth)`: a marker sample."""
struct MarkerElement <: LegendElement
    attrs::Dict{Symbol, Any}
end
MarkerElement(; marker = :circle, color = :black, markersize = 9, strokecolor = :black, strokewidth = 0) =
    MarkerElement(Dict{Symbol, Any}(:marker => marker, :color => color, :markersize => markersize,
        :strokecolor => strokecolor, :strokewidth => strokewidth))

"""`PolyElement(; color, strokecolor, strokewidth)`: a filled patch."""
struct PolyElement <: LegendElement
    attrs::Dict{Symbol, Any}
end
PolyElement(; color = :gray, strokecolor = :black, strokewidth = 0) =
    PolyElement(Dict{Symbol, Any}(:color => color, :strokecolor => strokecolor, :strokewidth => strokewidth))

function legend_defaults(t::Theme)
    fs = theme_value(t, :Legend, :fontsize, 14)
    tc = theme_value(t, :Legend, :textcolor, :black)
    return Dict{Symbol, Any}(
        :title => nothing, :titlesize => fs, :titlefont => :bold, :titlecolor => tc, :labelsize => fs,
        :labelcolor => tc, :framevisible => true, :framecolor => tc, :framewidth => 1.0,
        :backgroundcolor => :white, :padding => (6.0, 6.0, 6.0, 6.0), :patchsize => (20.0, 20.0),
        :patchlabelgap => 5.0, :rowgap => 3.0, :colgap => 16.0, :titlegap => 8.0, :orientation => :vertical,
        :position => :rt, :margin => (6.0, 6.0, 6.0, 6.0), :halign => :center, :valign => :center,
        :tellwidth => true, :tellheight => true, :width => nothing, :height => nothing, :visible => true,
    )
end

"""A vertical legend tells the layout its width, a horizontal one its height (Makie's usual setup)."""
function _legend_attrs(fig, kwargs)
    attrs = block_attributes(fig, :Legend, legend_defaults(fig.theme), kwargs)
    horizontal = attrs[:orientation] === :horizontal
    haskey(kwargs, :tellwidth) || (attrs[:tellwidth] = !horizontal)
    haskey(kwargs, :tellheight) || (attrs[:tellheight] = horizontal)
    return attrs
end

"""
    Legend(fig[i, j], ax, title = nothing; kwargs...)
    Legend(fig[i, j], elements, labels, title = nothing; kwargs...)

A legend block. With an axis, entries are its plots that have a `label`. `elements` may be
plots, `LineElement`/`MarkerElement`/`PolyElement`, or vectors of them (drawn on top of each other).
"""
mutable struct Legend <: Block
    figure::Figure
    attrs::Dict{Symbol, Any}
    source::Any
    entries::Vector{Any}
end

function Legend(fig::Figure, source::AbstractAxis, title = nothing; register = true, kwargs...)
    attrs = _legend_attrs(fig, kwargs)
    title === nothing || (attrs[:title] = title)
    lg = Legend(fig, attrs, source, Any[])
    return register ? _register!(fig, lg) : lg
end

function Legend(fig::Figure, elements::AbstractVector, labels::AbstractVector, title = nothing; kwargs...)
    length(elements) == length(labels) || throw(DimensionMismatch("Legend: $(length(elements)) elements, $(length(labels)) labels"))
    attrs = _legend_attrs(fig, kwargs)
    title === nothing || (attrs[:title] = title)
    entries = Any[(labels[i], _elements(elements[i])) for i in eachindex(labels)]
    return _register!(fig, Legend(fig, attrs, nothing, entries))
end

Legend(gp::GridPosition, args...; kwargs...) = place!(gp, Legend(figure_of(gp), args...; kwargs...))

"""
    axislegend(ax = current_axis(), title = nothing; position = :rt, kwargs...)

A legend inside the axis. `position` is `:rt`, `:rb`, `:lt`, `:lb`, `:ct`, `:cb`, `:lc`, `:rc` or `:cc`.
"""
function axislegend(ax::AbstractAxis, title = nothing; kwargs...)
    lg = Legend(ax.figure, ax, title; register = false, kwargs...)
    push!(ax.legends, lg)
    return lg
end
axislegend(title::Union{Nothing, AbstractString} = nothing; kwargs...) = axislegend(_ax(current_axis()), title; kwargs...)

_elements(e::LegendElement) = LegendElement[e]
_elements(e::AbstractVector) = reduce(vcat, [_elements(x) for x in e]; init = LegendElement[])
_elements(p::AbstractPlot) = plot_elements(p)

_mid(c::AbstractVector) = isempty(c) ? to_color(:black) : to_color(c[cld(length(c), 2)])
_mid(c) = c

function _plot_color(p::Plot)
    a = getfield(p, :attrs)
    info = color_info(p)
    if info !== nothing
        return sample(to_colormap(info.colormap), 0.5)
    end
    c = get(a, :color, :black)
    c === nothing && return to_color(:black)
    c isa AbstractArray{<:Real} && return sample(to_colormap(a[:colormap]), 0.5)
    return with_alpha(_mid(c), get(a, :alpha, 1.0))
end

function plot_elements(p::Plot{K}) where {K}
    a = getfield(p, :attrs)
    c = _plot_color(p)
    line() = LineElement(; color = c, linestyle = get(a, :linestyle, nothing), linewidth = get(a, :linewidth, 1.5))
    if K in (:lines, :stairs, :linesegments, :hlines, :vlines, :ablines, :contour, :wireframe, :errorbars)
        return LegendElement[line()]
    elseif K === :scatter
        return LegendElement[MarkerElement(; marker = _first(a[:marker]), color = c, markersize = _first(a[:markersize]),
            strokecolor = a[:strokecolor], strokewidth = a[:strokewidth])]
    elseif K === :scatterlines
        return LegendElement[line(), MarkerElement(; marker = _first(a[:marker]), color = c, markersize = _first(a[:markersize]))]
    elseif K === :stem
        return LegendElement[LineElement(; color = c, linewidth = a[:stemwidth]), MarkerElement(; marker = _first(a[:marker]), color = c, markersize = _first(a[:markersize]))]
    elseif K === :area
        return LegendElement[PolyElement(; color = with_alpha(c, a[:fillalpha])), line()]
    end
    return LegendElement[PolyElement(; color = c, strokecolor = get(a, :strokecolor, :black), strokewidth = get(a, :strokewidth, 0))]
end
_first(x::AbstractVector) = first(x)
_first(x) = x

function legend_entries(lg::Legend)
    lg.source === nothing && return lg.entries
    out = Any[]
    for p in lg.source.plots
        a = getfield(p, :attrs)
        K = kind(p)
        if K in (:series, :multiline) && a[:labels] !== nothing
            n = size(converted(p).Y, 1)
            colors = series_colors(a[:color], n)
            for s in 1:min(n, length(a[:labels]))
                els = LegendElement[LineElement(; color = colors[s], linestyle = a[:linestyle], linewidth = a[:linewidth])]
                a[:marker] === nothing || push!(els, MarkerElement(; marker = a[:marker], color = colors[s], markersize = a[:markersize]))
                push!(out, (a[:labels][s], els))
            end
        elseif get(a, :label, nothing) !== nothing && !is_empty_text(a[:label])
            push!(out, (a[:label], plot_elements(p)))
        end
    end
    return out
end

struct LegendState
    entries::Vector{Any}
    size::Tuple{Float64, Float64}
    rows::Vector{Tuple{Float64, Float64, Float64}}  # x, y, row height (relative to the legend's top-left)
    titleheight::Float64
    protrusions::NTuple{4, Float64}
end

function prepare(lg::Legend)
    a = getfield(lg, :attrs)
    entries = legend_entries(lg)
    pw, ph = a[:patchsize]
    pad = a[:padding]
    th = a[:title] === nothing || is_empty_text(a[:title]) ? 0.0 : text_size(a[:title], a[:titlesize], a[:titlefont])[2]
    tw = th > 0 ? text_size(a[:title], a[:titlesize], a[:titlefont])[1] : 0.0
    rows = Tuple{Float64, Float64, Float64}[]
    x, y = pad[1], pad[4] + (th > 0 ? th + a[:titlegap] : 0.0)
    w = h = 0.0
    for (i, (label, _)) in enumerate(entries)
        lw, lh = text_size(label, a[:labelsize])
        rh = max(ph, lh)
        ew = pw + a[:patchlabelgap] + lw
        if a[:orientation] === :horizontal
            push!(rows, (x, y, rh))
            x += ew + (i < length(entries) ? a[:colgap] : 0.0)
            w = max(w, x)
            h = max(h, y + rh)
        else
            push!(rows, (x, y, rh))
            w = max(w, x + ew)
            y += rh + (i < length(entries) ? a[:rowgap] : 0.0)
            h = max(h, y)
        end
    end
    isempty(entries) && (h = y; w = pad[1])
    width = max(w, pad[1] + tw) + pad[2]
    height = h + pad[3]
    return LegendState(entries, (width, height), rows, th, NO_PROTRUSION)
end

function draw_element(ctx::Ctx, e::LineElement, x, y, w, h)
    a = e.attrs
    draw_polyline(ctx, [x, x + w], [y + h / 2, y + h / 2], to_color(a[:color]), a[:linewidth], a[:linestyle])
end
function draw_element(ctx::Ctx, e::MarkerElement, x, y, w, h)
    a = e.attrs
    draw_markers(ctx, [x + w / 2], [y + h / 2], a[:marker], a[:markersize], to_color(a[:color]), to_color(a[:strokecolor]), a[:strokewidth])
end
function draw_element(ctx::Ctx, e::PolyElement, x, y, w, h)
    a = e.attrs
    fill_polygon(ctx, [x, x + w, x + w, x], [y + 2, y + 2, y + h - 2, y + h - 2], to_color(a[:color]);
        strokecolor = to_color(a[:strokecolor]), strokewidth = Float64(a[:strokewidth]))
end

function draw_legend(ctx::Ctx, lg::Legend, st::LegendState, x0, y0)
    a = getfield(lg, :attrs)
    a[:visible] || return
    W, H = st.size
    new_path(ctx)
    rectangle(ctx, x0, y0, W, H)
    set_color(ctx, a[:backgroundcolor])
    if a[:framevisible]
        fill_preserve(ctx)
        set_stroke(ctx, a[:framecolor], a[:framewidth])
        stroke(ctx)
    else
        fillpath(ctx)
    end
    pad = a[:padding]
    if st.titleheight > 0
        draw_text(ctx, a[:title], x0 + W / 2, y0 + pad[4]; size = a[:titlesize], font = a[:titlefont], color = a[:titlecolor],
            halign = :center, valign = :top)
    end
    pw, ph = a[:patchsize]
    for ((label, elements), (x, y, rh)) in zip(st.entries, st.rows)
        py0 = y0 + y + (rh - ph) / 2
        for e in elements
            draw_element(ctx, e, x0 + x, py0, pw, ph)
        end
        draw_text(ctx, label, x0 + x + pw + a[:patchlabelgap], y0 + y + rh / 2; size = a[:labelsize], color = a[:labelcolor],
            halign = :left, valign = :center)
    end
end

draw_block(ctx::Ctx, lg::Legend, r::Rect, st::LegendState) = draw_legend(ctx, lg, st, r.x, r.y)

function draw_axislegend(ctx::Ctx, lg::Legend, r::Rect)
    st = prepare(lg)
    isempty(st.entries) && return
    a = getfield(lg, :attrs)
    pos = a[:position]
    s = string(pos)
    length(s) == 2 || throw(ArgumentError("axislegend position is :rt, :rb, :lt, :lb, :ct, :cb, :lc, :rc or :cc"))
    m = a[:margin]
    W, H = st.size
    h, v = s[1], s[2]
    x = h == 'l' ? r.x + m[1] : h == 'r' ? r.x + r.w - W - m[2] : r.x + (r.w - W) / 2
    y = v == 't' ? r.y + m[4] : v == 'b' ? r.y + r.h - H - m[3] : r.y + (r.h - H) / 2
    draw_legend(ctx, lg, st, x, y)
end
