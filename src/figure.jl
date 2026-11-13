# The figure model: a Figure owns a GridLayout; blocks (Axis, Axis3, Colorbar, Legend, Label)
# and nested GridLayouts sit in its cells. `fig[i, j]` is a GridPosition, as in Makie.

abstract type Block end
abstract type AbstractAxis <: Block end
abstract type AbstractPlot end

"""A read/write handle on one attribute: `ax.title[]` reads it, `ax.title[] = "…"` sets it."""
struct AttrView
    dict::Dict{Symbol, Any}
    key::Symbol
end
Base.getindex(a::AttrView) = a.dict[a.key]
Base.setindex!(a::AttrView, value) = (a.dict[a.key] = value)
Base.show(io::IO, a::AttrView) = print(io, "Attribute(:", a.key, " = ", repr(a.dict[a.key]), ")")

# ---------------------------------------------------------------------------------------------
# Sizes and aspects

"""A column/row size in units."""
struct Fixed
    x::Float64
end
"""A column/row size as a fraction of the figure's free space."""
struct Relative
    x::Float64
end
"""A column/row that shares the free space (weighted by `ratio`) or fits its content."""
struct Auto
    ratio::Float64
    trydetermine::Bool
end
Auto(ratio::Real = 1.0) = Auto(Float64(ratio), true)
Auto(trydetermine::Bool, ratio::Real = 1.0) = Auto(Float64(ratio), trydetermine)

"""`aspect = DataAspect()`: one unit in x is as long as one unit in y."""
struct DataAspect end
"""`aspect = AxisAspect(r)`: the plot area is `r` times as wide as it is high."""
struct AxisAspect
    ratio::Float64
end

# ---------------------------------------------------------------------------------------------
# Grid layouts

mutable struct GridContent
    item::Any
    rows::UnitRange{Int}
    cols::UnitRange{Int}
end

"""
    GridLayout(; colgap, rowgap)
    GridLayout(fig[i, j])

A grid of blocks. Every Figure has one (`fig.layout`); a nested GridLayout fills one cell.
"""
mutable struct GridLayout
    parent::Any
    content::Vector{GridContent}
    nrows::Int
    ncols::Int
    colsizes::Dict{Int, Any}
    rowsizes::Dict{Int, Any}
    colgaps::Dict{Int, Float64}
    rowgaps::Dict{Int, Float64}
    colgap::Union{Nothing, Float64}
    rowgap::Union{Nothing, Float64}
    halign::Symbol
    valign::Symbol
end

function GridLayout(; colgap = nothing, rowgap = nothing, halign = :center, valign = :center)
    return GridLayout(nothing, GridContent[], 0, 0, Dict{Int, Any}(), Dict{Int, Any}(), Dict{Int, Float64}(),
        Dict{Int, Float64}(), colgap === nothing ? nothing : Float64(colgap),
        rowgap === nothing ? nothing : Float64(rowgap), halign, valign)
end

"""`fig[i, j]`: a cell (or span) of a layout, where a block or a nested layout goes."""
struct GridPosition
    layout::GridLayout
    rows::UnitRange{Int}
    cols::UnitRange{Int}
end

_span(i::Integer, n) = Int(i):Int(i)
_span(r::AbstractUnitRange{<:Integer}, n) = Int(first(r)):Int(last(r))
# `:` spans every row/column the layout has when it is drawn (1:0 marks "all").
_span(::Colon, n) = 1:0
_resolve(r::UnitRange{Int}, n::Int) = isempty(r) ? (1:max(n, 1)) : r

Base.getindex(g::GridLayout, rows, cols) = GridPosition(g, _span(rows, g.nrows), _span(cols, g.ncols))
Base.getindex(gp::GridPosition, rows, cols) = _sublayout!(gp)[rows, cols]
Base.show(io::IO, gp::GridPosition) = print(io, "GridPosition(", gp.rows, ", ", gp.cols, ")")

