# Composite plots ("recipes"): geometry built from the primitives the renderer draws (lines,
# segments, markers, polygons). `stairs` and `stem` follow Makie.jl's recipes (MIT, © 2018-2025
# Simon Danisch, Julius Krumbiegel and contributors): the same step modes, offset and trunk.

"""Makie's stair points: `:pre`, `:post` or `:center` steps."""
function stair_points(x::Vector{Float64}, y::Vector{Float64}, step::Symbol)
    n = length(x)
    n == 0 && return Float64[], Float64[]
    if step === :pre
        xs, ys = Vector{Float64}(undef, 2n - 1), Vector{Float64}(undef, 2n - 1)
        xs[1], ys[1] = x[1], y[1]
        for i in 1:(n - 1)
            xs[2i], ys[2i] = x[i], y[i + 1]
            xs[2i + 1], ys[2i + 1] = x[i + 1], y[i + 1]
        end
        return xs, ys
    elseif step === :post
        xs, ys = Vector{Float64}(undef, 2n - 1), Vector{Float64}(undef, 2n - 1)
        xs[1], ys[1] = x[1], y[1]
        for i in 1:(n - 1)
            xs[2i], ys[2i] = x[i + 1], y[i]
            xs[2i + 1], ys[2i + 1] = x[i + 1], y[i + 1]
        end
        return xs, ys
    elseif step === :center
        xs, ys = Vector{Float64}(undef, 2n), Vector{Float64}(undef, 2n)
        xs[1], ys[1] = x[1], y[1]
        for i in 1:(n - 1)
            half = (x[i] + x[i + 1]) / 2
            xs[2i], ys[2i] = half, y[i]
            xs[2i + 1], ys[2i + 1] = half, y[i + 1]
        end
        xs[end], ys[end] = x[end], y[end]
        return xs, ys
    end
    throw(ArgumentError("invalid step :$step; use :pre, :post or :center"))
end

"""The default bar width: the smallest gap between neighbouring x values (1 for a single bar)."""
function bar_width(x::Vector{Float64})
    xs = sort(unique(filter(isfinite, x)))
    length(xs) < 2 && return 1.0
    return minimum(diff(xs))
end

"""Bars as `(x0, x1, y0, y1)` rectangles in data space."""
function bar_rects(x, y, width, gap, fillto, direction)
    w = (width === :automatic ? bar_width(x) : Float64(width)) * (1 - gap)
    base(i) = fillto isa AbstractVector ? Float64(fillto[i]) : Float64(fillto)
    rects = NTuple{4, Float64}[]
    for i in eachindex(x)
        if direction === :y
            push!(rects, (x[i] - w / 2, x[i] + w / 2, base(i), y[i]))
        else
            push!(rects, (base(i), y[i], x[i] - w / 2, x[i] + w / 2))
        end
    end
    return rects
end

"""Histogram bins: `(centres, heights, width)` for `bins` (a count or edges) and `normalization`."""
function hist_bars(values::Vector{Float64}, bins, normalization::Symbol)
    if isempty(values)
        return Float64[], Float64[], 1.0
    end
    edges = if bins isa Integer
        lo, hi = extrema(values)
        lo == hi && (lo -= 0.5; hi += 0.5)
        collect(range(lo, hi; length = bins + 1))
    else
        sort!(_vec(bins))
    end
    counts = zeros(length(edges) - 1)
    for v in values
        (v < edges[1] || v > edges[end]) && continue
        i = v == edges[end] ? length(counts) : searchsortedlast(edges, v)
        1 <= i <= length(counts) && (counts[i] += 1)
    end
    widths = diff(edges)
    total = sum(counts)
    if normalization === :pdf
        counts = counts ./ (total .* widths)
    elseif normalization === :probability
        counts = counts ./ total
    elseif normalization === :density
        counts = counts ./ widths
    elseif normalization !== :none
        throw(ArgumentError("normalization is :none, :pdf, :probability or :density"))
    end
    centres = [(edges[i] + edges[i + 1]) / 2 for i in 1:(length(edges) - 1)]
    return centres, counts, widths
end

"""Colours for each series of `series`/`multiline`: the palette, a colormap name, or explicit colours."""
function series_colors(color, n::Int)
    if color isa Tuple && length(color) == 2 && color[2] isa Integer
        palette, offset = color
        return [to_color(palette[mod1(offset + i, length(palette))]) for i in 1:n]
    elseif color isa Symbol && (haskey(COLORMAP_DATA, color) || haskey(COLORMAP_ALIASES, color))
        cmap = to_colormap(color)
        return [sample(cmap, n == 1 ? 0.5 : (i - 1) / (n - 1)) for i in 1:n]
    elseif color isa AbstractVector
        return [to_color(color[mod1(i, length(color))]) for i in 1:n]
    end
    return fill(to_color(color), n)
end

# ---------------------------------------------------------------------------------------------
# Annotations: a label in data space with an arrow to a point.

