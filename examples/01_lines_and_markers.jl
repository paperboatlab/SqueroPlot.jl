# 01 — lines, scatter, line styles, markers and a legend.
# Tags: [Julia] Base Julia · [SqueroPlot] this package. Output goes to examples/out/.
using SqueroPlot                                    # [SqueroPlot] everything below comes from one `using`

out = mkpath(joinpath(@__DIR__, "out"))             # [Julia]
x = range(0, 2π; length = 100)                      # [Julia]

fig = Figure(; size = (700, 450))                   # [SqueroPlot]
ax = Axis(fig[1, 1]; title = "Line styles and markers", xlabel = "x", ylabel = "y",
    xticks = (0:π/2:2π, ["0", "π/2", "π", "3π/2", "2π"]))      # [SqueroPlot] ticks with text labels
for (i, style) in enumerate((:solid, :dash, :dot, :dashdot))    # [Julia]
    lines!(ax, x, sin.(x .+ i / 2); linestyle = style, linewidth = 2, label = string(style))   # [SqueroPlot]
end
markers = [:circle, :rect, :diamond, :utriangle, :star5, :xcross]   # [Julia]
scatter!(ax, range(0.5, 5.5; length = 6), fill(-1.4, 6); marker = markers, markersize = 14,
    color = :black, label = "markers")              # [SqueroPlot] one marker per point
Legend(fig[2, 1], ax; orientation = :horizontal, framevisible = false)   # [SqueroPlot] a legend block below the axis
ylims!(ax, -1.7, 1.2)                               # [SqueroPlot]
save(joinpath(out, "01_lines.png"), fig)            # [SqueroPlot]
save(joinpath(out, "01_lines.svg"), fig)
