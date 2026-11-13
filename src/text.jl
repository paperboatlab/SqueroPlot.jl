# Text: bundled fonts loaded through FreeType, per-glyph fallback, rich text (super/subscripts),
# measuring and drawing. Output never depends on the system's fonts.
#
# TeX Gyre Heros Makie is Makie.jl's modified TeX Gyre Heros (GUST Font License); DejaVu Sans
# (Bitstream Vera licence) covers what it lacks. See assets/fonts/LICENSES.md.

const FONT_DIR = normpath(joinpath(@__DIR__, "..", "assets", "fonts"))
const FONT_FILES = Dict(
    :regular => "TeXGyreHerosMakie-Regular.otf",
    :bold => "TeXGyreHerosMakie-Bold.otf",
    :fallback => "DejaVuSans.ttf",
)

mutable struct FontFace
    name::Symbol
    ft::Ptr{Cvoid}
    cairo::Ptr{Cvoid}
    glyphs::Dict{Char, Bool}
end

const FT_LIBRARY = Ref{Ptr{Cvoid}}(C_NULL)
const FACES = Dict{Symbol, FontFace}()
const MEASURE = Ref{Any}(nothing)
const FONT_LOCK = ReentrantLock()

function reset_fonts!()
    lock(FONT_LOCK) do
        empty!(FACES)
        FT_LIBRARY[] = C_NULL
        MEASURE[] = nothing
    end
    return nothing
end

function font_face(name::Symbol)
    name = name === :bold ? :bold : name === :fallback ? :fallback : :regular
    return lock(FONT_LOCK) do
        get!(FACES, name) do
            if FT_LIBRARY[] == C_NULL
                lib = Ref{Ptr{Cvoid}}(C_NULL)
                err = ccall((:FT_Init_FreeType, libfreetype), Cint, (Ref{Ptr{Cvoid}},), lib)
                err == 0 || error("FreeType failed to start ($err)")
                FT_LIBRARY[] = lib[]
            end
            path = joinpath(FONT_DIR, FONT_FILES[name])
            face = Ref{Ptr{Cvoid}}(C_NULL)
            err = ccall((:FT_New_Face, libfreetype), Cint, (Ptr{Cvoid}, Cstring, Clong, Ref{Ptr{Cvoid}}),
                FT_LIBRARY[], path, 0, face)
            err == 0 || error("cannot load the font $path ($err)")
            cface = ccall((:cairo_ft_font_face_create_for_ft_face, Cairo.libcairo), Ptr{Cvoid},
                (Ptr{Cvoid}, Cint), face[], 0)
            FontFace(name, face[], cface, Dict{Char, Bool}())
        end
    end
end

function has_glyph(f::FontFace, c::Char)
    return get!(f.glyphs, c) do
        ccall((:FT_Get_Char_Index, libfreetype), Cuint, (Ptr{Cvoid}, Culong), f.ft, UInt32(c)) != 0
    end
end

function measure_context()
    ctx = MEASURE[]
    ctx === nothing || return ctx::Ctx
    surface = Cairo.CairoARGBSurface(4, 4)
    ctx = context(surface)
    MEASURE[] = ctx
    return ctx
end

# ---------------------------------------------------------------------------------------------
# Rich text

"""A run of text with its own scale and baseline shift (in units of the font size)."""
struct RichPart
    text::String
    scale::Float64
    shift::Float64
    font::Union{Nothing, Symbol}
    color::Any
end

"""Text made of parts with their own size, shift, font and colour; build it with `rich`."""
struct RichText
    parts::Vector{RichPart}
end

_parts(s::AbstractString, scale, shift, font, color) = [RichPart(String(s), scale, shift, font, color)]
_parts(r::RichText, scale, shift, font, color) =
    [RichPart(p.text, p.scale * scale, shift + p.shift * scale, p.font === nothing ? font : p.font,
        p.color === nothing ? color : p.color) for p in r.parts]
_parts(x, scale, shift, font, color) = _parts(string(x), scale, shift, font, color)

"""
    rich(parts...; font = nothing, color = nothing)

Text made of parts: strings, `superscript(…)`, `subscript(…)` or nested `rich(…)`.
`rich("10", superscript("-3"))` draws 10⁻³. Works for titles, labels, tick labels and `text`.
"""
rich(parts...; font = nothing, color = nothing) =
    RichText(reduce(vcat, [_parts(p, 1.0, 0.0, font, color) for p in parts]; init = RichPart[]))
