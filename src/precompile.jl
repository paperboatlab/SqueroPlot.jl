# A precompile workload for the common figures, so the first figure of a session is quick. Inputs
# come as scripts write them: ranges, integer ranges, vectors, matrices from comprehensions.

@setup_workload begin
    r = range(0, 2π; length = 30)
    v = collect(r)
    Z = [sin(a) * cos(b) for a in r[1:6], b in r[1:6]]
    @compile_workload begin
        for x in (r, v)
            fig = Figure(; size = (300, 220), title = "w")
            ax = Axis(fig[1, 1]; title = "t", xlabel = "x", ylabel = "y")
            lines!(ax, x, sin.(x); label = "sin")
            scatter!(ax, x, cos.(x); label = "cos")
            stem!(ax, x[1:5:end], sin.(x[1:5:end]))
            stairs!(ax, x, cos.(x))
            axislegend(ax)
            hm = heatmap!(Axis(fig[1, 2]), Z)
            Colorbar(fig[1, 3], hm)
            ax3 = Axis3(fig[2, 1:3])
            surface!(ax3, r[1:6], r[1:6], Z)
            lines!(ax3, x, sin.(x), cos.(x))
            scatter!(ax3, [1.0], [1.0], [0.0])
            for f in (:png, :svg, :pdf)
                render(fig; format = f, px_per_unit = 1)
            end
        end
        fig = Figure()
        ax = Axis(fig[1, 1])
        lines!(ax, 1:5, [1, 4, 9, 16, 25])
        barplot!(ax, 1:3, [1, 2, 3])
        contourf!(Axis(fig[1, 2]), r[1:6], r[1:6], Z)
        snapshot(fig; formats = (:png, :svg, :pdf, :eps))
        to_html(fig)
    end
    reset_fonts!()
    FIGURE_SERIAL[] = 0
    CURRENT_FIGURE[] = nothing
end
