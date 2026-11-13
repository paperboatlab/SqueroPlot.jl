# Plots: one `Plot{K}` type for every kind. The inputs stay as given (so `p[1][] = y` updates a
# plot) and are converted when the figure is drawn. Attributes are plain values; `p.color[]`
# reads one and `p.color[] = :red` sets it.

"""A plot in an axis. `K` is the kind (`:lines`, `:scatter`, `:surface`, …)."""
mutable struct Plot{K} <: AbstractPlot
    input::Vector{Any}
    attrs::Dict{Symbol, Any}
    axis::Any
end

kind(::Plot{K}) where {K} = K

function Base.getproperty(p::Plot, s::Symbol)
    hasfield(Plot, s) && return getfield(p, s)
    d = getfield(p, :attrs)
    haskey(d, s) && return AttrView(d, s)
    throw(ArgumentError("$(kind(p)) has no attribute :$s"))
end

function Base.setproperty!(p::Plot, s::Symbol, v)
    hasfield(Plot, s) && return setfield!(p, s, v)
    d = getfield(p, :attrs)
    haskey(d, s) || throw(ArgumentError("$(kind(p)) has no attribute :$s"))
    return d[s] = v
end

Base.propertynames(p::Plot) = (fieldnames(Plot)..., keys(getfield(p, :attrs))...)

"""`p[i]`: the plot's i-th input argument; `p[2][] = ys` replaces it."""
Base.getindex(p::Plot, i::Integer) = ArgView(getfield(p, :input), i)

struct ArgView
    input::Vector{Any}
    i::Int
end
Base.getindex(a::ArgView) = a.input[a.i]
Base.setindex!(a::ArgView, v) = (a.input[a.i] = v)

Base.show(io::IO, p::Plot{K}) where {K} = print(io, "Plot{:", K, "}(", length(getfield(p, :input)), " args)")

"""What a non-mutating plot call returns: destructure as `fig, ax, plt = lines(…)`."""
struct FigureAxisPlot
    figure::Figure
    axis::AbstractAxis
    plot::AbstractPlot
end
Base.iterate(f::FigureAxisPlot, i::Int = 1) = i > 3 ? nothing : (getfield(f, i), i + 1)
Base.length(::FigureAxisPlot) = 3

"""What `lines(fig[i, j], …)` returns: destructure as `ax, plt = …`."""
struct AxisPlot
    axis::AbstractAxis
    plot::AbstractPlot
end
Base.iterate(a::AxisPlot, i::Int = 1) = i > 2 ? nothing : (getfield(a, i), i + 1)
Base.length(::AxisPlot) = 2

const KINDS = (:lines, :scatter, :scatterlines, :linesegments, :stem, :stairs, :barplot, :hist,
    :errorbars, :band, :area, :heatmap, :image, :contour, :contourf, :text, :hlines, :vlines,
    :ablines, :poly, :series, :multiline, :surface, :mesh, :wireframe)

const SECTION = Dict(
    :lines => :Lines, :scatter => :Scatter, :scatterlines => :ScatterLines, :linesegments => :LineSegments,
    :stem => :Stem, :stairs => :Stairs, :barplot => :BarPlot, :hist => :Hist, :errorbars => :Errorbars,
    :band => :Band, :area => :Area, :heatmap => :Heatmap, :image => :Image, :contour => :Contour,
    :contourf => :Contourf, :text => :Text, :hlines => :HLines, :vlines => :VLines, :ablines => :ABLines,
    :poly => :Poly, :series => :Series, :multiline => :Multiline, :surface => :Surface, :mesh => :Mesh,
    :wireframe => :Wireframe,
)
const PLOT_SECTIONS = Set(values(SECTION))

"""`shading = NoShading`: surfaces and meshes show their colour map unlit."""
const NoShading = :none
"""`shading = FastShading` (the default): surfaces and meshes are lit from the viewer's upper left."""
const FastShading = :fast

# ---------------------------------------------------------------------------------------------
# Defaults

