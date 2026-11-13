using Test
using SqueroPlot
using Aqua

const S = SqueroPlot

# --- helpers --------------------------------------------------------------------------------

"""A small XML well-formedness check: balanced tags, one root, no stray `<`."""
function wellformed(xml::AbstractString)
    stack = String[]
    roots = 0
    i = firstindex(xml)
    while (j = findnext('<', xml, i)) !== nothing
        if startswith(SubString(xml, j), "<!--")
            k = findnext("-->", xml, j)
            k === nothing && return false
            i = last(k) + 1
            continue
        elseif startswith(SubString(xml, j), "<![CDATA[")
            k = findnext("]]>", xml, j)
            k === nothing && return false
            i = last(k) + 1
            continue
        end
        k = findnext('>', xml, j)
        k === nothing && return false
        tag = xml[j:k]
        i = k + 1
        if startswith(tag, "<?") || startswith(tag, "<!")
            continue
        elseif startswith(tag, "</")
            name = strip(tag[3:(end - 1)])
            (isempty(stack) || pop!(stack) != name) && return false
        else
            name = match(r"^<([A-Za-z_:][\w:.-]*)", tag)
            name === nothing && return false
            isempty(stack) && (roots += 1)
            endswith(tag, "/>") || push!(stack, name.captures[1])
        end
    end
    return isempty(stack) && roots == 1
end

png_size(b) = (Int(ntoh(reinterpret(UInt32, b[17:20])[1])), Int(ntoh(reinterpret(UInt32, b[21:24])[1])))
const PNG_MAGIC = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

function check_formats(fig; title = nothing)
    png = render(fig; format = :png, px_per_unit = 1)
    @test png[1:8] == PNG_MAGIC
    @test png_size(png) == (round(Int, fig.size[1]), round(Int, fig.size[2]))
    svg = String(render(fig; format = :svg))
    @test startswith(svg, "<?xml")
    @test wellformed(svg)
    @test occursin("<path", svg)
    title === nothing || @test occursin("<title>$title</title>", svg)
    pdf = render(fig; format = :pdf)
    @test String(pdf[1:5]) == "%PDF-"
    @test occursin("%%EOF", String(pdf[(end - 8):end]))
    eps = render(fig; format = :eps)
    @test startswith(String(eps[1:30]), "%!PS-Adobe-3.0 EPSF-3.0")
    @test occursin("%%BoundingBox:", String(eps))
    html = to_html(fig)
    @test startswith(html, "<!DOCTYPE html>")
    @test occursin("<svg", html)
    return svg
end

# --- the model -------------------------------------------------------------------------------

@testset "SqueroPlot" begin

@testset "2D: lines, scatter, stem, stairs, bars" begin
    x = range(0, 2π; length = 40)
    fig = Figure(; size = (500, 360))
    ax = Axis(fig[1, 1]; title = "Waves", xlabel = "x", ylabel = "y")
    l = lines!(ax, x, sin.(x); label = "sin")
    s = scatter!(ax, x, cos.(x); label = "cos", marker = :diamond)
    st = stem!(ax, x[1:5:end], sin.(x[1:5:end]); label = "stem", offset = 0.1)
    sr = stairs!(ax, 1:5, [1, 3, 2, 4, 3]; step = :post)
    b = barplot!(ax, 1:3, [0.5, 0.8, 0.2]; label = "bars")
    axislegend(ax)
    @test S.kind(l) == :lines && S.kind(st) == :stem
    @test plot_count(fig) == 5 && axes_count(fig) == 1
    @test title(fig) == "Waves"
    svg = check_formats(fig; title = "Waves")
    @test occursin("sin", svg) && occursin("cos", svg)  # labels are in <desc>
    # colours cycle across kinds in one axis
    @test l.color[] != s.color[]
    # Makie's stair geometry
    @test S.stair_points([1.0, 2.0, 3.0], [1.0, 2.0, 3.0], :pre) == ([1.0, 1.0, 2.0, 2.0, 3.0], [1.0, 2.0, 2.0, 3.0, 3.0])
    @test S.stair_points([1.0, 2.0, 3.0], [1.0, 2.0, 3.0], :post) == ([1.0, 2.0, 2.0, 3.0, 3.0], [1.0, 1.0, 2.0, 2.0, 3.0])
    @test length(S.stair_points([1.0, 2.0, 3.0], [1.0, 2.0, 3.0], :center)[1]) == 6
    @test_throws ArgumentError S.stair_points([1.0], [1.0], :middle)
    # attributes read and write like Makie's
    l.color[] = :red
    @test l.color[] == :red
    ax.title[] = "Changed"
    @test title(fig) == "Changed"
    ax.xlabel = "time"
    @test ax.xlabel[] == "time"
    @test_throws ArgumentError lines!(ax, x, x; colr = :red)
    @test_throws ArgumentError Axis(fig[2, 1]; nonsense = 1)
    @test_throws DimensionMismatch lines!(ax, 1:3, 1:4)