function Base.setindex!(g::GridLayout, item, rows, cols)
    place!(g[rows, cols], item)
    return item
end

function GridLayout(gp::GridPosition; kwargs...)
    g = GridLayout(; kwargs...)
    place!(gp, g)
    return g
end

function _sublayout!(gp::GridPosition)
    for c in gp.layout.content
        c.item isa GridLayout && c.rows == gp.rows && c.cols == gp.cols && return c.item
    end
    return GridLayout(gp)
end

"""Put `item` at `gp`. A row or column index below 1 shifts the existing content down/right."""
function place!(gp::GridPosition, item)
    g = gp.layout
    rows, cols = gp.rows, gp.cols
    if first(rows) < 1
        shift = 1 - first(rows)
        for c in g.content
            c.rows = c.rows .+ shift
        end
        g.rowsizes = Dict(k + shift => v for (k, v) in g.rowsizes)
        g.nrows += shift
        rows = rows .+ shift
    end
    if first(cols) < 1
        shift = 1 - first(cols)
        for c in g.content
            c.cols = c.cols .+ shift
        end
        g.colsizes = Dict(k + shift => v for (k, v) in g.colsizes)
        g.ncols += shift
        cols = cols .+ shift
    end
    filter!(c -> c.item !== item, g.content)
    push!(g.content, GridContent(item, rows, cols))
    g.nrows = max(g.nrows, isempty(rows) ? 1 : last(rows))
    g.ncols = max(g.ncols, isempty(cols) ? 1 : last(cols))
    item isa GridLayout && (item.parent = g)
    return item
end

_layout(g::GridLayout) = g
figure_of(g::GridLayout) = g.parent isa GridLayout ? figure_of(g.parent) : g.parent
figure_of(gp::GridPosition) = figure_of(gp.layout)

"""`colsize!(layout, i, size)`: `Fixed(px)`, `Relative(fraction)`, `Auto()` or a number (Fixed)."""
colsize!(g, i::Integer, s) = (_layout(g).colsizes[i] = s isa Real ? Fixed(s) : s; nothing)
"""`rowsize!(layout, i, size)`: as `colsize!`."""
rowsize!(g, i::Integer, s) = (_layout(g).rowsizes[i] = s isa Real ? Fixed(s) : s; nothing)
"""`colgap!(layout, gap)` for all gaps, or `colgap!(layout, i, gap)` after column `i`."""
colgap!(g, gap::Real) = (_layout(g).colgap = Float64(gap); nothing)
colgap!(g, i::Integer, gap::Real) = (_layout(g).colgaps[i] = Float64(gap); nothing)
"""`rowgap!(layout, gap)` or `rowgap!(layout, i, gap)`."""
rowgap!(g, gap::Real) = (_layout(g).rowgap = Float64(gap); nothing)
rowgap!(g, i::Integer, gap::Real) = (_layout(g).rowgaps[i] = Float64(gap); nothing)

# ---------------------------------------------------------------------------------------------
# Figure

const FIGURE_SERIAL = Ref(0)
const CURRENT_FIGURE = Ref{Any}(nothing)

"""
    Figure(; size = (600, 450), backgroundcolor, figure_padding, fontsize, title, …)

A figure: a background, a padding and a `GridLayout` (`fig.layout`). Place blocks with
`Axis(fig[1, 1])`, `Colorbar(fig[1, 2], plot)`, `Label(fig[0, :], "Title")`. Theme keys
(`fontsize`, `textcolor`, `colormap`, `Axis = (…)`, …) given here apply to this figure only.
"""
mutable struct Figure
    size::Tuple{Float64, Float64}
    backgroundcolor::RGBAf
    padding::NTuple{4, Float64}
    layout::GridLayout
    content::Vector{Any}
    current_axis::Any
    theme::Theme
    attributes::Dict{Symbol, Any}
    serial::Int
end