function plot_defaults(K::Symbol, t::Theme)
    lw = theme_value(t, SECTION[K], :linewidth, 1.5)
    ms = theme_value(t, SECTION[K], :markersize, 9)
    cmap = theme_value(t, SECTION[K], :colormap, :viridis)
    tc = theme_value(t, SECTION[K], :textcolor, :black)
    fs = theme_value(t, SECTION[K], :fontsize, 14)
    d = Dict{Symbol, Any}(:label => nothing, :visible => true, :alpha => 1.0)
    line = Dict{Symbol, Any}(:color => :cycle, :linewidth => lw, :linestyle => nothing, :colormap => cmap, :colorrange => :automatic)
    marker = Dict{Symbol, Any}(:marker => :circle, :markersize => ms, :strokecolor => :black, :strokewidth => 0.0)
    if K in (:lines, :linesegments, :stairs)
        merge!(d, line)
        K === :stairs && (d[:step] = :pre)
    elseif K === :scatter
        merge!(d, line, marker)
        delete!(d, :linewidth)
        delete!(d, :linestyle)
    elseif K === :scatterlines
        merge!(d, line, marker)
        d[:markercolor] = :inherit
    elseif K === :stem
        merge!(d, marker)
        merge!(d, Dict{Symbol, Any}(:color => :cycle, :stemcolor => :inherit, :stemwidth => lw, :stemlinestyle => nothing,
            :trunkcolor => :inherit, :trunkwidth => lw, :trunklinestyle => nothing, :offset => 0.0,
            :colormap => cmap, :colorrange => :automatic))
    elseif K in (:barplot, :hist)
        merge!(d, Dict{Symbol, Any}(:color => :cycle_patch, :strokecolor => :black, :strokewidth => 0.0,
            :width => :automatic, :gap => K === :hist ? 0.0 : 0.2, :fillto => 0.0, :direction => :y,
            :colormap => cmap, :colorrange => :automatic))
        K === :hist && merge!(d, Dict{Symbol, Any}(:bins => 15, :normalization => :none))
    elseif K === :errorbars
        merge!(d, Dict{Symbol, Any}(:color => :black, :linewidth => lw, :whiskerwidth => 0.0, :direction => :y))
    elseif K === :band
        merge!(d, Dict{Symbol, Any}(:color => :cycle_patch))
    elseif K === :area
        merge!(d, Dict{Symbol, Any}(:color => :cycle, :fillalpha => 0.35, :linewidth => lw, :linestyle => nothing, :baseline => 0.0))
    elseif K === :heatmap
        merge!(d, Dict{Symbol, Any}(:colormap => cmap, :colorrange => :automatic, :nan_color => :transparent, :interpolate => false))
    elseif K === :image
        merge!(d, Dict{Symbol, Any}(:colormap => :grays, :colorrange => :automatic, :interpolate => true))
    elseif K === :contour
        merge!(d, Dict{Symbol, Any}(:levels => 5, :color => nothing, :colormap => cmap, :colorrange => :automatic,
            :linewidth => 1.0, :linestyle => nothing))
    elseif K === :contourf
        merge!(d, Dict{Symbol, Any}(:levels => 10, :colormap => cmap))
    elseif K === :text
        merge!(d, Dict{Symbol, Any}(:text => "", :color => tc, :fontsize => fs, :font => :regular,
            :align => (:left, :bottom), :rotation => 0.0, :offset => (0.0, 0.0), :position => nothing))
    elseif K in (:hlines, :vlines, :ablines)
        merge!(d, Dict{Symbol, Any}(:color => :cycle, :linewidth => lw, :linestyle => nothing))
        K === :hlines && merge!(d, Dict{Symbol, Any}(:xmin => 0.0, :xmax => 1.0))
        K === :vlines && merge!(d, Dict{Symbol, Any}(:ymin => 0.0, :ymax => 1.0))
    elseif K === :poly
        merge!(d, Dict{Symbol, Any}(:color => :cycle_patch, :strokecolor => :black, :strokewidth => 0.0))
    elseif K in (:series, :multiline)
        merge!(d, Dict{Symbol, Any}(:color => :palette, :linewidth => lw, :linestyle => nothing, :labels => nothing,
            :marker => nothing, :markersize => ms))
    elseif K === :surface
        merge!(d, Dict{Symbol, Any}(:color => nothing, :colormap => cmap, :colorrange => :automatic,
            :shading => FastShading, :strokewidth => 0.0, :strokecolor => :black, :nan_color => :transparent))
    elseif K === :mesh
        merge!(d, Dict{Symbol, Any}(:color => :cycle, :colormap => cmap, :colorrange => :automatic,
            :shading => FastShading, :strokewidth => 0.0, :strokecolor => :black))
    elseif K === :wireframe
        merge!(d, Dict{Symbol, Any}(:color => :black, :linewidth => 1.0, :linestyle => nothing))
    end
    return d
