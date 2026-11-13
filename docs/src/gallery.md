# Plot gallery

Each example saves a PNG next to this page.

## Lines, scatter, stem and stairs

```@example g
using SqueroPlot
x = range(0, 4π; length = 120)
fig = Figure(; size = (800, 300))
ax = Axis(fig[1, 1]; title = "lines + scatter")
lines!(ax, x, sin.(x); label = "sin")
lines!(ax, x, cos.(x); linestyle = :dash, linewidth = 2, label = "cos")
scatter!(ax, x[1:8:end], sin.(x[1:8:end]); marker = :diamond, label = "samples")
axislegend(ax; position = :rb)
ax = Axis(fig[1, 2]; title = "stem + stairs")
n = 0:15
stem!(ax, n, exp.(-n ./ 5) .* cos.(n); label = "h[n]")
stairs!(ax, n, exp.(-n ./ 5); step = :post, label = "envelope")
axislegend(ax)
save("gallery-lines.png", fig); nothing # hide
```

![](gallery-lines.png)

## Bars, histograms, error bars, bands and areas

```@example g
fig = Figure(; size = (800, 300))
ax = Axis(fig[1, 1]; title = "barplot + errorbars", xticks = (1:4, ["Q1", "Q2", "Q3", "Q4"]))
barplot!(ax, 1:4, [12, 18, 9, 15])
errorbars!(ax, 1:4, [12, 18, 9, 15], [2, 3, 1.5, 2]; whiskerwidth = 10)
ax = Axis(fig[1, 2]; title = "hist")
hist!(ax, [sin(3k) + cos(7k) for k in 1:2000]; bins = 30, normalization = :pdf)
ax = Axis(fig[1, 3]; title = "band + area")
t = range(0, 10; length = 100)
band!(ax, t, sin.(t) .- 0.3, sin.(t) .+ 0.3)
lines!(ax, t, sin.(t); color = :black)
area!(ax, t, 0.4 .* cos.(t) .- 1.6; baseline = -1.6)
save("gallery-bars.png", fig); nothing # hide
```

![](gallery-bars.png)

## Heatmaps, contours and colour bars

```@example g
xs = range(-3, 3; length = 120)
Z = [sin(x) * cos(y) + 0.3x for x in xs, y in xs]
fig = Figure(; size = (800, 330))
hm = heatmap(fig[1, 1], xs, xs, Z; colormap = :magma, axis = (title = "heatmap",)).plot
Colorbar(fig[1, 2], hm)
ax = Axis(fig[1, 3]; title = "contourf + contour", aspect = DataAspect())
cf = contourf!(ax, xs, xs, Z; levels = 10)
contour!(ax, xs, xs, Z; levels = 10, color = :black, linewidth = 0.5)
Colorbar(fig[1, 4], cf; label = "level")
save("gallery-heat.png", fig); nothing # hide
```

![](gallery-heat.png)

## Scales, limits, ticks and labels

```@example g
f = 10 .^ range(-2, 3; length = 200)
fig = Figure(; size = (800, 300))
ax = Axis(fig[1, 1]; title = "log10 axes", xscale = log10, yscale = log10, xlabel = "ω", ylabel = "|H(jω)|")
lines!(ax, f, 1 ./ sqrt.(1 .+ f .^ 2); label = "1st order")
lines!(ax, f, 1 ./ (1 .+ f .^ 2); label = "2nd order")
axislegend(ax; position = :lb)
ax = Axis(fig[1, 2]; title = "reversed, formatted", yreversed = true, ytickformat = "{:.1f} m",
    xticks = 0:2:10, limits = (0, 10, nothing, nothing))
scatterlines!(ax, 0:10, sqrt.(0:10))
text!(ax, 5, 1; text = rich("depth ∝ t", superscript("1/2")), align = (:center, :bottom))
save("gallery-scales.png", fig); nothing # hide
```

![](gallery-scales.png)

## Layouts: spans, shared and twin axes

```@example g
fig = Figure(; size = (800, 500))
top = Axis(fig[1, 1:2]; title = "spanning two columns", ylabel = "x(t)")
t = range(0, 20; length = 400)
lines!(top, t, exp.(-t ./ 8) .* sin.(2t))
a = Axis(fig[2, 1]; ylabel = "temperature", xlabel = "hour")
lines!(a, 0:23, [20 + 5sin(h / 24 * 2π) for h in 0:23])
b = twinx(a; ylabel = "humidity")
lines!(b, 0:23, [60 - 15sin(h / 24 * 2π) for h in 0:23])
c = Axis(fig[2, 2]; xlabel = "x")
linkyaxes!(c, top)
lines!(c, t, exp.(-t ./ 8) .* cos.(2t))
Label(fig[0, :], "A figure title"; fontsize = 20, font = :bold)
save("gallery-layout.png", fig); nothing # hide
```

![](gallery-layout.png)

## 3D: surfaces, meshes, lines and scatter

```@example g
xs = range(-2, 2; length = 50)
Z = [x * exp(-x^2 - y^2) for x in xs, y in xs]
fig = Figure(; size = (800, 360))
ax = Axis3(fig[1, 1]; title = "surface + marker")
s = surface!(ax, xs, xs, Z)
scatter!(ax, [-1 / sqrt(2)], [0.0], [minimum(Z)]; color = :red, markersize = 12)
Colorbar(fig[1, 2], s)
ax = Axis3(fig[1, 3]; title = "mesh, wireframe, helix", aspect = :equal, azimuth = 0.3π)
θ = range(0, 4π; length = 200)
lines!(ax, cos.(θ), sin.(θ), θ ./ 4π)
mesh!(ax, [0 0 0; 1 0 0; 0 1 0; 0 0 1.0], [1 2 3; 1 2 4; 1 3 4; 2 3 4]; color = [0, 1, 2, 3])
wireframe!(ax, range(-1, 1; length = 6), range(-1, 1; length = 6), zeros(6, 6); color = :gray)
save("gallery-3d.png", fig); nothing # hide
```

![](gallery-3d.png)