end

@testset "more 2D kinds" begin
    fig = Figure()
    ax = Axis(fig[1, 1])
    hist!(ax, randn(200); bins = 12, normalization = :pdf)
    errorbars!(ax, 1:3, [1, 2, 3], [0.1, 0.2, 0.3]; whiskerwidth = 6)
    band!(ax, 1:3, [0, 1, 2], [1, 2, 3])
    area!(ax, 1:3, [1, 2, 1])
    hlines!(ax, [0.5]); vlines!(ax, [2]); ablines!(ax, 0, 1)
    poly!(ax, [(0, 0), (1, 0), (0.5, 1)])
    text!(ax, 1, 1; text = rich("10", superscript("3")))
    annotation!(ax, 2, 2, 1, 1; text = "here")
    series!(ax, 1:4, [1 2 3 4; 2 3 4 5]; labels = ["a", "b"])
    multiline!(ax, 1:4, [1 2; 2 3; 3 4; 4 5]; color = :viridis)
    scatterlines!(ax, 1:3, [3, 2, 1])
    linesegments!(ax, [0, 1, 2, 3], [0, 1, 0, 1])
    ax2 = Axis(fig[1, 2])
    hm = heatmap!(ax2, 1:20, 1:10, [i + j for i in 1:20, j in 1:10])
    contour!(ax2, 1:20, 1:10, [sin(i / 3) * cos(j / 3) for i in 1:20, j in 1:10]; levels = 4)
    Colorbar(fig[1, 3], hm; label = "value")
    ax3 = Axis(fig[2, 1])
    cf = contourf!(ax3, range(-2, 2; length = 30), range(-2, 2; length = 30), (x, y) -> exp(-x^2 - y^2); levels = 6)
    Colorbar(fig[2, 3], cf)
    image!(Axis(fig[2, 2]), [RGBf(i / 8, j / 8, 0.5) for i in 1:8, j in 1:8])
    @test plot_count(fig) == 18
    check_formats(fig)
    # a heatmap big enough for the raster path
    fig2 = Figure()
    heatmap(fig2[1, 1], rand(80, 60))
    svg = String(render(fig2; format = :svg))
    @test occursin("<image", svg)
    # contour helpers
    segs = S.contour_segments([0.0, 1.0], [0.0, 1.0], [0.0 0.0; 1.0 1.0], 0.5)
    @test length(segs) == 1 && segs[1][1] == 0.5 && segs[1][3] == 0.5
    polys = S.contourf_polygons([0.0, 1.0], [0.0, 1.0], [0.0 0.0; 1.0 1.0], [0.0, 0.5, 1.0])
    area(p) = abs(sum(p[i][1] * p[mod1(i + 1, length(p))][2] - p[mod1(i + 1, length(p))][1] * p[i][2] for i in eachindex(p))) / 2
    @test sum(area(p) for (_, p) in polys) ≈ 1.0
    @test S.contour_levels(4, [0.0 1.0]) ≈ [0.2, 0.4, 0.6, 0.8]
    @test S.hist_bars([1.0, 2.0, 2.0, 3.0], 2, :none)[2] == [1.0, 3.0]
end