end

const PLOT_ALIASES = Dict(:colour => :color, :lw => :linewidth, :ls => :linestyle, :ms => :markersize)

# ---------------------------------------------------------------------------------------------
# Argument conversion

_num(v::Real) = Float64(v)
_num(::Missing) = NaN
_num(::Nothing) = NaN
_num(v) = throw(ArgumentError("expected numbers, got $(repr(v))"))
_vec(x::Real) = [Float64(x)]
_vec(x::AbstractVector) = Float64[_num(v) for v in x]
_vec(x::Tuple) = Float64[_num(v) for v in x]
_vec(x) = throw(ArgumentError("expected a vector of numbers, got $(typeof(x))"))
_mat(x::AbstractMatrix) = Float64[_num(v) for v in x]
_mat(x) = throw(ArgumentError("expected a matrix, got $(typeof(x))"))

_same(name, a, b) = length(a) == length(b) || throw(DimensionMismatch("$name: x has $(length(a)) values, y has $(length(b))"))

const PointArgs = NamedTuple{(:x, :y, :z), Tuple{Vector{Float64}, Vector{Float64}, Union{Nothing, Vector{Float64}}}}

function points(name, args...)
    if length(args) == 1
        a = args[1]
        if a isa AbstractVector && !isempty(a) && (first(a) isa Tuple || first(a) isa AbstractVector)
            n = length(first(a))
            n in (2, 3) || throw(ArgumentError("$name: points have 2 or 3 coordinates"))
            x = Float64[_num(p[1]) for p in a]
            y = Float64[_num(p[2]) for p in a]
            z = n == 3 ? Float64[_num(p[3]) for p in a] : nothing
            return PointArgs((x, y, z))
        elseif a isa AbstractMatrix && size(a, 2) in (2, 3) && !(eltype(a) <: AbstractVector)
            return PointArgs((_vec(a[:, 1]), _vec(a[:, 2]), size(a, 2) == 3 ? _vec(a[:, 3]) : nothing))
        end
        y = _vec(a)
        return PointArgs((collect(1.0:length(y)), y, nothing))
    elseif length(args) == 2
        x = _vec(args[1])
        y = args[2] isa Function ? Float64[_num(args[2](v)) for v in x] : _vec(args[2])
        _same(name, x, y)
        return PointArgs((x, y, nothing))
    elseif length(args) == 3
        x, y, z = _vec(args[1]), _vec(args[2]), _vec(args[3])
        _same(name, x, y)
        _same(name, x, z)
        return PointArgs((x, y, z))
    end
    throw(ArgumentError("$name takes y, (x, y), (x, y, z) or a vector of points"))
end

