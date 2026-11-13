# 04 — layouts (spans, nested grids, shared and twin axes) and themes.
# Tags: [Julia] Base Julia · [SqueroPlot] this package.
using SqueroPlot

out = mkpath(joinpath(@__DIR__, "out"))             # [Julia]
t = range(0, 10; length = 300)                      # [Julia]

fig = with_theme(theme_squero()) do                 # [SqueroPlot] a temporary theme
    fig = Figure(; size = (900, 640))
    top = Axis(fig[1, 1:2]; title = "a span over two columns", ylabel = "x(t)")   # [SqueroPlot]
    lines!(top, t, exp.(-t ./ 5) .* sin.(3t))
    side = GridLayout(fig[2, 2])                    # [SqueroPlot] a nested grid
    a = Axis(side[1, 1]; ylabel = "x")
    b = Axis(side[2, 1]; ylabel = "ẋ", xlabel = "t")
    lines!(a, t, sin.(t)); lines!(b, t, cos.(t))
    linkxaxes!(a, b)                                # [SqueroPlot] shared x limits
    hidexdecorations!(a; grid = false)
    rowgap!(side, 6)
    c = Axis(fig[2, 1]; title = "twin axes", ylabel = "°C", xlabel = "hour")
    lines!(c, 0:23, [15 + 6sin(h / 24 * 2π) for h in 0:23])
    d = twinx(c; ylabel = "%")                      # [SqueroPlot] a right-hand y axis
    lines!(d, 0:23, [65 - 20sin(h / 24 * 2π) for h in 0:23])
    Label(fig[0, :], "Layouts"; fontsize = 22, font = :bold)   # [SqueroPlot] a title row, added last
    fig
end
save(joinpath(out, "04_layouts.png"), fig)

dark = with_theme(theme_dark()) do                  # [SqueroPlot]
    f, ax, p = lines(t, sin.(t); axis = (title = "theme_dark()",))   # [SqueroPlot] the one-call form
    f
end
save(joinpath(out, "04_dark.png"), dark)
