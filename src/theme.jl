# Themes: nested attribute sets. Top-level keys (`fontsize`, `textcolor`, `palette`, …) are
# inherited by every block; `Axis = (…)`, `Axis3 = (…)`, `Colorbar = (…)`, `Legend = (…)`,
# `Label = (…)` and plot names (`Lines = (…)`, `Scatter = (…)`) override per block or plot type.

"""
    Theme(; kwargs...)

A set of default attributes. Nested named tuples set block or plot defaults:

```julia
Theme(fontsize = 12, Axis = (xgridvisible = false,), Lines = (linewidth = 2,))
```
"""
struct Theme
    attributes::Dict{Symbol, Any}
end

_nest(x::NamedTuple) = Dict{Symbol, Any}(k => _nest(v) for (k, v) in pairs(x))
_nest(x::AbstractDict) = Dict{Symbol, Any}(Symbol(k) => _nest(v) for (k, v) in x)
_nest(x::Theme) = deepcopy(x.attributes)
_nest(x) = x

Theme(; kwargs...) = Theme(_nest(NamedTuple(kwargs)))
Theme(t::Theme) = Theme(deepcopy(t.attributes))

Base.getindex(t::Theme, k::Symbol) = t.attributes[k]
Base.haskey(t::Theme, k::Symbol) = haskey(t.attributes, k)
Base.get(t::Theme, k::Symbol, default) = get(t.attributes, k, default)
Base.keys(t::Theme) = keys(t.attributes)
Base.:(==)(a::Theme, b::Theme) = a.attributes == b.attributes
Base.hash(t::Theme, h::UInt) = hash(t.attributes, hash(:Theme, h))
Base.show(io::IO, t::Theme) = print(io, "Theme(", join(sort!(string.(collect(keys(t.attributes)))), ", "), ")")

function _merge!(into::Dict{Symbol, Any}, from::Dict{Symbol, Any})
    for (k, v) in from
        if v isa Dict{Symbol, Any} && get(into, k, nothing) isa Dict{Symbol, Any}
            _merge!(into[k], v)
        else
            into[k] = v isa Dict ? deepcopy(v) : v
        end
    end
    return into
end

"""`merge(a, b)`: `b`'s attributes win, nested sets merge key by key."""
Base.merge(a::Theme, b::Theme) = Theme(_merge!(deepcopy(a.attributes), b.attributes))

"""Makie's defaults: 14 pt text, 600 × 450 figures, the Wong palette, viridis."""
function theme_default()
    return Theme(
        fontsize = 14,
        textcolor = :black,
        backgroundcolor = :white,
        size = (600, 450),
        figure_padding = 16,
        rowgap = 18,
        colgap = 18,
        colormap = :viridis,
        linewidth = 1.5,
        markersize = 9,
        palette = (
            color = WONG,
            patchcolor = [lerp(RGBAf(1, 1, 1, 1), c, 0.8) for c in WONG],
            marker = [:circle, :utriangle, :cross, :rect, :diamond, :dtriangle, :pentagon, :xcross],
            linestyle = [nothing, :dash, :dot, :dashdot, :dashdotdot],
        ),
        Axis = (;), Axis3 = (;), Colorbar = (;), Legend = (;), Label = (;),
    )
end

"""
The Squero look: the default theme with a quieter frame (no top/right spines), lighter grid and
a palette that matches Squero Studio.
"""
function theme_squero()
    palette = RGBAf[to_color(c) for c in ("#2563EB", "#E5484D", "#10B981", "#F59E0B", "#8B5CF6", "#06B6D4", "#64748B")]
    return merge(theme_default(), Theme(
        fontsize = 13,
        palette = (color = palette, patchcolor = [lerp(RGBAf(1, 1, 1, 1), c, 0.8) for c in palette]),
        Axis = (topspinevisible = false, rightspinevisible = false, xgridcolor = RGBAf(0, 0, 0, 0.08),
                ygridcolor = RGBAf(0, 0, 0, 0.08), titlealign = :left),
        Legend = (framevisible = false,),
    ))
end

"""Light text and lines on a dark background."""
function theme_dark()
    fg = RGBAf(0.92, 0.92, 0.92, 1)
    grid = RGBAf(1, 1, 1, 0.12)
    axis = (backgroundcolor = :transparent, xgridcolor = grid, ygridcolor = grid, spinecolor = fg,
            xtickcolor = fg, ytickcolor = fg)
    return merge(theme_default(), Theme(
        textcolor = fg,
        backgroundcolor = RGBAf(0.12, 0.12, 0.13, 1),
        Axis = axis,
        Axis3 = (xgridcolor = grid, ygridcolor = grid, zgridcolor = grid, spinecolor = fg),
        Colorbar = (spinecolor = fg, tickcolor = fg),
        Legend = (backgroundcolor = RGBAf(0.12, 0.12, 0.13, 1), framecolor = fg),
    ))
end

const CURRENT_THEME = Ref{Theme}(theme_default())

"""
    set_theme!(theme = nothing; kwargs...)

Make `theme` (plus `kwargs`) the default for new figures, on top of `theme_default()`.
`set_theme!()` restores the defaults.
"""
function set_theme!(theme::Union{Nothing, Theme} = nothing; kwargs...)
    base = theme_default()
    theme === nothing || (base = merge(base, theme))
    CURRENT_THEME[] = merge(base, Theme(; kwargs...))
    return CURRENT_THEME[]
end

"""`update_theme!(; kwargs...)` changes only the given keys of the current theme."""
update_theme!(theme::Theme = Theme(); kwargs...) = (CURRENT_THEME[] = merge(merge(CURRENT_THEME[], theme), Theme(; kwargs...)))

"""`with_theme(f, theme; kwargs...)` runs `f()` with a temporary theme."""
function with_theme(f::Function, theme::Theme = Theme(); kwargs...)
    old = CURRENT_THEME[]
    try
        CURRENT_THEME[] = merge(merge(old, theme), Theme(; kwargs...))
        return f()
    finally
        CURRENT_THEME[] = old
    end
end

"""A theme value, looked up in `section` first and then at the top level."""
function theme_value(theme::Theme, section::Symbol, key::Symbol, default)
    s = get(theme.attributes, section, nothing)
    s isa Dict{Symbol, Any} && haskey(s, key) && return s[key]
    return get(theme.attributes, key, default)
end

"""The block's or plot type's own theme section (no top-level fallback)."""
theme_section(theme::Theme, section::Symbol) = (s = get(theme.attributes, section, nothing); s isa Dict{Symbol, Any} ? s : Dict{Symbol, Any}())
