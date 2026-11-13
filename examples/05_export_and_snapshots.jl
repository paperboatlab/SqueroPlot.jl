# 05 — every export format, and snapshots for a GUI history.
# Tags: [Julia] Base Julia · [SqueroPlot] this package.
using SqueroPlot

out = mkpath(joinpath(@__DIR__, "out"))             # [Julia]
fig = Figure(; title = "Export demo")               # [SqueroPlot] a figure title for history lists
ax = Axis(fig[1, 1]; xlabel = "x", ylabel = "x²")
lines!(ax, 0:0.1:3, (0:0.1:3) .^ 2)

for ext in ("png", "svg", "pdf", "eps", "html")     # [Julia]
    save(joinpath(out, "05_export.$ext"), fig)      # [SqueroPlot] the format comes from the extension
end
bytes = render(fig; format = :pdf)                  # [SqueroPlot] the same bytes in memory
println("PDF: ", length(bytes), " bytes, header ", String(bytes[1:5]))   # [Julia]
write(joinpath(out, "05_interactive.html"), to_html(fig; interactive = true))   # [SqueroPlot] + wheel zoom / drag pan

snap = snapshot(fig; formats = (:png, :svg, :pdf))  # [SqueroPlot] an immutable copy
println(snap)                                       # Snapshot(figure-1 @ …, "Export demo", 600×450, …)
scatter!(ax, 0:3, (0:3) .^ 2; color = :red)         # [SqueroPlot] change the live figure
println("changed: ", figure_version(fig) != snap.version)          # [SqueroPlot] a new version
println("unchanged since: ", snapshot(fig; since = figure_version(fig)) === nothing)
save(joinpath(out, "05_before.pdf"), snap)          # [SqueroPlot] the old drawing, from the snapshot
save(joinpath(out, "05_after.pdf"), fig)