"""Grid arguments `(x, y, z)` as three `nx × ny` matrices (Makie's convention: `z[i, j]` is at `(x[i], y[j])`)."""
function grid3(name, args...)
    if length(args) == 1
        Z = _mat(args[1])
        nx, ny = size(Z)
        return (X = [Float64(i) for i in 1:nx, j in 1:ny], Y = [Float64(j) for i in 1:nx, j in 1:ny], Z = Z)
    elseif length(args) == 3
        a, b, c = args
        if c isa Function
            xs, ys = _vec(a), _vec(b)
            Z = Float64[_num(c(x, y)) for x in xs, y in ys]
        else
            Z = _mat(c)
        end
        nx, ny = size(Z)
        X = a isa AbstractMatrix ? _mat(a) : (xs = _vec(a); length(xs) == nx || throw(DimensionMismatch("$name: x has $(length(xs)) values, z has $nx rows")); [xs[i] for i in 1:nx, j in 1:ny])
        Y = b isa AbstractMatrix ? _mat(b) : (ys = _vec(b); length(ys) == ny || throw(DimensionMismatch("$name: y has $(length(ys)) values, z has $ny columns")); [ys[j] for i in 1:nx, j in 1:ny])
        size(X) == size(Z) && size(Y) == size(Z) || throw(DimensionMismatch("$name: x, y and z matrices differ in size"))
        return (X = X, Y = Y, Z = Z)
    end
    throw(ArgumentError("$name takes z or (x, y, z)"))
end

function _edges(c::Vector{Float64}, n::Int, name)
    if length(c) == n + 1
        return c
    elseif length(c) == n
        n == 1 && return [c[1] - 0.5, c[1] + 0.5]
        mids = [(c[i] + c[i + 1]) / 2 for i in 1:(n - 1)]
        return [c[1] - (mids[1] - c[1]); mids; c[end] + (c[end] - mids[end])]
    end
    throw(DimensionMismatch("$name: $(length(c)) coordinates for $n cells (give centres or edges)"))
end

function convert_args(::Val{K}, args...) where {K}
    if K in (:lines, :scatter, :scatterlines, :linesegments, :stem, :stairs)
        return points(K, args...)
    elseif K === :text
        if length(args) == 1 && args[1] isa TextLike
            return (x = Float64[], y = Float64[], z = nothing, text = args[1])
        end
        p = points(K, args...)
        return (x = p.x, y = p.y, z = p.z, text = nothing)
    elseif K === :area
        p = points(K, args...)
        return (x = p.x, y = p.y)
    elseif K === :barplot
        p = points(K, args...)
        return (x = p.x, y = p.y)
    elseif K === :hist
        length(args) == 1 || throw(ArgumentError("hist takes one vector of values"))
        return (values = filter(isfinite, _vec(args[1])),)
    elseif K === :errorbars
        if length(args) == 3
            x, y, e = _vec(args[1]), _vec(args[2]), _vec(args[3])
            length(e) == 1 && (e = fill(e[1], length(x)))
            return (x = x, y = y, low = e, high = e)
        elseif length(args) == 4
            x, y, lo, hi = _vec.(args)
            return (x = x, y = y, low = lo, high = hi)
        end
        throw(ArgumentError("errorbars takes (x, y, err) or (x, y, low, high)"))
    elseif K === :band
        length(args) == 3 || throw(ArgumentError("band takes (x, ylow, yhigh)"))
        x, lo, hi = _vec(args[1]), _vec(args[2]), _vec(args[3])
        _same(K, x, lo)
        _same(K, x, hi)
        return (x = x, lo = lo, hi = hi)
    elseif K === :heatmap || K === :contour || K === :contourf
        if length(args) == 1
            Z = _mat(args[1])
            x, y = collect(1.0:size(Z, 1)), collect(1.0:size(Z, 2))
        elseif length(args) == 3
            Z = args[3] isa Function ? Float64[_num(args[3](a, b)) for a in args[1], b in args[2]] : _mat(args[3])
            x, y = _vec(args[1]), _vec(args[2])
        else
            throw(ArgumentError("$K takes z or (x, y, z)"))
        end
        if K === :heatmap
            return (xe = _edges(x, size(Z, 1), K), ye = _edges(y, size(Z, 2), K), Z = Z)
        end
        length(x) == size(Z, 1) && length(y) == size(Z, 2) || throw(DimensionMismatch("$K: x and y must match size(z)"))
        return (x = x, y = y, Z = Z)
    elseif K === :image
        img = args[end]
        img isa AbstractMatrix || throw(ArgumentError("image takes a matrix (of colours or numbers)"))
        nx, ny = size(img)
        span(a, n) = a isa Tuple ? (Float64(a[1]), Float64(a[2])) : a isa AbstractVector ? (Float64(first(a)), Float64(last(a))) : (0.0, Float64(n))
        x = length(args) == 3 ? span(args[1], nx) : (0.0, Float64(nx))
        y = length(args) == 3 ? span(args[2], ny) : (0.0, Float64(ny))
        return (x = x, y = y, img = img)
    elseif K in (:hlines, :vlines)
        length(args) == 1 || throw(ArgumentError("$K takes the values"))
        return (values = _vec(args[1]),)
    elseif K === :ablines
        length(args) == 2 || throw(ArgumentError("ablines takes (intercepts, slopes)"))
        a, b = _vec(args[1]), _vec(args[2])
        length(a) == 1 && (a = fill(a[1], length(b)))
        length(b) == 1 && (b = fill(b[1], length(a)))
        return (a = a, b = b)
    elseif K === :poly
        p = points(K, args...)
        return (x = p.x, y = p.y)
    elseif K in (:series, :multiline)
        if length(args) == 1
            Y = _mat(args[1])
        elseif length(args) == 2
            Y = _mat(args[2])
        else
            throw(ArgumentError("$K takes Y or (x, Y)"))
        end
        K === :multiline && (Y = permutedims(Y))  # columns are series
        x = length(args) == 2 ? _vec(args[1]) : collect(1.0:size(Y, 2))
        length(x) == size(Y, 2) || throw(DimensionMismatch("$K: x has $(length(x)) values, each series $(size(Y, 2))"))
        return (x = x, Y = Y)
    elseif K === :surface || K === :wireframe
        return grid3(K, args...)
    elseif K === :mesh
        return mesh_args(args...)
    end
    error("unknown plot kind $K")
