# 03 — 2D fields: heatmap, contour, contourf and colour bars; 3D: surface, wireframe, mesh.
# Tags: [Julia] Base Julia · [SqueroPlot] this package.
using SqueroPlot

out = mkpath(joinpath(@__DIR__, "out"))             # [Julia]
f(x, y) = sin(x) * cos(y) * exp(-(x^2 + y^2) / 8)   # [Julia] any function of two variables
xs = range(-4, 4; length = 80)                      # [Julia]
Z = [f(x, y) for x in xs, y in xs]                  # [Julia] Z[i, j] = f(xs[i], ys[j])

fig = Figure(; size = (1000, 720))                  # [SqueroPlot]
ax1 = Axis(fig[1, 1]; title = "heatmap", aspect = DataAspect())          # [SqueroPlot]
hm = heatmap!(ax1, xs, xs, Z; colormap = :balance)                       # [SqueroPlot]
Colorbar(fig[1, 2], hm)                                                   # [SqueroPlot]
ax2 = Axis(fig[1, 3]; title = "contourf + contour", aspect = DataAspect())
cf = contourf!(ax2, xs, xs, f; levels = 10, colormap = :viridis)         # [SqueroPlot] a function works as z
contour!(ax2, xs, xs, Z; levels = 10, color = :black, linewidth = 0.5)
Colorbar(fig[1, 4], cf; label = "f(x, y)")
ax3 = Axis3(fig[2, 1:2]; title = "surface")                               # [SqueroPlot]
surface!(ax3, xs, xs, Z; colormap = :balance)
ax4 = Axis3(fig[2, 3:4]; title = "mesh + wireframe", aspect = :equal)    # [SqueroPlot]
V = [1 1 1; 1 -1 -1; -1 1 -1; -1 -1 1.0]            # [Julia] a tetrahedron's vertices…
F = [1 2 3; 1 2 4; 1 3 4; 2 3 4]                    # [Julia] …and faces
mesh!(ax4, V, F; color = [0.0, 1.0, 2.0, 3.0], colormap = :plasma)       # [SqueroPlot] colours per vertex
wireframe!(ax4, range(-1, 1; length = 9), range(-1, 1; length = 9), fill(-1.0, 9, 9); color = :gray)
save(joinpath(out, "03_fields.png"), fig)
save(joinpath(out, "03_fields.svg"), fig)
