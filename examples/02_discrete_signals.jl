# 02 — stem, stairs, bars, error bars and a histogram: the discrete plots.
# Tags: [Julia] Base Julia · [SqueroPlot] this package.
using SqueroPlot

out = mkpath(joinpath(@__DIR__, "out"))             # [Julia]
n = 0:20                                            # [Julia]
h = 0.85 .^ n .* cos.(0.6 .* n)                     # [Julia] an impulse response

fig = Figure(; size = (900, 600))                   # [SqueroPlot]
ax1 = Axis(fig[1, 1]; title = "impulse response h[n]", xlabel = "n")      # [SqueroPlot]
stem!(ax1, n, h)                                    # [SqueroPlot] Makie's stem recipe (offset, trunk, markers)
ax2 = Axis(fig[1, 2]; title = "step response", xlabel = "n")              # [SqueroPlot]
stairs!(ax2, n, cumsum(h); step = :post, linewidth = 2)                   # [SqueroPlot]; cumsum is [Julia]
ax3 = Axis(fig[2, 1]; title = "bars with error bars", xticks = (1:4, ["A", "B", "C", "D"]))
values = [4.2, 6.1, 3.3, 5.0]; errs = [0.4, 0.7, 0.3, 0.5]               # [Julia]
barplot!(ax3, 1:4, values; color = [:steelblue, :orange, :seagreen, :purple])   # [SqueroPlot]
errorbars!(ax3, 1:4, values, errs; whiskerwidth = 12)                     # [SqueroPlot]
ax4 = Axis(fig[2, 2]; title = "histogram (pdf)")                          # [SqueroPlot]
samples = [sum(sin(13.7k * j) for j in 1:6) for k in 1:3000]             # [Julia] a deterministic sample
hist!(ax4, samples; bins = 40, normalization = :pdf)                      # [SqueroPlot]
save(joinpath(out, "02_discrete.png"), fig)
save(joinpath(out, "02_discrete.pdf"), fig)