@testset "axes: scales, limits, ticks" begin
    fig = Figure()
    ax = Axis(fig[1, 1]; xscale = log10, yscale = log10, limits = (1, 1000, nothing, nothing), xreversed = true)
    lines!(ax, [1, 10, 100, 1000], [1, 0.1, 0.01, 0.001])
    xlims!(ax, 1, 1000)
    ylims!(ax, nothing, 2)
    states, rects = S.layout_figure(fig)
    st = states[ax]
    @test st.xticks == [1.0, 10.0, 100.0, 1000.0]
    @test st.xreversed
    @test st.ylims[2] ≈ log10(2)
    @test st.xlabels[2] isa S.RichText && string(st.xlabels[2]) == "101"  # 10 and a superscript 1
    # limits on a fresh (all automatic) axis, one side at a time
    fresh = Axis(Figure()[1, 1])
    ylims!(fresh, 0, 0.75)
    @test fresh.limits[] == (nothing, (0, 0.75))
    xlims!(fresh, (1, 2))
    @test fresh.limits[] == ((1, 2), (0, 0.75))
    # function arguments are evaluated when the plot is added, not when it is drawn
    fp = lines!(fresh, [0.0, 1.0], x -> 2x)
    @test fp[2][] == [0.0, 2.0]
    cp = contour!(fresh, 1:3, 1:2, (x, y) -> x * y)
    @test cp[3][] == [1.0 2.0; 2.0 4.0; 3.0 6.0]
    # a tick format defined after the package code still runs (invokelatest)
    fmt = Core.eval(Module(), :(vs -> string.(vs, "!")))
    @test S.apply_format(fmt, [1.0]) == ["1.0!"]
    reset_limits!(ax); autolimits!(ax)
    @test ax.limits[] == (nothing, nothing)
    @test S.optimize_ticks(0.0, 10.0) == [0.0, 5.0, 10.0]  # ties with 0:2.5:10; the first wins, as in PlotUtils
    @test S.optimize_ticks(-1.0, 1.0) == [-1.0, -0.5, 0.0, 0.5, 1.0]
    @test S.format_ticks([0.0, 0.5, 1.0]) == ["0.0", "0.5", "1.0"]
    @test S.format_ticks([-1.0, 0.0, 1.0]) == ["−1", "0", "1"]
    @test S.apply_format("{:.2f} m", [1.0]) == ["1.00 m"]
    @test S.apply_format(v -> string.(Int.(v), "%"), [10.0]) == ["10%"]
    fig = Figure()
    ax = Axis(fig[1, 1]; xticks = ([1, 2, 3], ["a", "b", "c"]), yticks = LinearTicks(3))
    scatter!(ax, 1:3, 1:3)
    st = S.layout_figure(fig)[1][ax]
    @test st.xlabels == ["a", "b", "c"] && length(st.yticks) == 3
    # an empty axis still draws
    fig = Figure()
    Axis(fig[1, 1]; title = "empty")
    check_formats(fig; title = "empty")
    @test plot_count(fig) == 0
end

@testset "layouts, legends, colorbars" begin
    fig = Figure(; size = (800, 600))
    a = Axis(fig[1, 1]; ylabel = "a long y label", yticks = [0, 1000000])
    b = Axis(fig[2, 1])
    c = Axis(fig[1:2, 2]; title = "span")
    lines!(a, 1:3, [0, 500000, 1000000]; label = "one")
    lines!(b, 1:3, 1:3; label = "two")
    hm = heatmap!(c, rand(5, 5))
    cb = Colorbar(fig[1:2, 3], hm; label = "z")
    lg = Legend(fig[3, 1:2], a; orientation = :horizontal)
    t = Label(fig[0, :], "Super title"; font = :bold, fontsize = 20)
    linkxaxes!(a, b)
    colsize!(fig.layout, 1, Relative(0.5))
    states, rects = S.layout_figure(fig)
    @test rects[a].x ≈ rects[b].x                     # aligned plot areas in one column
    @test rects[a].w ≈ rects[b].w
    @test rects[c].x > rects[a].x + rects[a].w        # the spanning axis is to the right
    @test rects[cb].x > rects[c].x + rects[c].w       # then the colour bar
    @test rects[cb].w ≈ 12
    @test rects[t].y < rects[a].y                     # row 0 went on top
    @test rects[lg].y > rects[b].y + rects[b].h       # the legend row is at the bottom
    @test rects[c].y ≈ rects[a].y && rects[c].y + rects[c].h ≈ rects[b].y + rects[b].h
    @test states[a].xlims == states[b].xlims          # linked
    @test length(S.legend_entries(lg)) == 1
    check_formats(fig; title = "span")
    # a vertical legend sets its column's width, not its row's height; a horizontal one the reverse
    fig = Figure()
    ax = Axis(fig[1, 1])
    lines!(ax, 1:3, 1:3; label = "a")
    side = Legend(fig[1, 2], ax)
    below = Legend(fig[2, 1], ax; orientation = :horizontal)
    states, rects = S.layout_figure(fig)
    @test rects[ax].h > 250 && rects[side].h < 60
    @test rects[ax].w > 400 && rects[below].w < 100
    @test rects[below].x > rects[ax].x                # centred under the axis
    # nested layouts and twin axes
    fig = Figure()
    g = GridLayout(fig[1, 1])
    a1 = Axis(g[1, 1]); a2 = Axis(fig[1, 2][1, 1])
    lines!(a1, 1:3, 1:3)
    tw = twinx(a1; ylabel = "right")
    lines!(tw, 1:3, [10, 20, 30])
    rowgap!(g, 4); colgap!(fig.layout, 10); rowsize!(g, 1, Auto())
    states, rects = S.layout_figure(fig)
    @test rects[tw] == rects[a1]
    @test states[tw].xlims == states[a1].xlims
    check_formats(fig)
    # explicit legend elements
    fig = Figure()
    ax = Axis(fig[1, 1])
    p = scatter!(ax, 1:3, 1:3)
    Legend(fig[1, 2], [LineElement(color = :red), [p, MarkerElement(marker = :star5)], PolyElement(color = :blue)], ["l", "p", "poly"], "Title")
    check_formats(fig)