const THEME_KEYS = Set([:fontsize, :textcolor, :backgroundcolor, :size, :figure_padding, :rowgap, :colgap,
    :colormap, :linewidth, :markersize, :palette, :font, :Axis, :Axis3, :Colorbar, :Legend, :Label])

function _padding(p)
    p isa Real && return (Float64(p), Float64(p), Float64(p), Float64(p))
    length(p) == 4 || throw(ArgumentError("figure_padding is a number or (left, right, bottom, top)"))
    return (Float64(p[1]), Float64(p[2]), Float64(p[3]), Float64(p[4]))
end

function Figure(; size = nothing, resolution = nothing, title = nothing, kwargs...)
    for k in keys(kwargs)
        (k in THEME_KEYS || k in PLOT_SECTIONS) || throw(ArgumentError("Figure has no attribute :$k"))
    end
    theme = isempty(kwargs) ? CURRENT_THEME[] : merge(CURRENT_THEME[], Theme(; kwargs...))
    sz = something(size, resolution, theme[:size])
    layout = GridLayout()
    attributes = Dict{Symbol, Any}(:title => title)
    fig = Figure((Float64(sz[1]), Float64(sz[2])), to_color(theme[:backgroundcolor]), _padding(theme[:figure_padding]),
        layout, Any[], nothing, theme, attributes, (FIGURE_SERIAL[] += 1))
    layout.parent = fig
    CURRENT_FIGURE[] = fig
    return fig
end

Base.getindex(fig::Figure, rows, cols) = fig.layout[rows, cols]
Base.setindex!(fig::Figure, item, rows, cols) = (fig.layout[rows, cols] = item)
_layout(fig::Figure) = fig.layout
figure_of(fig::Figure) = fig

"""`resize!(fig, width, height)` sets the figure size in units (1 unit = 1 px in PNG at `px_per_unit = 1`)."""
Base.resize!(fig::Figure, w::Real, h::Real) = (fig.size = (Float64(w), Float64(h)); fig)
Base.resize!(fig::Figure, wh::Tuple) = resize!(fig, wh...)

"""`figure_title!(fig, text)` sets the title `title(fig)` reports (and history entries show)."""
figure_title!(fig::Figure, text) = (fig.attributes[:title] = text; fig)

"""The figure most recently created or drawn into, or `nothing`."""
current_figure() = CURRENT_FIGURE[]

"""The axis most recently created or drawn into (of `fig`, default the current figure)."""
current_axis(fig = current_figure()) = fig === nothing ? nothing : fig.current_axis

axes_of(fig::Figure) = [b for b in fig.content if b isa AbstractAxis]

# ---------------------------------------------------------------------------------------------
# Block attributes

function block_attributes(fig::Figure, section::Symbol, defaults::Dict{Symbol, Any}, kwargs; aliases = Dict{Symbol, Symbol}())
    attrs = defaults
    for (k, v) in theme_section(fig.theme, section)
        haskey(attrs, k) && (attrs[k] = v)
    end
    for (k, v) in pairs(kwargs)
        k = get(aliases, k, k)
        haskey(attrs, k) || throw(ArgumentError("$section has no attribute :$k. Valid: $(join(sort!(string.(collect(keys(attrs)))), ", "))"))
        attrs[k] = v
    end
    return attrs
end

const BLOCK_FIELDS = Dict{DataType, Tuple}()

function Base.getproperty(b::Block, s::Symbol)
    hasfield(typeof(b), s) && return getfield(b, s)
    d = getfield(b, :attrs)
    haskey(d, s) && return AttrView(d, s)
    throw(ArgumentError("$(nameof(typeof(b))) has no attribute :$s"))
end

function Base.setproperty!(b::Block, s::Symbol, v)
    hasfield(typeof(b), s) && return setfield!(b, s, convert(fieldtype(typeof(b), s), v))
    d = getfield(b, :attrs)
    haskey(d, s) || throw(ArgumentError("$(nameof(typeof(b))) has no attribute :$s"))
    d[s] = v
    return v