"""`superscript(text)`: smaller and raised, inside `rich(…)`."""
superscript(parts...; kw...) = (r = rich(parts...; kw...); RichText([RichPart(p.text, p.scale * 0.66, p.shift * 0.66 + 0.4, p.font, p.color) for p in r.parts]))
"""`subscript(text)`: smaller and lowered, inside `rich(…)`."""
subscript(parts...; kw...) = (r = rich(parts...; kw...); RichText([RichPart(p.text, p.scale * 0.66, p.shift * 0.66 - 0.25, p.font, p.color) for p in r.parts]))

Base.string(r::RichText) = join(p.text for p in r.parts)
Base.isempty(r::RichText) = all(p -> isempty(p.text), r.parts)
Base.show(io::IO, r::RichText) = print(io, "rich(", repr(string(r)), ")")
plaintext(s::AbstractString) = String(s)
plaintext(r::RichText) = string(r)
plaintext(x) = string(x)

const TextLike = Union{AbstractString, RichText}
is_empty_text(s) = s === nothing || isempty(s)

# ---------------------------------------------------------------------------------------------
# Layout of one line of text: glyph runs, each in the face that has its glyphs.

struct Glyphs
    face::FontFace
    text::String
    size::Float64
    dx::Float64
    dy::Float64
    color::Any
end

struct TextLine
    runs::Vector{Glyphs}
    width::Float64
    ascent::Float64
    descent::Float64
end

function _split_runs(s::String, primary::FontFace, fallback::FontFace)
    out = Tuple{FontFace, String}[]
    isempty(s) && return out
    buf = IOBuffer()
    current = nothing
    for c in s
        f = (has_glyph(primary, c) || !has_glyph(fallback, c)) ? primary : fallback
        if current !== nothing && f !== current
            push!(out, (current, String(take!(buf))))
        end
        current = f
        print(buf, c)
    end
    push!(out, (current, String(take!(buf))))
    return out
end

function layout_text(text, size::Real, font::Symbol = :regular)
    ctx = measure_context()
    parts = text isa RichText ? text.parts : [RichPart(plaintext(text), 1.0, 0.0, nothing, nothing)]
    runs = Glyphs[]
    x = 0.0
    ascent = descent = 0.0
    fallback = font_face(:fallback)
    for part in parts
        psize = size * part.scale
        primary = font_face(something(part.font, font))
        shift = part.shift * size
        set_font_face(ctx, primary.cairo)
        set_font_size(ctx, psize)
        a, d = font_extents(ctx)
        ascent = max(ascent, a * 0.8 + shift)  # cap-height-ish, so labels sit tight
        descent = max(descent, d * 0.8 - shift)
        for (face, piece) in _split_runs(part.text, primary, fallback)
            set_font_face(ctx, face.cairo)
            set_font_size(ctx, psize)
            w = text_advance(ctx, piece)
            push!(runs, Glyphs(face, piece, psize, x, -shift, part.color))
            x += w
        end
    end
    if isempty(parts) || all(p -> isempty(p.text), parts)
        return TextLine(Glyphs[], 0.0, 0.0, 0.0)
    end
    return TextLine(runs, x, ascent, descent)
end

text_size(text, size, font = :regular) = (l = layout_text(text, size, font); (l.width, l.ascent + l.descent))
text_height(size) = size * 1.0

const HALIGN = Dict(:left => 0.0, :center => 0.5, :right => 1.0)

"""
Draw `text` anchored at `(x, y)`: `halign` is `:left`/`:center`/`:right` (or a fraction),
`valign` is `:bottom`/`:center`/`:top`/`:baseline`. `rotation` is counter-clockwise, in radians.
"""
function draw_text(ctx::Ctx, text, x, y; size = 14.0, font::Symbol = :regular, color = :black,
        halign = :left, valign = :baseline, rotation = 0.0)
    is_empty_text(text) && return nothing
    line = layout_text(text, size, font)
    fx = halign isa Real ? Float64(halign) : HALIGN[halign]
    base = valign === :top ? line.ascent :
           valign === :center ? (line.ascent - line.descent) / 2 :
           valign === :bottom ? -line.descent : 0.0
    gsave(ctx)
    translate(ctx, x, y)
    rotation == 0 || rotate(ctx, -rotation)
    for run in line.runs
        set_font_face(ctx, run.face.cairo)
        set_font_size(ctx, run.size)
        set_color(ctx, something(run.color, color))
        move_to(ctx, -fx * line.width + run.dx, base + run.dy)
        show_text(ctx, run.text)
    end
    new_path(ctx)
    grestore(ctx)
    return nothing
end
