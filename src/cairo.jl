# Thin wrappers over libcairo. Surfaces, PNG writing and `finish` come from Cairo.jl; the drawing
# calls go straight to the C library so the renderer has one small, explicit vocabulary.

"""
A cairo_t. Not Cairo.jl's `CairoContext`: that one also makes a Pango layout, which starts Pango
and fontconfig (a scan of the system's fonts, about a second per process). Text here is drawn
with the bundled fonts through FreeType, so Pango is never needed.
"""
mutable struct Ctx
    ptr::Ptr{Cvoid}
    surface::Any   # keeps the surface alive as long as the context
end

function context(surface)
    ptr = ccall((:cairo_create, Cairo.libcairo), Ptr{Cvoid}, (Ptr{Cvoid},), surface.ptr)
    ctx = Ctx(ptr, surface)
    finalizer(ctx) do c
        c.ptr == C_NULL || ccall((:cairo_destroy, Cairo.libcairo), Cvoid, (Ptr{Cvoid},), c.ptr)
        c.ptr = C_NULL
    end
    return ctx
end

macro cairo(name, argtypes, args...)
    sym = QuoteNode(Symbol("cairo_", name))
    types = Expr(:tuple, :(Ptr{Cvoid}), argtypes.args...)
    return esc(:(ccall(($sym, Cairo.libcairo), Cvoid, $types, ctx.ptr, $(args...))))
end

move_to(ctx::Ctx, x, y) = @cairo(move_to, (Cdouble, Cdouble), x, y)
line_to(ctx::Ctx, x, y) = @cairo(line_to, (Cdouble, Cdouble), x, y)
curve_to(ctx::Ctx, x1, y1, x2, y2, x3, y3) =
    @cairo(curve_to, (Cdouble, Cdouble, Cdouble, Cdouble, Cdouble, Cdouble), x1, y1, x2, y2, x3, y3)
close_path(ctx::Ctx) = @cairo(close_path, ())
new_path(ctx::Ctx) = @cairo(new_path, ())
new_sub_path(ctx::Ctx) = @cairo(new_sub_path, ())
rectangle(ctx::Ctx, x, y, w, h) = @cairo(rectangle, (Cdouble, Cdouble, Cdouble, Cdouble), x, y, w, h)
arc(ctx::Ctx, x, y, r, a1, a2) = @cairo(arc, (Cdouble, Cdouble, Cdouble, Cdouble, Cdouble), x, y, r, a1, a2)
stroke(ctx::Ctx) = @cairo(stroke, ())
stroke_preserve(ctx::Ctx) = @cairo(stroke_preserve, ())
fillpath(ctx::Ctx) = @cairo(fill, ())
fill_preserve(ctx::Ctx) = @cairo(fill_preserve, ())
paint(ctx::Ctx) = @cairo(paint, ())
clip(ctx::Ctx) = @cairo(clip, ())
gsave(ctx::Ctx) = @cairo(save, ())
grestore(ctx::Ctx) = @cairo(restore, ())
translate(ctx::Ctx, x, y) = @cairo(translate, (Cdouble, Cdouble), x, y)
rotate(ctx::Ctx, a) = @cairo(rotate, (Cdouble,), a)
scale(ctx::Ctx, sx, sy) = @cairo(scale, (Cdouble, Cdouble), sx, sy)
set_line_width(ctx::Ctx, w) = @cairo(set_line_width, (Cdouble,), w)
set_line_cap(ctx::Ctx, cap::Integer) = @cairo(set_line_cap, (Cint,), cap)
set_line_join(ctx::Ctx, join::Integer) = @cairo(set_line_join, (Cint,), join)
set_antialias(ctx::Ctx, a::Integer) = @cairo(set_antialias, (Cint,), a)
set_font_size(ctx::Ctx, s) = @cairo(set_font_size, (Cdouble,), s)
set_font_face(ctx::Ctx, face::Ptr{Cvoid}) = @cairo(set_font_face, (Ptr{Cvoid},), face)
show_text(ctx::Ctx, s::AbstractString) = @cairo(show_text, (Cstring,), String(s))