end

Base.propertynames(b::Block) = (fieldnames(typeof(b))..., keys(getfield(b, :attrs))...)

attr(b, k::Symbol) = getfield(b, :attrs)[k]

function _register!(fig::Figure, b)
    push!(fig.content, b)
    b isa AbstractAxis && (fig.current_axis = b)
    CURRENT_FIGURE[] = fig
    return b
end

# ---------------------------------------------------------------------------------------------
# Axis

function axis_defaults(t::Theme)
    fs = theme_value(t, :Axis, :fontsize, 14)
    tc = theme_value(t, :Axis, :textcolor, :black)
    d = Dict{Symbol, Any}(
        :title => "", :subtitle => "", :titlesize => fs, :subtitlesize => fs, :titlefont => :bold,
        :subtitlefont => :regular, :titlecolor => tc, :subtitlecolor => tc, :titlealign => :center,
        :titlegap => 4.0, :subtitlegap => 2.0, :titlevisible => true, :subtitlevisible => true,
        :limits => (nothing, nothing), :xscale => identity, :yscale => identity,
        :xreversed => false, :yreversed => false, :aspect => nothing,
        :xautolimitmargin => (0.05, 0.05), :yautolimitmargin => (0.05, 0.05),
        :backgroundcolor => :white, :yaxisposition => :left, :xaxisposition => :bottom,
        :spinewidth => 1.0, :spinecolor => tc,
        :leftspinevisible => true, :rightspinevisible => true, :topspinevisible => true, :bottomspinevisible => true,
        :width => nothing, :height => nothing, :halign => :center, :valign => :center,
        :tellwidth => true, :tellheight => true,
    )
    for a in (:x, :y)
        s(n) = Symbol(a, n)
        d[s(:label)] = ""
        d[s(:labelsize)] = fs
        d[s(:labelcolor)] = tc
        d[s(:labelfont)] = :regular
        d[s(:labelpadding)] = a === :x ? 3.0 : 5.0
        d[s(:labelvisible)] = true
        d[s(:ticks)] = :automatic
        d[s(:tickformat)] = :automatic
        d[s(:ticklabelsize)] = fs
        d[s(:ticklabelcolor)] = tc
        d[s(:ticklabelpad)] = a === :x ? 2.0 : 4.0
        d[s(:ticklabelsvisible)] = true
        d[s(:ticklabelrotation)] = 0.0
        d[s(:ticksize)] = 5.0
        d[s(:tickwidth)] = 1.0
        d[s(:tickcolor)] = tc
        d[s(:ticksvisible)] = true
        d[s(:tickalign)] = 0.0
        d[s(:gridvisible)] = true
        d[s(:gridcolor)] = RGBAf(0, 0, 0, 0.12)
        d[s(:gridwidth)] = 1.0
        d[s(:gridstyle)] = nothing
        d[s(:minorticksvisible)] = false
        d[s(:minorgridvisible)] = false
        d[s(:minorticks)] = 5
        d[s(:minorgridcolor)] = RGBAf(0, 0, 0, 0.05)
        d[s(:minorticksize)] = 3.0
    end
    return d
end

"""
    Axis(fig[i, j]; title, xlabel, ylabel, xscale, yscale, limits, xticks, …)

A 2D axis. Scales: `identity`, `log10`, `log2`, `log`, `sqrt`. `limits = (x1, x2, y1, y2)`
(any part `nothing` for automatic); `xreversed`/`yreversed`; `aspect = DataAspect()`.
Ticks: a vector, `(values, labels)`, `WilkinsonTicks(n)`, `LinearTicks(n)`; `xtickformat`
is a function of the values or a `"{:.2f}"` string.
"""
mutable struct Axis <: AbstractAxis
    figure::Figure
    attrs::Dict{Symbol, Any}
    plots::Vector{AbstractPlot}
    cycle::Dict{Symbol, Int}
    xgroup::Vector{Any}
    ygroup::Vector{Any}
    legends::Vector{Any}
