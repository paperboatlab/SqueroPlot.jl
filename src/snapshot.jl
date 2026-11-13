# Snapshots: what a GUI keeps of a figure. A snapshot is rendered bytes plus metadata, so
# changing the live figure later never changes an old snapshot, and a snapshot exports without
# the figure. The application owns history; SqueroPlot only makes snapshots and artifacts.

"""
    Snapshot

An immutable rendering of a figure: `id`, `version` (a digest of the SVG), `title`, `width`,
`height`, `plots`, `axes`, and the artifacts `png` (bytes), `svg` (string), `pdf`, `eps`
(bytes; `nothing` when not rendered). Reading `snap.png` returns a copy.

A snapshot also keeps a frozen copy of the figure as it was drawn, so `render(snap; size)` and
`snapshot_figure(snap)` can draw that version again, at another size or with another view, after
the live figure has changed or is gone.
"""
struct Snapshot
    id::String
    version::String
    title::String
    width::Int
    height::Int
    plots::Int
    axes::Int
    artifacts::Dict{Symbol, String}  # bytes kept in Strings, which cannot be mutated
    model::Figure                    # a private copy; only ever copied again, never drawn into
end

function Base.getproperty(s::Snapshot, name::Symbol)
    if name in (:png, :pdf, :eps)
        a = getfield(s, :artifacts)
        return haskey(a, name) ? Vector{UInt8}(codeunits(a[name])) : nothing
    elseif name === :svg
        return get(getfield(s, :artifacts), :svg, nothing)
    elseif name === :formats
        return Tuple(sort!(collect(keys(getfield(s, :artifacts)))))
    end
    return getfield(s, name)
end
Base.propertynames(::Snapshot) = (:id, :version, :title, :width, :height, :plots, :axes, :png, :svg, :pdf, :eps, :formats)
Base.show(io::IO, s::Snapshot) = print(io, "Snapshot(", s.id, " @ ", s.version, ", ", repr(s.title), ", ",
    s.width, "×", s.height, ", formats = ", join(s.formats, "/"), ")")

"""
    figure_id(fig) -> String

A stable id for a figure: `"figure-N"`, numbered in creation order in this Julia session
(deterministic for a given script).
"""
figure_id(fig::Figure) = "figure-" * string(fig.serial)

"""
    figure_version(fig) -> String

A content digest of the figure as it would be drawn now (16 hex characters of the SHA-256 of
its SVG). Equal versions mean identical output; any visible change gives a new version.
"""
figure_version(fig::Figure) = _digest(render(fig; format = :svg))
_digest(bytes) = bytes2hex(sha256(bytes))[1:16]

"""
    title(fig) -> String

The figure's title: `figure_title!`/`Figure(title = …)`, else the first axis title, else the
first `Label`'s text, else "".
"""
function title(fig::Figure)
    t = get(fig.attributes, :title, nothing)
    t === nothing || is_empty_text(t) || return plaintext(t)
    for b in fig.content
        b isa AbstractAxis || continue
        t = attr(b, :title)
        is_empty_text(t) || return plaintext(t)
    end
    for b in fig.content
        b isa Label || continue
        t = attr(b, :text)
        is_empty_text(t) || return plaintext(t)
    end
    return ""
end
title(f::FigureAxisPlot) = title(f.figure)

"""`plot_count(fig)`: the number of plots in all axes of the figure."""
plot_count(fig::Figure) = sum((length(b.plots) for b in fig.content if b isa AbstractAxis); init = 0)
"""`axes_count(fig)`: the number of axes (Axis and Axis3)."""
axes_count(fig::Figure) = count(b -> b isa AbstractAxis, fig.content)

"""
    snapshot(fig; formats = (:png, :svg), since = nothing, px_per_unit = 2, pt_per_unit = 0.75)

Render `fig` into an immutable `Snapshot` with the requested `formats` (any of `:png`, `:svg`,
`:pdf`, `:eps`; SVG is always kept, it defines the version). With `since = version`, returns
`nothing` when the figure has not changed since that version, without rendering the other formats.
"""
function snapshot(fig::Figure; formats = (:png, :svg), since::Union{Nothing, AbstractString} = nothing,
        px_per_unit::Real = 2, pt_per_unit::Real = 0.75)
    for f in formats
        f in (:png, :svg, :pdf, :eps) || throw(ArgumentError("snapshot formats are :png, :svg, :pdf and :eps (HTML derives from SVG)"))
    end
    svg = render(fig; format = :svg)
    version = _digest(svg)
    since !== nothing && since == version && return nothing
    artifacts = Dict{Symbol, String}(:svg => String(svg))
    for f in formats
        f === :svg && continue
        artifacts[f] = String(render(fig; format = f, px_per_unit = px_per_unit, pt_per_unit = pt_per_unit))
    end
    return Snapshot(figure_id(fig), version, title(fig), round(Int, fig.size[1]), round(Int, fig.size[2]),
        plot_count(fig), axes_count(fig), artifacts, deepcopy(fig))
end
snapshot(f::FigureAxisPlot; kwargs...) = snapshot(f.figure; kwargs...)

"""
    snapshot_figure(snap; size = nothing) -> Figure

A new, independent `Figure` equal to the one the snapshot was taken from (optionally resized).
Change it freely, for example to pan or zoom a history entry; the snapshot never changes.
"""
function snapshot_figure(s::Snapshot; size = nothing)
    fig = deepcopy(getfield(s, :model))
    size === nothing || resize!(fig, size...)
    return fig
end

"""
    render(snap; format = :png, size = nothing, px_per_unit = 2, pt_per_unit = 0.75) -> Vector{UInt8}

Draw a snapshot's version again, at `size = (width, height)` (default: as it was drawn).
"""
render(s::Snapshot; size = nothing, kwargs...) = render(snapshot_figure(s; size = size); kwargs...)

"""
    save_snapshot(snapshot, format) -> Vector{UInt8}
    save_snapshot(path, snapshot) -> path

A stored artifact of a snapshot (`:png`, `:svg`, `:pdf`, `:eps`, or `:html`, built from the
SVG), for exporting history after the live figure has changed or is gone.
"""
function save_snapshot(s::Snapshot, format::Symbol)
    a = getfield(s, :artifacts)
    format === :html && return Vector{UInt8}(html_page(a[:svg]; title = s.title))
    haskey(a, format) || throw(ArgumentError("this snapshot has no $format artifact (it has $(join(s.formats, ", "))); take it with formats = (…, :$format)"))
    return Vector{UInt8}(codeunits(a[format]))
end

function save_snapshot(path::AbstractString, s::Snapshot)
    mkpath(dirname(abspath(path)))
    write(path, save_snapshot(s, format_of(path)))
    return path
end
save(path::AbstractString, s::Snapshot) = save_snapshot(path, s)