end

function mesh_args(args...)
    if length(args) == 2
        V, F = args
        Vm = V isa AbstractMatrix ? _mat(V) : Float64[_num(v[j]) for v in V, j in 1:length(first(V))]
        Fm = F isa AbstractMatrix ? Int[Int(f) for f in F] : Int[Int(f[j]) for f in F, j in 1:3]
    elseif length(args) == 4
        Vm = hcat(_vec(args[1]), _vec(args[2]), _vec(args[3]))
        F = args[4]
        Fm = F isa AbstractMatrix ? Int[Int(f) for f in F] : Int[Int(f[j]) for f in F, j in 1:3]
    else
        throw(ArgumentError("mesh takes (vertices, faces) or (x, y, z, faces)"))
    end
    size(Vm, 2) in (2, 3) || throw(ArgumentError("mesh vertices are n × 2 or n × 3"))
    size(Fm, 2) == 3 || throw(ArgumentError("mesh faces are m × 3 (triangles)"))
    all(1 .<= Fm .<= size(Vm, 1)) || throw(BoundsError("mesh faces index vertices 1:$(size(Vm, 1))"))
    size(Vm, 2) == 2 && (Vm = hcat(Vm, zeros(size(Vm, 1))))
    return (V = Vm, F = Fm, flat = size(Vm, 2) == 2)
end

converted(p::Plot{K}) where {K} = convert_args(Val(K), getfield(p, :input)...)

"""Whether a plot's data is 3D (it needs an Axis3)."""
function is3d(K::Symbol, data)
    K in (:surface, :wireframe) && return true
    K === :mesh && return true
    hasproperty(data, :z) && return data.z !== nothing
    return false
end

# ---------------------------------------------------------------------------------------------
# Creating plots

# One colour cycle per axis, shared by every plot kind (Makie keeps one per kind; a shared cycle
# keeps a line and a scatter in the same axis apart, which reads better in a legend).
function _cycle_index!(ax, K::Symbol)
    n = get(ax.cycle, :all, 0)
    ax.cycle[:all] = n + 1
    return n
end