end

@testset "3D: lines, scatter, surface, mesh" begin
    fig = Figure(; size = (700, 500))
    ax = Axis3(fig[1, 1]; title = "Surface", azimuth = 0.3π, elevation = 0.25π)
    xs = range(-2, 2; length = 25)
    sf = surface!(ax, xs, xs, [x * exp(-x^2 - y^2) for x in xs, y in xs])
    lines!(ax, xs, xs, zeros(25))
    scatter!(ax, [0.0], [0.0], [0.4]; color = :red)
    stem!(ax, [1.0], [1.0], [0.3])
    text!(ax, [0.0], [0.0], [0.45]; text = "top")
    Colorbar(fig[1, 2], sf)
    ax2 = Axis3(fig[1, 3]; aspect = :data, limits = (0, 1, 0, 1, 0, 1))
    mesh!(ax2, [0 0 0; 1 0 0; 0 1 0; 0 0 1], [1 2 3; 1 2 4; 1 3 4; 2 3 4]; color = [0, 1, 2, 3], shading = NoShading)
    wireframe!(ax2, 0:0.25:1, 0:0.25:1, [x * y for x in 0:0.25:1, y in 0:0.25:1])
    @test plot_count(fig) == 7 && axes_count(fig) == 2
    check_formats(fig; title = "Surface")
    # 3D data needs an Axis3; the plain forms pick the right axis
    @test_throws ArgumentError lines!(Axis(fig[2, 1]), 1:3, 1:3, 1:3)
    f, a, p = surface(rand(5, 5))
    @test a isa Axis3 && S.kind(p) == :surface
    f, a, p = scatter(1:3, 1:3, 1:3)
    @test a isa Axis3
    f, a, p = lines(1:3, 1:3)
    @test a isa Axis
    ap = scatter(f[1, 2], 1:3, 1:3)
    @test ap.axis isa Axis
    @test S.kind(stem!(a, 1:3, 1:3)) == :stem
end

@testset "export API" begin
    dir = mktempdir()
    fig = Figure()
    lines(fig[1, 1], 1:10, (1:10) .^ 2)
    for ext in ("png", "svg", "pdf", "eps", "html")
        path = save(joinpath(dir, "fig.$ext"), fig)
        @test isfile(path) && filesize(path) > 500
    end
    @test_throws ArgumentError save(joinpath(dir, "fig.gif"), fig)
    @test png_size(read(joinpath(dir, "fig.png"))) == (1200, 900)  # px_per_unit = 2
    html = read(joinpath(dir, "fig.html"), String)
    @test !occursin("<script", html) && !occursin("<link", html) && !occursin("@import", html)
    @test !occursin(r"(src|href)=\"https?:", html)
    @test occursin("<script", to_html(fig; interactive = true))
    # deterministic output
    @test render(fig; format = :svg) == render(fig; format = :svg)
    @test figure_version(fig) == figure_version(fig)
    # show methods
    @test occursin("Figure(600×450", sprint(show, fig))
    @test startswith(String(sprint(show, MIME("image/svg+xml"), fig)), "<?xml")
