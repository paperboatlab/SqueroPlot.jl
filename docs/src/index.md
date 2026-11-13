# Getting started

SqueroPlot draws figures (2D and 3D axes, legends, colour bars, layouts) and writes them as PNG,
SVG, PDF, EPS and standalone HTML. Its API follows Makie's, so a Makie script reads the same, but
it is a small package of its own: the renderer is Cairo, the fonts are bundled, and nothing
needs a GPU or a display.

## Install

```julia
using Pkg
Pkg.add(url = "https://github.com/paperboatlab/SqueroPlot.jl")   # or Pkg.develop(path = "SqueroPlot.jl")
```

Julia 1.11 or newer.

## A first figure

```@example start
using SqueroPlot

x = range(0, 2π; length = 60)

fig = Figure(; size = (600, 400))
ax = Axis(fig[1, 1]; title = "Waves", xlabel = "x", ylabel = "y")
lines!(ax, x, sin.(x); label = "sin")
scatter!(ax, x, cos.(x); label = "cos", markersize = 6)
stem!(ax, x[1:6:end], 0.5 .* sin.(x[1:6:end]); label = "samples")
axislegend(ax; position = :lb)

save("first.png", fig)
save("first.svg", fig)        # vector
nothing # hide
```

![](first.png)

## The pieces

- `Figure(; size)` holds a grid layout. `fig[i, j]` is a cell; `fig[1, 1:2]` spans two;
  `fig[0, :]` adds a row on top.
- Blocks go into cells: `Axis`, `Axis3`, `Colorbar`, `Legend`, `Label`, or a nested
  `GridLayout`.
- `lines!(ax, …)` adds a plot to an axis and returns it. `lines(…)` makes a figure and returns
  `(figure, axis, plot)`; `lines(fig[1, 2], …)` makes an axis in a cell.
- Attributes are keywords (`color`, `linewidth`, `marker`, …). Read or change one later with
  `plot.color[]` / `plot.color[] = :red`, or `ax.title = "…"`.
- In one axis, plots cycle through the palette across kinds (a line and a scatter get different
  colours); give `color` to choose.

## Themes

```julia
set_theme!(theme_squero())          # the Squero look for new figures
with_theme(theme_dark()) do
    lines(1:10, rand(10))
end
Figure(fontsize = 12)               # theme keys per figure
```

## Differences from Makie

SqueroPlot is not a Makie backend and does not load Makie. It has no observables or interaction;
a figure is drawn when it is saved, rendered or snapshotted. 3D views are orthographic
(`perspectiveness` is accepted and ignored). Linear, `log10`, `log2`, `log` and `sqrt` scales
are supported in 2D; 3D axes are linear.