end

function Axis(fig::Figure; kwargs...)
    attrs = block_attributes(fig, :Axis, axis_defaults(fig.theme), kwargs)
    attrs[:limits] = _limits2(attrs[:limits])
    ax = Axis(fig, attrs, AbstractPlot[], Dict{Symbol, Int}(), Any[], Any[], Any[])
    push!(ax.xgroup, ax)
    push!(ax.ygroup, ax)
    return _register!(fig, ax)
end
Axis(gp::GridPosition; kwargs...) = place!(gp, Axis(figure_of(gp); kwargs...))

function _limits2(l)
    l === nothing && return (nothing, nothing)
    if l isa Tuple && length(l) == 4
        return ((l[1], l[2]), (l[3], l[4]))
    elseif l isa Tuple && length(l) == 2
        return (l[1], l[2])
    end
    throw(ArgumentError("limits are (x1, x2, y1, y2) or ((x1, x2), (y1, y2)); use nothing for automatic"))
end

function _limits3(l)
    l === nothing && return (nothing, nothing, nothing)
    if l isa Tuple && length(l) == 6
        return ((l[1], l[2]), (l[3], l[4]), (l[5], l[6]))
    elseif l isa Tuple && length(l) == 3
        return l
    end
    throw(ArgumentError("Axis3 limits are (x1, x2, y1, y2, z1, z2) or (xlims, ylims, zlims)"))
end

Base.show(io::IO, ax::Axis) = print(io, "Axis(", length(ax.plots), " plots, title = ", repr(plaintext(attr(ax, :title))), ")")

# ---------------------------------------------------------------------------------------------
# Axis3

function axis3_defaults(t::Theme)
    fs = theme_value(t, :Axis3, :fontsize, 14)
    tc = theme_value(t, :Axis3, :textcolor, :black)
    d = Dict{Symbol, Any}(
        :title => "", :titlesize => fs, :titlefont => :bold, :titlecolor => tc, :titlegap => 4.0,
        :titlevisible => true, :titlealign => :center,
        :azimuth => 1.275π, :elevation => π / 8, :perspectiveness => 0.0, :aspect => (1.0, 1.0, 2 / 3),
        :limits => (nothing, nothing, nothing), :viewmode => :fit, :backgroundcolor => :transparent,
        :spinewidth => 1.0, :spinecolor => tc, :protrusions => 30.0,
        :width => nothing, :height => nothing, :halign => :center, :valign => :center,
        :tellwidth => true, :tellheight => true,
        :xypanelcolor => :transparent, :yzpanelcolor => :transparent, :xzpanelcolor => :transparent,
        :xypanelvisible => true, :yzpanelvisible => true, :xzpanelvisible => true,
    )
    for a in (:x, :y, :z)
        s(n) = Symbol(a, n)
        d[s(:label)] = string(a)
        d[s(:labelsize)] = fs
        d[s(:labelcolor)] = tc
        d[s(:labelfont)] = :regular
        d[s(:labelvisible)] = true
        d[s(:labeloffset)] = a === :z ? 46.0 : 36.0
        d[s(:ticks)] = :automatic
        d[s(:tickformat)] = :automatic
        d[s(:ticklabelsize)] = fs
        d[s(:ticklabelcolor)] = tc
        d[s(:ticklabelpad)] = 5.0
        d[s(:ticklabelsvisible)] = true
        d[s(:ticksize)] = 6.0
        d[s(:tickwidth)] = 1.0
        d[s(:tickcolor)] = tc
        d[s(:ticksvisible)] = true
        d[s(:gridvisible)] = true
        d[s(:gridcolor)] = RGBAf(0, 0, 0, 0.12)
        d[s(:gridwidth)] = 1.0
        d[s(:spinesvisible)] = true
        d[s(:autolimitmargin)] = (0.05, 0.05)
        d[s(:reversed)] = false
    end
    return d
