# Export: one drawing pass per format, straight from the figure model (never a screen capture).
# PNG is a raster at `px_per_unit`; SVG, PDF and EPS are vector (1 unit = `pt_per_unit` points
# in PDF/EPS, 1 user unit in SVG). HTML is a standalone page with the SVG inline.

const FORMATS = (:png, :svg, :pdf, :eps, :html)

"""The format of a file name: `.png`, `.svg`, `.pdf`, `.eps`, `.html`/`.htm`."""
function format_of(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    ext == ".htm" && return :html
    f = Symbol(lstrip(ext, '.'))
    f in FORMATS || throw(ArgumentError("cannot tell the format of \"$path\"; use .png, .svg, .pdf, .eps or .html"))
    return f
end

"""Draw the whole figure onto a Cairo context in figure units."""
function draw_figure(ctx::Ctx, fig::Figure)
    states, rects = layout_figure(fig)
    if alpha(fig.backgroundcolor) > 0
        new_path(ctx)
        rectangle(ctx, 0, 0, fig.size...)
        set_color(ctx, fig.backgroundcolor)
        fillpath(ctx)
    end
    for b in fig.content
        haskey(rects, b) || continue
        draw_block(ctx, b, rects[b], states[b])
    end
    return nothing
end

"""
    render(fig; format = :png, px_per_unit = 2, pt_per_unit = 0.75) -> Vector{UInt8}

The figure as file bytes: `:png`, `:svg`, `:pdf`, `:eps` or `:html`.
"""
function render(fig::Figure; format::Symbol = :png, px_per_unit::Real = 2, pt_per_unit::Real = 0.75, title = nothing)
    format in FORMATS || throw(ArgumentError("unknown format :$format; use one of $(join(FORMATS, ", "))"))
    format === :html && return Vector{UInt8}(to_html(fig; title = title))
    w, h = fig.size
    io = IOBuffer()
    if format === :png
        surface = Cairo.CairoARGBSurface(max(1, round(Int, w * px_per_unit)), max(1, round(Int, h * px_per_unit)))
        ctx = context(surface)
        scale(ctx, px_per_unit, px_per_unit)
        draw_figure(ctx, fig)
        Cairo.write_to_png(surface, io)
        Cairo.finish(surface)
        return take!(io)
    end
    surface = format === :svg ? Cairo.CairoSVGSurface(io, w, h) :
              format === :pdf ? Cairo.CairoPDFSurface(io, w * pt_per_unit, h * pt_per_unit) :
              Cairo.CairoEPSSurface(io, w * pt_per_unit, h * pt_per_unit)
    ctx = context(surface)
    format === :svg || scale(ctx, pt_per_unit, pt_per_unit)
    draw_figure(ctx, fig)
    Cairo.finish(surface)
    bytes = take!(io)
    return format === :svg ? Vector{UInt8}(annotate_svg(String(bytes), fig)) : bytes
end
render(fap::FigureAxisPlot; kwargs...) = render(fap.figure; kwargs...)

"""
    save(path, fig; px_per_unit = 2, pt_per_unit = 0.75) -> path
    save(path, snapshot) -> path

Write the figure (or a stored snapshot) to `path`; the format comes from the extension.
"""
function save(path::AbstractString, fig::Figure; format::Symbol = format_of(path), kwargs...)
    bytes = render(fig; format = format, kwargs...)
    mkpath(dirname(abspath(path)))
    write(path, bytes)
    return path
end
save(path::AbstractString, fap::FigureAxisPlot; kwargs...) = save(path, fap.figure; kwargs...)

_escape(s) = replace(String(s), '&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '"' => "&quot;")

"""Every text a figure shows, for the SVG's `<desc>` (Cairo writes glyphs as paths)."""
function figure_texts(fig::Figure)
    out = String[]
    add(s) = (s === nothing || is_empty_text(s)) || push!(out, plaintext(s))
    for b in fig.content
        a = getfield(b, :attrs)
        if b isa Axis
            foreach(k -> add(a[k]), (:title, :subtitle, :xlabel, :ylabel))
        elseif b isa Axis3
            foreach(k -> add(a[k]), (:title, :xlabel, :ylabel, :zlabel))
        elseif b isa Colorbar
            add(a[:label])
        elseif b isa Label
            add(a[:text])
        end
        if b isa AbstractAxis
            for p in b.plots
                pa = getfield(p, :attrs)
                add(get(pa, :label, nothing))
                kind(p) === :text && (t = pa[:text]; t isa AbstractVector ? foreach(add, t) : add(t))
            end
        end
    end
    return unique(out)
end

"""Add a `<title>` and `<desc>` (the figure's text) and an ARIA label to Cairo's SVG."""
function annotate_svg(svg::String, fig::Figure)
    m = match(r"<svg\b[^>]*>", svg)
    m === nothing && return svg
    t = _escape(title(fig))
    desc = _escape(join(figure_texts(fig), " | "))
    head = replace(m.match, r">$" => " role=\"img\" aria-label=\"$(t)\">")
    inject = "\n<title>$(t)</title>\n<desc>$(desc)</desc>"
    return svg[1:(m.offset - 1)] * head * inject * svg[(m.offset + length(m.match)):end]
end

const PANZOOM = """
<script>
(() => {
  const svg = document.querySelector("main svg");
  if (!svg) return;
  const base = svg.viewBox.baseVal;
  const home = [base.x, base.y, base.width, base.height];
  let drag = null;
  const set = (x, y, w, h) => svg.setAttribute("viewBox", x + " " + y + " " + w + " " + h);
  svg.addEventListener("wheel", (e) => {
    e.preventDefault();
    const r = svg.getBoundingClientRect(), v = svg.viewBox.baseVal;
    const k = e.deltaY < 0 ? 0.9 : 1.1;
    const px = v.x + (e.clientX - r.left) / r.width * v.width, py = v.y + (e.clientY - r.top) / r.height * v.height;
    set(px - (px - v.x) * k, py - (py - v.y) * k, v.width * k, v.height * k);
  }, { passive: false });
  svg.addEventListener("pointerdown", (e) => { drag = [e.clientX, e.clientY]; svg.setPointerCapture(e.pointerId); });
  svg.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const r = svg.getBoundingClientRect(), v = svg.viewBox.baseVal;
    set(v.x - (e.clientX - drag[0]) / r.width * v.width, v.y - (e.clientY - drag[1]) / r.height * v.height, v.width, v.height);
    drag = [e.clientX, e.clientY];
  });
  svg.addEventListener("pointerup", () => { drag = null; });
  svg.addEventListener("dblclick", () => set(...home));
})();
</script>"""

"""A standalone HTML page around an SVG document (no external CSS, JS or fonts)."""
function html_page(svg::String; title::AbstractString = "", interactive::Bool = false)
    body = replace(svg, r"^<\?xml[^>]*\?>\s*" => "")
    t = _escape(title)
    script = interactive ? PANZOOM : ""
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="generator" content="SqueroPlot">
    <title>$(isempty(t) ? "Figure" : t)</title>
    <style>
    html, body { margin: 0; background: #ffffff; }
    main { display: flex; justify-content: center; padding: 16px; }
    main svg { max-width: 100%; height: auto; touch-action: none; }
    </style>
    </head>
    <body>
    <main>
    $(body)
    </main>$(script)
    </body>
    </html>
    """
end

"""
    to_html(fig; title = title(fig), interactive = false) -> String

A standalone HTML document with the figure as inline SVG: vector, no network access, no external
CSS/JS/fonts. `interactive = true` adds a small inline script for wheel zoom, drag pan and
double-click reset.
"""
function to_html(fig::Figure; title = nothing, interactive::Bool = false)
    svg = String(render(fig; format = :svg))
    return html_page(svg; title = something(title, SqueroPlot.title(fig)), interactive = interactive)
end
to_html(fap::FigureAxisPlot; kwargs...) = to_html(fap.figure; kwargs...)

# Display in notebooks, VS Code and Documenter.
Base.showable(::MIME"image/png", ::Union{Figure, FigureAxisPlot}) = true
Base.showable(::MIME"image/svg+xml", ::Union{Figure, FigureAxisPlot}) = true
Base.show(io::IO, ::MIME"image/png", fig::Figure) = write(io, render(fig; format = :png))
Base.show(io::IO, ::MIME"image/svg+xml", fig::Figure) = write(io, render(fig; format = :svg))
Base.show(io::IO, m::MIME"image/png", f::FigureAxisPlot) = show(io, m, f.figure)
Base.show(io::IO, m::MIME"image/svg+xml", f::FigureAxisPlot) = show(io, m, f.figure)

function Base.show(io::IO, fig::Figure)
    w, h = round.(Int, fig.size)
    print(io, "Figure(", w, "×", h, ", ", axes_count(fig), " axes, ", plot_count(fig), " plots)")
end
Base.show(io::IO, ::MIME"text/plain", fig::Figure) = show(io, fig)
Base.show(io::IO, f::FigureAxisPlot) = show(io, f.figure)
Base.show(io::IO, ::MIME"text/plain", f::FigureAxisPlot) = show(io, f.figure)
