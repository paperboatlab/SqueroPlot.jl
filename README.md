# SqueroPlot.jl

Figures for Julia: 2D and 3D axes, legends, colour bars and layouts, written as **PNG, SVG, PDF,
EPS and standalone HTML**, with immutable **snapshots** for GUIs that keep a figure history.

The API follows [Makie](https://docs.makie.org)'s, so a script reads the same, but SqueroPlot is
a small package of its own: one Cairo renderer, bundled fonts, no GPU, no display, no Makie.

```julia
using SqueroPlot

x = range(0, 2π; length = 100)
fig = Figure()
ax = Axis(fig[1, 1]; title = "Waves", xlabel = "x", ylabel = "y")
lines!(ax, x, sin.(x); label = "sin")
scatter!(ax, x, cos.(x); label = "cos")
stem!(ax, x[1:10:end], sin.(x[1:10:end]))
axislegend(ax)
save("figure.svg", fig)
```

## Install

```julia
using Pkg
Pkg.develop(path = "path/to/SqueroPlot.jl")   # or Pkg.add(url = "…/SqueroPlot.jl")
```

Julia 1.11 or newer. Dependencies: Cairo, Colors, FreeType2_jll, PrecompileTools, SHA.

## API summary

| Area | Names |
| --- | --- |
| Figure and layout | `Figure`, `fig[i, j]`, `GridLayout`, `Label`, `colsize!`, `rowsize!`, `colgap!`, `rowgap!`, `Fixed`, `Relative`, `Auto` |
| Axes | `Axis` (scales `log10`/`log2`/`log`/`sqrt`, `limits`, `xreversed`, ticks, `xtickformat`, `aspect = DataAspect()`), `Axis3` (`azimuth`, `elevation`, `aspect`), `twinx`, `linkaxes!`, `linkxaxes!`, `linkyaxes!`, `xlims!`, `ylims!`, `zlims!`, `limits!`, `hidedecorations!`, `hidespines!` |
| 2D plots | `lines`, `scatter`, `scatterlines`, `linesegments`, `stem`, `stairs`, `barplot`, `hist`, `errorbars`, `band`, `area`, `heatmap`, `image`, `contour`, `contourf`, `text`, `hlines`, `vlines`, `ablines`, `poly`, `series`, `multiline`, `annotation!` |
| 3D plots | `lines`, `scatter`, `stem`, `text` in an `Axis3`; `surface`, `mesh`, `wireframe` |
| Guides | `Legend`, `axislegend`, `LineElement`, `MarkerElement`, `PolyElement`, `Colorbar` |
| Text | strings, or `rich(…)` with `superscript`/`subscript`; Unicode (Greek, math) built in |
| Themes | `Theme`, `set_theme!`, `update_theme!`, `with_theme`, `theme_default`, `theme_squero`, `theme_dark`, `available_colormaps` |
| Export | `save(path, fig)`, `render(fig; format)`, `to_html(fig; interactive)` |
| Snapshots | `snapshot(fig; formats, since)`, `Snapshot`, `save_snapshot`, `figure_id`, `figure_version`, `title`, `plot_count`, `axes_count` |

Every plot has a mutating form (`lines!(ax, …)`, returns the plot) and a creating form
(`lines(…)` returns `(figure, axis, plot)`; `lines(fig[i, j], …)` returns `(axis, plot)`).

## Export

| Format | Kind | Notes |
| --- | --- | --- |
| PNG | raster | `px_per_unit = 2` by default |
| SVG | vector | `<title>`/`<desc>` carry the figure's text |
| PDF, EPS | vector | 1 unit = 0.75 pt (`pt_per_unit`) |
| HTML | vector | a standalone page with the SVG inline; no external CSS, JS or fonts |

## Snapshots for GUIs

```julia
snap = snapshot(fig; formats = (:png, :svg, :pdf, :eps))
snap.id, snap.version, snap.title, snap.width, snap.height, snap.plots, snap.axes
snapshot(fig; since = snap.version)    # nothing: the drawing has not changed
save_snapshot(snap, :pdf)              # bytes, even after `fig` changed or is gone
```

## Documentation, examples, tests

```sh
julia --project=docs docs/make.jl           # Getting started, gallery, export, snapshots, API
julia --project=. examples/run_all.jl        # standalone examples → examples/out/
julia --project=. examples/timings.jl        # time to first figure, export timings
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Licence

MIT. A few small pieces are adapted from Makie.jl, PlotUtils.jl and ColorSchemes.jl (all MIT),
and the bundled fonts carry their own licences; see [NOTICE.md](NOTICE.md).