end

@testset "snapshots" begin
    fig = Figure(; title = "History")
    ax = Axis(fig[1, 1]; title = "first")
    lines!(ax, 1:3, [1, 2, 3])
    id = figure_id(fig)
    @test startswith(id, "figure-")
    snap = snapshot(fig; formats = (:png, :svg, :pdf, :eps))
    @test snap.id == id && snap.title == "History" && snap.plots == 1 && snap.axes == 1
    @test (snap.width, snap.height) == (600, 450)
    @test snap.formats == (:eps, :pdf, :png, :svg)
    @test snap.png[1:8] == PNG_MAGIC
    @test wellformed(snap.svg)
    # immutable: later changes to the figure do not reach the snapshot
    svg0, png0 = snap.svg, snap.png
    scatter!(ax, 1:3, [3, 2, 1])
    ax.title[] = "second"
    figure_title!(fig, "Changed")
    @test snap.svg == svg0 && snap.png == png0 && snap.title == "History" && snap.plots == 1
    b = snap.png
    b[1] = 0x00
    @test snap.png[1] == 0x89                     # reading gives a copy
    @test_throws ErrorException (snap.version = "x")
    # versions: a change makes a new one; no change returns nothing with `since`
    snap2 = snapshot(fig)
    @test snap2.version != snap.version && snap2.id == snap.id && snap2.plots == 2
    @test snapshot(fig; since = snap2.version) === nothing
    @test snapshot(fig; since = snap.version) isa Snapshot
    # historical export needs no figure
    dir = mktempdir()
    for f in (:png, :svg, :pdf, :eps, :html)
        bytes = save_snapshot(snap, f)
        @test !isempty(bytes)
        save(joinpath(dir, "h.$f"), snap)
        @test read(joinpath(dir, "h.$f")) == bytes
    end
    @test occursin("<svg", String(save_snapshot(snap, :html)))
    @test_throws ArgumentError save_snapshot(snap2, :pdf)
    @test_throws ArgumentError snapshot(fig; formats = (:gif,))
    # ids follow creation order; titles fall back to the axis, then a Label
    f1, f2 = Figure(), Figure()
    @test parse(Int, split(figure_id(f2), "-")[2]) == parse(Int, split(figure_id(f1), "-")[2]) + 1
    Label(f1[1, 1], "Only a label")
    @test title(f1) == "Only a label"
    @test title(f2) == ""
end

@testset "interaction and re-rendering" begin
    fig = Figure()
    a = Axis(fig[1, 1])
    b = Axis(fig[2, 1])
    lines!(a, 0:10, 0:10)
    lines!(b, 0:10, 10:-1:0)
    linkxaxes!(a, b)
    lay = axes_layout(fig)
    @test [l.index for l in lay] == [1, 2] && lay[1].kind == :axis && lay[1].y < lay[2].y
    xl0 = S.prepare_figure(fig)[a].xlims
    zoom!(a, 0.5; around = (0.5, 0.5))
    xl1 = S.prepare_figure(fig)[a].xlims
    @test (xl1[2] - xl1[1]) ≈ (xl0[2] - xl0[1]) / 2
    @test S.prepare_figure(fig)[b].xlims == xl1                 # linked axes follow
    pan!(a, 0.25, 0.0)                                          # drag right: the view moves left
    xl2 = S.prepare_figure(fig)[a].xlims
    @test xl2[1] ≈ xl1[1] - 0.25 * (xl1[2] - xl1[1])
    ylog = Axis(fig[3, 1]; yscale = log10)
    lines!(ylog, 1:3, [1, 10, 100])
    yl0 = S.prepare_figure(fig)[ylog].ylims
    zoom!(ylog, 0.5; around = (0.5, 0.0), x = false)            # about the bottom, in log space
    yl1 = S.prepare_figure(fig)[ylog].ylims
    @test yl1[1] ≈ yl0[1] && (yl1[2] - yl1[1]) ≈ (yl0[2] - yl0[1]) / 2
    rev = Axis(Figure()[1, 1]; xreversed = true)
    lines!(rev, 0:10, 0:10)
    pan!(rev, 0.1, 0)
    @test S.prepare_figure(rev.figure)[rev].xreversed
    a3 = Axis3(fig[1:3, 2])
    surface!(a3, rand(4, 4))
    az = a3.azimuth[]
    rotate!(a3, 0.1, 10.0)
    @test a3.azimuth[] ≈ az + 0.1 && a3.elevation[] ≈ 0.49π
    span0 = S.prepare3d(a3).lims[1]
    zoom!(a3, 0.5)
    @test a3.limits[][1][2] - a3.limits[][1][1] ≈ (span0[2] - span0[1]) / 2
    @test axes_layout(fig)[end].kind == :axis3
    # a snapshot re-renders at another size, from its frozen copy
    f = Figure(; title = "T")
    lines!(Axis(f[1, 1]), 1:3, 1:3)
    snap = snapshot(f)
    lines!(current_axis(f), 1:3, 3:-1:1)                       # the live figure moves on
    png = render(snap; format = :png, size = (300, 200), px_per_unit = 1)
    @test png_size(png) == (300, 200)
    copy1 = snapshot_figure(snap; size = (500, 300))
    @test plot_count(copy1) == 1 && copy1.size == (500.0, 300.0)
    zoom!(axes_layout(copy1)[1].index == 1 ? S.axes_of(copy1)[1] : nothing, 0.5)
    @test snapshot_figure(snap).content[1].limits[] == (nothing, nothing)   # the snapshot's copy is untouched
    @test render(snap; format = :svg) == Vector{UInt8}(snap.svg)            # same drawing as stored