end

"""
    Axis3(fig[i, j]; title, xlabel, ylabel, zlabel, azimuth, elevation, aspect, limits, …)

A 3D axis with an orthographic camera. `azimuth`/`elevation` are in radians (Makie's defaults:
1.275π and π/8); `aspect` is `(ax, ay, az)`, `:data` or `:equal`.
"""
mutable struct Axis3 <: AbstractAxis
    figure::Figure
    attrs::Dict{Symbol, Any}
    plots::Vector{AbstractPlot}
    cycle::Dict{Symbol, Int}
    legends::Vector{Any}
end

function Axis3(fig::Figure; kwargs...)
    attrs = block_attributes(fig, :Axis3, axis3_defaults(fig.theme), kwargs)
    attrs[:limits] = _limits3(attrs[:limits])
    return _register!(fig, Axis3(fig, attrs, AbstractPlot[], Dict{Symbol, Int}(), Any[]))
end
Axis3(gp::GridPosition; kwargs...) = place!(gp, Axis3(figure_of(gp); kwargs...))

Base.show(io::IO, ax::Axis3) = print(io, "Axis3(", length(ax.plots), " plots, title = ", repr(plaintext(attr(ax, :title))), ")")

# ---------------------------------------------------------------------------------------------
# Colorbar, Label

function colorbar_defaults(t::Theme)
    fs = theme_value(t, :Colorbar, :fontsize, 14)
    tc = theme_value(t, :Colorbar, :textcolor, :black)
    return Dict{Symbol, Any}(
        :label => "", :labelsize => fs, :labelcolor => tc, :labelfont => :regular, :labelpadding => 5.0,
        :labelvisible => true, :ticks => :automatic, :tickformat => :automatic, :ticklabelsize => fs,
        :ticklabelcolor => tc, :ticklabelpad => 3.0, :ticksize => 5.0, :tickwidth => 1.0, :tickcolor => tc,
        :ticksvisible => true, :ticklabelsvisible => true, :colormap => theme_value(t, :Colorbar, :colormap, :viridis),
        :limits => nothing, :size => 12.0, :vertical => true, :flipaxis => true, :spinewidth => 1.0,
        :spinecolor => tc, :scale => identity, :width => nothing, :height => nothing, :halign => :center,
        :valign => :center, :tellwidth => true, :tellheight => true, :levels => nothing,
    )
end

"""
    Colorbar(fig[i, j], plot; label, …)
    Colorbar(fig[i, j]; colormap = :viridis, limits = (0, 1), label, …)

A colour bar for a plot's colour map and range (heatmap, surface, contourf, coloured scatter, …).
"""
mutable struct Colorbar <: Block
    figure::Figure
    attrs::Dict{Symbol, Any}
    plot::Any
end

function Colorbar(fig::Figure, plot = nothing; kwargs...)
    attrs = block_attributes(fig, :Colorbar, colorbar_defaults(fig.theme), kwargs; aliases = Dict(:colorrange => :limits))
    return _register!(fig, Colorbar(fig, attrs, plot))
end
Colorbar(gp::GridPosition, plot = nothing; kwargs...) = place!(gp, Colorbar(figure_of(gp), plot; kwargs...))

function label_defaults(t::Theme)
    return Dict{Symbol, Any}(
        :text => "", :fontsize => theme_value(t, :Label, :fontsize, 14), :font => :regular,
        :color => theme_value(t, :Label, :textcolor, :black), :rotation => 0.0, :padding => (0.0, 0.0, 0.0, 0.0),
        :halign => :center, :valign => :center, :tellwidth => true, :tellheight => true, :visible => true,
        :width => nothing, :height => nothing,
    )
end