const CAP_BUTT, CAP_ROUND, CAP_SQUARE = 0, 1, 2
const JOIN_MITER, JOIN_ROUND, JOIN_BEVEL = 0, 1, 2

function set_dash(ctx::Ctx, dashes::Vector{Float64}, offset = 0.0)
    ccall((:cairo_set_dash, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cdouble}, Cint, Cdouble),
        ctx.ptr, dashes, length(dashes), offset)
end

set_color(ctx::Ctx, c) = (rgba = to_color(c);
    @cairo(set_source_rgba, (Cdouble, Cdouble, Cdouble, Cdouble), red(rgba), green(rgba), blue(rgba), alpha(rgba)))

"""The x advance of `s` in the current font, in user units."""
function text_advance(ctx::Ctx, s::AbstractString)
    ext = zeros(Cdouble, 6)
    ccall((:cairo_text_extents, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Cstring, Ptr{Cdouble}), ctx.ptr, String(s), ext)
    return ext[5]
end

"""`(ascent, descent)` of the current font, in user units."""
function font_extents(ctx::Ctx)
    ext = zeros(Cdouble, 5)
    ccall((:cairo_font_extents, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cdouble}), ctx.ptr, ext)
    return ext[1], ext[2]
end

# Patterns: a linear gradient (colour bars) and a surface source (rasters).
function linear_gradient(ctx::Ctx, x0, y0, x1, y1, stops)
    pat = ccall((:cairo_pattern_create_linear, Cairo.libcairo), Ptr{Cvoid},
        (Cdouble, Cdouble, Cdouble, Cdouble), x0, y0, x1, y1)
    for (t, c) in stops
        ccall((:cairo_pattern_add_color_stop_rgba, Cairo.libcairo), Cvoid,
            (Ptr{Cvoid}, Cdouble, Cdouble, Cdouble, Cdouble, Cdouble), pat, t, red(c), green(c), blue(c), alpha(c))
    end
    ccall((:cairo_set_source, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), ctx.ptr, pat)
    ccall((:cairo_pattern_destroy, Cairo.libcairo), Cvoid, (Ptr{Cvoid},), pat)
    return nothing
end

"""Paint `pixels` (premultiplied ARGB32, `h × w`, row = y) into the rectangle `x, y, w, h`."""
function draw_raster(ctx::Ctx, pixels::Matrix{UInt32}, x, y, w, h; smooth::Bool = false)
    rows, cols = size(pixels)
    (rows == 0 || cols == 0 || w == 0 || h == 0) && return
    surface = Cairo.CairoImageSurface(pixels, Cairo.FORMAT_ARGB32; flipxy = true)
    gsave(ctx)
    rectangle(ctx, x, y, w, h)
    clip(ctx)
    translate(ctx, x, y)
    scale(ctx, w / cols, h / rows)
    ccall((:cairo_set_source_surface, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Cdouble, Cdouble),
        ctx.ptr, surface.ptr, 0.0, 0.0)
    pat = ccall((:cairo_get_source, Cairo.libcairo), Ptr{Cvoid}, (Ptr{Cvoid},), ctx.ptr)
    ccall((:cairo_pattern_set_filter, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Cint), pat,
        smooth ? Cairo.FILTER_BILINEAR : Cairo.FILTER_NEAREST)
    ccall((:cairo_pattern_set_extend, Cairo.libcairo), Cvoid, (Ptr{Cvoid}, Cint), pat, Cairo.EXTEND_PAD)
    paint(ctx)
    grestore(ctx)
    Cairo.finish(surface)
    return nothing
end

function argb32(c)
    a = alpha(c)
    q(v) = UInt32(round(clamp(v, 0, 1) * 255))
    return (q(a) << 24) | (q(red(c) * a) << 16) | (q(green(c) * a) << 8) | q(blue(c) * a)
end