"""
    annotation!(ax, xlabel, ylabel, x, y; text, color, fontsize, linewidth, arrowsize)

Write `text` at `(xlabel, ylabel)` and draw an arrow from it to the point `(x, y)` (all in data
coordinates).
"""
function annotation!(ax::Axis, xt::Real, yt::Real, x::Real, y::Real; text = "", color = nothing,
        fontsize = nothing, linewidth = 1.0, arrowsize = 8.0, label = nothing)
    fs = something(fontsize, theme_value(ax.figure.theme, :Text, :fontsize, 14))
    c = something(color, theme_value(ax.figure.theme, :Text, :textcolor, :black))
    p = Plot{:annotation}(Any[xt, yt, x, y], Dict{Symbol, Any}(:text => text, :color => c, :fontsize => fs,
        :linewidth => linewidth, :arrowsize => arrowsize, :label => label, :visible => true, :alpha => 1.0), ax)
    push!(ax.plots, p)
    return p
end
annotation!(args...; kwargs...) = annotation!(_ax(current_axis()), args...; kwargs...)
converted(p::Plot{:annotation}) = (xt = Float64(p.input[1]), yt = Float64(p.input[2]), x = Float64(p.input[3]), y = Float64(p.input[4]))

# ---------------------------------------------------------------------------------------------
# Docstrings for the generated plot functions

const PLOT_DOCS = Dict(
    :lines => "lines(x, y; color, linewidth, linestyle, label) — a polyline; `lines(x, y, z)` in an Axis3. `color` may be a vector of numbers (mapped through `colormap`).",
    :scatter => "scatter(x, y; color, marker, markersize, strokecolor, strokewidth, label) — markers. Markers: :circle, :rect, :diamond, :utriangle, :dtriangle, :ltriangle, :rtriangle, :cross, :xcross, :star5, :pentagon, :hexagon, :hline, :vline.",
    :scatterlines => "scatterlines(x, y; color, linewidth, marker, markersize, markercolor) — a line with markers at the points.",
    :linesegments => "linesegments(x, y) — disconnected segments between points 1–2, 3–4, ….",
    :stem => "stem(x, y; offset = 0, stemcolor, stemwidth, trunkcolor, marker, markersize) — stems from `offset` to each point, a trunk along the offset, and markers (Makie's recipe). `stem(x, y, z)` in an Axis3.",
    :stairs => "stairs(x, y; step = :pre | :post | :center) — a step function (Makie's recipe).",
    :barplot => "barplot(x, y; width, gap = 0.2, fillto = 0, direction = :y | :x, color, strokecolor, strokewidth) — bars.",
    :hist => "hist(values; bins = 15, normalization = :none | :pdf | :probability | :density) — a histogram.",
    :errorbars => "errorbars(x, y, err) or errorbars(x, y, low, high; whiskerwidth, direction = :y | :x) — error bars.",
    :band => "band(x, ylow, yhigh; color) — the filled region between two curves.",
    :area => "area(x, y; baseline = 0, fillalpha = 0.35) — a line with the region down to `baseline` filled (Squero).",
    :heatmap => "heatmap(x, y, z; colormap, colorrange, interpolate) — a cell grid; `z[i, j]` is at `(x[i], y[j])`; `x`/`y` are centres or edges.",
    :image => "image(x, y, img) or image(img) — a matrix of colours (or numbers through `colormap`); `img[i, j]` is at column i, row j from the bottom.",
    :contour => "contour(x, y, z; levels = 5, color, colormap, linewidth) — iso-lines; `levels` is a count or values.",
    :contourf => "contourf(x, y, z; levels = 10, colormap) — filled bands between levels.",
    :text => "text(x, y; text, fontsize, font, color, align = (:left, :bottom), rotation, offset) — text at points (data space); `text` may be a vector or `rich(…)`.",
    :hlines => "hlines(ys; xmin = 0, xmax = 1, color, linewidth, linestyle) — horizontal lines across the axis (xmin/xmax are fractions).",
    :vlines => "vlines(xs; ymin = 0, ymax = 1, …) — vertical lines across the axis.",
    :ablines => "ablines(intercepts, slopes) — lines y = a + b·x across the axis.",
    :poly => "poly(points; color, strokecolor, strokewidth) — a filled polygon.",
    :series => "series(x, Y; labels, color) — one line per row of `Y` (Makie's layout); colours from the palette or a colormap name.",
    :multiline => "multiline(x, Y; labels, color) — one line per column of `Y` (Squero), the natural layout for sampled data.",
    :surface => "surface(x, y, z; colormap, colorrange, color, shading = FastShading | NoShading, strokewidth) — a 3D surface (needs an Axis3); `z[i, j]` is at `(x[i], y[j])`; `x`, `y` may be matrices.",
    :mesh => "mesh(vertices, faces; color, colormap, shading) — triangles; `vertices` is n × 3 (or n × 2), `faces` m × 3; `color` one colour or one value per vertex.",
    :wireframe => "wireframe(x, y, z; color, linewidth) — the grid lines of a surface.",
)

for K in KINDS
    doc = PLOT_DOCS[K]
    f! = Symbol(K, :!)
    @eval begin
        @doc """
            $($(string(K)))(args...; figure = (;), axis = (;), kwargs...) -> (figure, axis, plot)
            $($(string(K)))(fig[i, j], args...; axis = (;), kwargs...) -> (axis, plot)

        $($doc)

        Makes a figure (or an axis at `fig[i, j]`); `$($(string(f!)))` adds to an existing axis.
        """ $K
        @doc """
            $($(string(f!)))(ax, args...; kwargs...) -> plot

        $($doc)

        Adds to `ax` (or to the current axis when `ax` is left out).
        """ $f!
    end
end