"""
    Label(fig[i, j], text; fontsize, font = :regular | :bold, color, rotation, …)

A text block, such as a figure title: `Label(fig[0, :], "Title"; fontsize = 20, font = :bold)`.
"""
mutable struct Label <: Block
    figure::Figure
    attrs::Dict{Symbol, Any}
end

function Label(fig::Figure, text = nothing; kwargs...)
    attrs = block_attributes(fig, :Label, label_defaults(fig.theme), kwargs)
    text === nothing || (attrs[:text] = text)
    return _register!(fig, Label(fig, attrs))
end
Label(gp::GridPosition, text = nothing; kwargs...) = place!(gp, Label(figure_of(gp), text; kwargs...))

# ---------------------------------------------------------------------------------------------
# Axis helpers

_ax(ax) = ax === nothing ? throw(ArgumentError("there is no current axis; make one with Axis(fig[1, 1])")) : ax

function _set_limits!(ax::Axis, which::Int, lohi)
    l = Any[attr(ax, :limits)...]
    l[which] = lohi
    ax.attrs[:limits] = (l[1], l[2])
    return ax
end

function _set_limits!(ax::Axis3, which::Int, lohi)
    l = Any[attr(ax, :limits)...]
    l[which] = lohi
    ax.attrs[:limits] = (l[1], l[2], l[3])
    return ax
end

"""`xlims!(ax, lo, hi)`: fix the x limits (`nothing` keeps a side automatic; `lo > hi` reverses)."""
xlims!(ax::AbstractAxis, lo, hi) = _set_limits!(ax, 1, (lo, hi))
xlims!(ax::AbstractAxis, lohi::Tuple) = xlims!(ax, lohi...)
xlims!(args...) = xlims!(_ax(current_axis()), args...)
"""`ylims!(ax, lo, hi)`: as `xlims!`."""
ylims!(ax::AbstractAxis, lo, hi) = _set_limits!(ax, 2, (lo, hi))
ylims!(ax::AbstractAxis, lohi::Tuple) = ylims!(ax, lohi...)
ylims!(args...) = ylims!(_ax(current_axis()), args...)
"""`zlims!(ax3, lo, hi)`."""
zlims!(ax::Axis3, lo, hi) = _set_limits!(ax, 3, (lo, hi))
zlims!(ax::Axis3, lohi::Tuple) = zlims!(ax, lohi...)

"""`limits!(ax, x1, x2, y1, y2)` (or six values for an Axis3)."""
limits!(ax::Axis, x1, x2, y1, y2) = (ax.attrs[:limits] = ((x1, x2), (y1, y2)); ax)
limits!(ax::Axis, xl::Tuple, yl::Tuple) = limits!(ax, xl..., yl...)
limits!(ax::Axis3, x1, x2, y1, y2, z1, z2) = (ax.attrs[:limits] = ((x1, x2), (y1, y2), (z1, z2)); ax)

"""`autolimits!(ax)`: back to limits from the data."""
autolimits!(ax::Axis) = (ax.attrs[:limits] = (nothing, nothing); ax)
autolimits!(ax::Axis3) = (ax.attrs[:limits] = (nothing, nothing, nothing); ax)
autolimits!() = autolimits!(_ax(current_axis()))
"""`reset_limits!(ax)`: a no-op kept for Makie scripts; limits are computed when drawing."""
reset_limits!(ax::AbstractAxis) = ax

function _hide!(ax::Axis, a::Symbol; label = true, ticklabels = true, ticks = true, grid = true, minorgrid = true, minorticks = true)
    s(n) = Symbol(a, n)
    label && (ax.attrs[s(:labelvisible)] = false)
    ticklabels && (ax.attrs[s(:ticklabelsvisible)] = false)
    ticks && (ax.attrs[s(:ticksvisible)] = false)
    grid && (ax.attrs[s(:gridvisible)] = false)
    minorgrid && (ax.attrs[s(:minorgridvisible)] = false)
    minorticks && (ax.attrs[s(:minorticksvisible)] = false)
    return ax