end

@testset "themes" begin
    fig = with_theme(theme_squero()) do
        Figure()
    end
    @test fig.theme[:fontsize] == 13
    @test Figure().theme[:fontsize] == 14
    set_theme!(theme_dark())
    @test Figure().backgroundcolor != RGBAf(1, 1, 1, 1)
    set_theme!()
    @test Figure().backgroundcolor == RGBAf(1, 1, 1, 1)
    update_theme!(fontsize = 18)
    @test Figure().theme[:fontsize] == 18
    set_theme!()
    @test Figure(fontsize = 9).theme[:fontsize] == 9
    @test_throws ArgumentError Figure(fontsiz = 9)
    @test length(available_colormaps()) > 10
    @test_throws ArgumentError heatmap!(Axis(Figure()[1, 1]), rand(3, 3); colormap = :nope)
    @test_throws ArgumentError scatter!(Axis(Figure()[1, 1]), 1:3, 1:3; marker = :blob)
    lines!(Axis(fig[1, 1]), 1:3, 1:3)
    check_formats(fig)
end

@testset "scene & apply_view!" begin
    fig = Figure(; size = (640, 400), title = "Scene Test")
    ax1 = Axis(fig[1, 1]; xlabel = rich("x", superscript("2")), ylabel = "y")
    lines!(ax1, [0.0, 1.0, NaN, 2.0], [1.0, 2.0, NaN, 3.0]; label = "sig", linestyle = :solid)
    stairs!(ax1, 1:4, [1.0, 3.0, 2.0, 4.0]; linestyle = "--")
    scatter!(ax1, 1:100, collect(1.0:100.0); color = 1.0:100.0, colormap = :plasma)
    barplot!(ax1, [1, 2, 3], [2.0, 4.0, 1.0]; label = "bars")
    hist!(ax1, randn(80); bins = 8)
    errorbars!(ax1, 1:3, [2.0, 3.0, 2.5], fill(0.3, 3))
    band!(ax1, 1:5, zeros(5), ones(5))
    area!(ax1, 1:5, ones(5))
    hlines!(ax1, [0.5]; color = :gray)
    vlines!(ax1, [1.5]; linestyle = :dot)
    ablines!(ax1, [0.0], [1.0])
    poly!(ax1, [0.0, 1.0, 0.5], [0.0, 0.0, 1.0])
    series!(ax1, collect(1.0:4.0), [1.0 2.0 3.0 4.0; 2.0 3.0 4.0 5.0]; labels = ["a", "b"])
    text!(ax1, 1.0, 1.0; text = "pt")
    annotation!(ax1, 1.5, 1.5, 2.0, 2.0; text = "ann")
    axislegend(ax1)

    ax2 = Axis(fig[2, 1]; yscale = log10)
    Z = [sin(i / 4) * cos(j / 4) for i in 1:20, j in 1:16]
    heatmap!(ax2, 1:20, 1:16, Z)
    contour!(ax2, 1:20, 1:16, Z; levels = 4)
    contourf!(ax2, 1:20, 1:16, Z; levels = 4)
    linkxaxes!(ax1, ax2)
    cb = Colorbar(fig[1:2, 2]; colorrange = (-1, 1), colormap = :viridis, label = "Z")

    ax3 = Axis3(fig[1:2, 3]; aspect = :equal)
    surface!(ax3, 1:10, 1:10, rand(10, 10))
    lines!(ax3, 1.0:100.0, cos.(1.0:100.0), sin.(1.0:100.0); color = 1.0:100.0)
    wireframe!(ax3, 1:4, 1:4, rand(4, 4))
    Label(fig[0, :], "Header")

    spec, bytes = scene_spec(fig)
    @test spec["width"] == 640 && spec["height"] == 400
    @test spec["layout"]["kind"] == "grid"
    @test !isempty(bytes)
    items = spec["layout"]["items"]
    a1_spec = first(it["block"] for it in items if it["block"]["kind"] == "axis" && it["block"]["index"] == 1)
    a2_spec = first(it["block"] for it in items if it["block"]["kind"] == "axis" && it["block"]["index"] == 2)
    a3_spec = first(it["block"] for it in items if it["block"]["kind"] == "axis3" && it["block"]["index"] == 3)
    @test a1_spec["plots"][1]["linestyle"] == "solid"
    @test a1_spec["plots"][1]["y"][3] === nothing
    @test a1_spec["plots"][2]["linestyle"] == "dashed"
    @test a1_spec["plots"][3]["x"]["buf"] == true
    @test length(bytes) >= a1_spec["plots"][3]["x"]["offset"] + 4 * 100
    f32_slice = let off = a1_spec["plots"][3]["x"]["offset"]
        reinterpret(Float32, @view bytes[(off + 1):(off + 4 * 100)])
    end
    @test f32_slice[1] ≈ 1.0f0 && f32_slice[end] ≈ 100.0f0
    @test a1_spec["linkX"] !== nothing && a1_spec["linkX"] == a2_spec["linkX"]
    @test a2_spec["yscale"] == "log10"
    @test a3_spec["half"] == [1.0, 1.0, 1.0]
    @test !isempty(a3_spec["plots"])
    @test any(it -> it["block"]["kind"] == "colorbar", items)
    @test any(it -> it["block"]["kind"] == "label", items)

    snap = snapshot(fig)
    svg_scripted = String(render(snap; format = :svg))
    fig_view = snapshot_figure(snap; size = (800, 500))
    apply_view!(fig_view, Dict(
        "axes" => [
            Dict("index" => 1, "limits" => [0.5, 5.5, -2.0, 6.0], "xgridvisible" => false),
            Dict("index" => 3, "azimuth" => 1.1, "elevation" => 0.4, "perspectiveness" => 0.0,
                 "limits" => [0.0, 12.0, 0.0, 12.0, -1.0, 2.0]),
        ],
    ))
    @test fig_view.content[1].attrs[:limits] == ((0.5, 5.5), (-2.0, 6.0))
    @test fig_view.content[1].attrs[:xgridvisible] == false
    # Linked axis ax2 inherits new X limits
    @test fig_view.content[2].attrs[:limits][1] == (0.5, 5.5)
    @test ax3.azimuth[] != 1.1  # snapshot clone does not mutate original
    svg_view = String(render(fig_view; format = :svg))
    @test startswith(lstrip(svg_view), "<svg") || contains(svg_view, "<svg")
    @test svg_view != svg_scripted

    fig_cb = Figure()
    Axis3(fig_cb[1, 1:2])
    Axis3(fig_cb[1, 3:4])
    axh = Axis(fig_cb[2, 1])
    hm = heatmap!(axh, 1:4, 1:4, rand(4, 4))
    Colorbar(fig_cb[2, 2], hm)
    axc = Axis(fig_cb[2, 3])
    cf = contourf!(axc, 1:4, 1:4, rand(4, 4))
    Colorbar(fig_cb[2, 4], cf)
    cb_spec, _ = scene_spec(fig_cb)
    @test [t["kind"] for t in cb_spec["layout"]["cols"]] == ["fr", "auto", "fr", "auto"]
end

@testset "Aqua" begin
    Aqua.test_all(SqueroPlot; ambiguities = (recursive = false,), persistent_tasks = false)
end

end
