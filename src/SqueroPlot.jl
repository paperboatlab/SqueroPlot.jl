"""
    SqueroPlot

Figures, axes and plots for Julia, rendered with Cairo to PNG, SVG, PDF, EPS and standalone HTML.

The API keeps Makie's shape (`Figure`, `Axis`, `Axis3`, `fig[i, j]`, `lines!`, `scatter!`,
`surface!`, `Colorbar`, `Legend`, …) so a script reads the same, but SqueroPlot does not depend on
Makie: it has its own figure model, layout and renderer. A few small pieces are adapted from
Makie.jl and PlotUtils.jl (both MIT); see `NOTICE.md`.

```julia
using SqueroPlot

x = range(0, 2π; length = 50)
fig = Figure()
ax = Axis(fig[1, 1]; title = "Waves", xlabel = "x", ylabel = "y")
lines!(ax, x, sin.(x); label = "sin")
stem!(ax, x[1:5:end], cos.(x[1:5:end]); label = "cos")
axislegend(ax)
save("waves.svg", fig)
```
"""
module SqueroPlot

import Cairo
using Colors: Colors, Colorant, RGB, RGBA, @colorant_str, alpha, red, green, blue
using FreeType2_jll: libfreetype
using Printf: @sprintf
using SHA: sha256
using PrecompileTools: @compile_workload, @setup_workload

# The model
export Figure, Axis, Axis3, Colorbar, Legend, Label, GridLayout, GridPosition
export LineElement, MarkerElement, PolyElement
export current_figure, current_axis, figure_title!

# Plots (the `!` forms add to an axis; the plain forms make a figure)
export lines, lines!, scatter, scatter!, scatterlines, scatterlines!, linesegments, linesegments!
export stem, stem!, stairs, stairs!, barplot, barplot!, hist, hist!, errorbars, errorbars!
export band, band!, area, area!, heatmap, heatmap!, image, image!, contour, contour!
export contourf, contourf!, text, text!, hlines, hlines!, vlines, vlines!, ablines, ablines!
export poly, poly!, series, series!, multiline, multiline!, annotation!
export surface, surface!, mesh, mesh!, wireframe, wireframe!

# Axes, layout and theming
export xlims!, ylims!, zlims!, limits!, autolimits!, reset_limits!
export hidedecorations!, hidexdecorations!, hideydecorations!, hidespines!
export linkaxes!, linkxaxes!, linkyaxes!, twinx, axislegend
export colsize!, rowsize!, colgap!, rowgap!, Relative, Fixed, Auto, DataAspect, AxisAspect
export WilkinsonTicks, LinearTicks
export zoom!, pan!, rotate!, axes_layout
export Theme, set_theme!, update_theme!, with_theme, theme_default, theme_squero, theme_dark
export RGBf, RGBAf, RGB, RGBA, @colorant_str, Reverse, available_colormaps
export NoShading, FastShading, rich, superscript, subscript

# Output
export save, render, to_html, snapshot, Snapshot, save_snapshot, snapshot_figure
export scene_spec, apply_view!
export figure_id, figure_version, title, plot_count, axes_count

include("cairo.jl")
include("colors.jl")
include("theme.jl")
include("text.jl")
include("ticks.jl")
include("figure.jl")
include("plots.jl")
include("recipes.jl")
include("contour.jl")
include("layout.jl")
include("render2d.jl")
include("render3d.jl")
include("legend.jl")
include("export.jl")
include("snapshot.jl")
include("interact.jl")
include("scene.jl")
include("precompile.jl")

function __init__()
    # Font handles and the measuring surface are process-local pointers: never reuse the ones a
    # precompile workload created.
    reset_fonts!()
    FIGURE_SERIAL[] = 0
    CURRENT_FIGURE[] = nothing
    return nothing
end

end
