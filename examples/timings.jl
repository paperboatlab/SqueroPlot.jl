# Time to first figure and export timings. Run in a fresh process:
#   julia --project=. examples/timings.jl
t0 = time_ns()
using SqueroPlot
t_using = (time_ns() - t0) / 1e9

ms(t) = round(t * 1000; digits = 1)
x = range(0, 2π; length = 200)
line_figure() = (f = Figure(); ax = Axis(f[1, 1]; title = "t"); lines!(ax, x, sin.(x)); scatter!(ax, x[1:10:end], cos.(x[1:10:end])); f)
surface_figure() = (f = Figure(); s = surface!(Axis3(f[1, 1]), x[1:4:end], x[1:4:end], [sin(a) * cos(b) for a in x[1:4:end], b in x[1:4:end]]); Colorbar(f[1, 2], s); f)

t1 = time_ns()
render(line_figure(); format = :png)
t_first2d = (time_ns() - t1) / 1e9
t1 = time_ns()
render(surface_figure(); format = :png)
t_first3d = (time_ns() - t1) / 1e9
println("using SqueroPlot          ", ms(t_using), " ms")
println("cold first 2D figure PNG  ", ms(t_first2d), " ms   (time to first figure: ", ms(t_using + t_first2d), " ms)")
println("cold first 3D figure PNG  ", ms(t_first3d), " ms")

for (name, make) in (("2D lines+scatter", line_figure), ("3D surface 50×50", surface_figure))
    fig = make()
    for f in (:png, :svg, :pdf, :eps, :html)
        render(fig; format = f)            # first use of each format path
    end
    warm = minimum(@elapsed(render(make(); format = :png)) for _ in 1:5)
    println("\n", name, ": warm figure + PNG ", ms(warm), " ms")
    for f in (:png, :svg, :pdf, :eps, :html)
        t = minimum(@elapsed(render(fig; format = f)) for _ in 1:5)
        println("  ", rpad(f, 5), " ", lpad(ms(t), 7), " ms  ", length(render(fig; format = f)) ÷ 1024, " KiB")
    end
    t = minimum(@elapsed(snapshot(fig; formats = (:png, :svg, :pdf, :eps))) for _ in 1:3)
    println("  snapshot(png, svg, pdf, eps) ", ms(t), " ms")
end