function plot!(ax::AbstractAxis, K::Symbol, args...; kwargs...)
    fig = ax.figure
    attrs = plot_defaults(K, fig.theme)
    for (k, v) in theme_section(fig.theme, SECTION[K])
        haskey(attrs, k) && (attrs[k] = v)
    end
    for (k, v) in pairs(kwargs)
        k = get(PLOT_ALIASES, k, k)
        haskey(attrs, k) || throw(ArgumentError("$K has no attribute :$k. Valid: $(join(sort!(string.(collect(keys(attrs)))), ", "))"))
        attrs[k] = v
    end
    # Fail on the line that set a bad name, not when the figure is drawn.
    haskey(attrs, :colormap) && to_colormap(attrs[:colormap])
    if get(attrs, :marker, nothing) !== nothing
        m = attrs[:marker]
        m isa AbstractVector ? foreach(marker_symbol, m) : marker_symbol(m)
    end
    input = Any[args...]
    # A function argument is evaluated now, in the caller's world: a figure is drawn later, maybe
    # by code older than the function (a kernel snapshotting a session's figure).
    if length(input) == 2 && input[2] isa Function
        input[2] = Float64[_num(input[2](v)) for v in _vec(input[1])]
    elseif length(input) == 3 && input[3] isa Function
        input[3] = Float64[_num(input[3](a, b)) for a in _vec(input[1]), b in _vec(input[2])]
    end
    data = convert_args(Val(K), input...)
    if ax isa Axis && is3d(K, data) && !(K === :mesh && data.flat)
        throw(ArgumentError("$K with 3D data needs an Axis3: ax = Axis3(fig[1, 1])"))
    end
    if any(v -> v === :cycle || v === :cycle_patch || v === :palette, values(attrs))
        i = _cycle_index!(ax, K)
        palette = theme_value(fig.theme, :palette, :palette, Dict{Symbol, Any}())
        colors = get(palette, :color, WONG)
        patches = get(palette, :patchcolor, colors)
        for (k, v) in attrs
            v === :cycle && (attrs[k] = to_color(colors[mod1(i + 1, length(colors))]))
            v === :cycle_patch && (attrs[k] = to_color(patches[mod1(i + 1, length(patches))]))
            v === :palette && (attrs[k] = (colors, i))
        end
    end
    p = Plot{K}(input, attrs, ax)
    push!(ax.plots, p)
    fig.current_axis = ax
    CURRENT_FIGURE[] = fig
    return p
end

function _axis_at(gp::GridPosition)
    for c in gp.layout.content
        c.item isa AbstractAxis && c.rows == gp.rows && c.cols == gp.cols && return c.item
    end
    throw(ArgumentError("there is no axis at $gp; use the plain form (e.g. lines(fig[1, 1], …)) to make one"))
end

function _new_axisplot(gp::GridPosition, K::Symbol, args, axis, kwargs)
    data = convert_args(Val(K), args...)
    AxisType = is3d(K, data) && !(K === :mesh && data.flat) ? Axis3 : Axis
    ax = AxisType(gp; axis...)
    return AxisPlot(ax, plot!(ax, K, args...; kwargs...))
end

function _new_figure(K::Symbol, args, figure, axis, kwargs)
    fig = Figure(; figure...)
    ax, p = _new_axisplot(fig[1, 1], K, args, axis, kwargs)
    return FigureAxisPlot(fig, ax, p)
end

for K in KINDS
    f! = Symbol(K, :!)
    k = QuoteNode(K)
    @eval begin
        $f!(ax::AbstractAxis, args...; kwargs...) = plot!(ax, $k, args...; kwargs...)
        $f!(gp::GridPosition, args...; kwargs...) = plot!(_axis_at(gp), $k, args...; kwargs...)
        $f!(args...; kwargs...) = plot!(_ax(current_axis()), $k, args...; kwargs...)
        $K(gp::GridPosition, args...; axis = NamedTuple(), kwargs...) = _new_axisplot(gp, $k, args, axis, kwargs)
        $K(args...; figure = NamedTuple(), axis = NamedTuple(), kwargs...) = _new_figure($k, args, figure, axis, kwargs)
    end
end