end

"""`hidexdecorations!(ax; label, ticklabels, ticks, grid, minorgrid, minorticks)` (all `true`)."""
hidexdecorations!(ax::Axis; kwargs...) = _hide!(ax, :x; kwargs...)
"""`hideydecorations!(ax; …)`: as `hidexdecorations!`."""
hideydecorations!(ax::Axis; kwargs...) = _hide!(ax, :y; kwargs...)
"""`hidedecorations!(ax; …)`: both axes."""
hidedecorations!(ax::Axis; kwargs...) = (_hide!(ax, :x; kwargs...); _hide!(ax, :y; kwargs...))
function hidedecorations!(ax::Axis3; label = true, ticklabels = true, ticks = true, grid = true, kwargs...)
    for a in (:x, :y, :z)
        label && (ax.attrs[Symbol(a, :labelvisible)] = false)
        ticklabels && (ax.attrs[Symbol(a, :ticklabelsvisible)] = false)
        ticks && (ax.attrs[Symbol(a, :ticksvisible)] = false)
        grid && (ax.attrs[Symbol(a, :gridvisible)] = false)
    end
    return ax
end

"""`hidespines!(ax, :l, :r, :t, :b)`; no sides hides all four."""
function hidespines!(ax::Axis, sides::Symbol...)
    names = Dict(:l => :leftspinevisible, :r => :rightspinevisible, :t => :topspinevisible, :b => :bottomspinevisible)
    for s in (isempty(sides) ? (:l, :r, :t, :b) : sides)
        ax.attrs[names[s]] = false
    end
    return ax
end
function hidespines!(ax::Axis3)
    for a in (:x, :y, :z)
        ax.attrs[Symbol(a, :spinesvisible)] = false
    end
    return ax
end

function _link!(field::Symbol, axes)
    group = Any[]
    for ax in axes
        for other in getfield(ax, field)
            any(g -> g === other, group) || push!(group, other)
        end
    end
    for ax in group
        setfield!(ax, field, group)
    end
    return nothing
end

"""`linkxaxes!(a, b, …)`: the axes share x limits (the union of their data)."""
linkxaxes!(a::Axis, others::Axis...) = _link!(:xgroup, (a, others...))
"""`linkyaxes!(a, b, …)`: the axes share y limits."""
linkyaxes!(a::Axis, others::Axis...) = _link!(:ygroup, (a, others...))
"""`linkaxes!(a, b, …)`: share both."""
linkaxes!(a::Axis, others::Axis...) = (linkxaxes!(a, others...); linkyaxes!(a, others...))
linkxaxes!(axes::AbstractVector) = linkxaxes!(axes...)
linkyaxes!(axes::AbstractVector) = linkyaxes!(axes...)
linkaxes!(axes::AbstractVector) = linkaxes!(axes...)

function _position_of(layout::GridLayout, item)
    for c in layout.content
        c.item === item && return GridPosition(layout, c.rows, c.cols)
        if c.item isa GridLayout
            p = _position_of(c.item, item)
            p === nothing || return p
        end
    end
    return nothing
end

"""
    twinx(ax; kwargs...)

A second y axis on the right of `ax`, sharing its x limits and colour cycle. Plot into the
returned axis for a second scale.
"""
function twinx(ax::Axis; kwargs...)
    gp = _position_of(ax.figure.layout, ax)
    gp === nothing && throw(ArgumentError("twinx needs an axis placed in the figure's layout"))
    twin = Axis(gp; yaxisposition = :right, backgroundcolor = :transparent, xgridvisible = false,
        ygridvisible = false, leftspinevisible = false, topspinevisible = false, bottomspinevisible = false, kwargs...)
    hidexdecorations!(twin)
    linkxaxes!(ax, twin)
    twin.cycle = ax.cycle
    ax.figure.current_axis = ax
    return twin
end
