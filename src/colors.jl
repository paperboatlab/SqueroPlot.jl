# Colours: parsing, the default palette, colour maps and their sampling.

"""`RGBf(r, g, b)`: an RGB colour with Float32 channels (as in Makie)."""
const RGBf = RGB{Float32}
"""`RGBAf(r, g, b, a)`: an RGBA colour with Float32 channels (as in Makie)."""
const RGBAf = RGBA{Float32}

"""
The Wong palette (Bang Wong, "Points of view: Color blindness", Nature Methods 2011), as Makie
uses it for its default cycle.
"""
const WONG = RGBAf[
    RGBAf(0 / 255, 114 / 255, 178 / 255, 1), RGBAf(230 / 255, 159 / 255, 0 / 255, 1),
    RGBAf(0 / 255, 158 / 255, 115 / 255, 1), RGBAf(204 / 255, 121 / 255, 167 / 255, 1),
    RGBAf(86 / 255, 180 / 255, 233 / 255, 1), RGBAf(213 / 255, 94 / 255, 0 / 255, 1),
    RGBAf(240 / 255, 228 / 255, 66 / 255, 1),
]

# 33 evenly spaced samples per map, taken from ColorSchemes.jl (MIT; the matplotlib maps are CC0,
# cmocean's `balance`/`thermal` are MIT). Sampling is linear between neighbouring entries.
const COLORMAP_DATA = Dict{Symbol, String}(
    :viridis => "#440154 #470D60 #48186A #482374 #472D7B #453681 #424086 #3F4989 #3B528B #375A8D #33638D #2F6A8E #2C728E #297A8E #26818E #23898E #21908C #1F988B #1F9F88 #21A685 #28AE80 #31B57B #3EBC74 #4CC26C #5DC963 #6ECE58 #82D34C #96D83F #ABDC32 #C0DF24 #D5E21A #EAE51A #FDE725",
    :plasma => "#0D0887 #220690 #310596 #3F049C #4C02A1 #5901A5 #6600A7 #7201A8 #7E03A8 #8909A6 #9511A2 #9F1A9C #A92396 #B22C8E #BB3587 #C33E80 #CB4778 #D25071 #D9596A #E06263 #E66C5C #EB7555 #F07F4F #F48A48 #F89441 #FB9F3A #FDAB33 #FEB72D #FDC328 #FCD025 #F9DD25 #F5EB27 #F0F921",
    :inferno => "#000004 #040312 #0B0724 #150B37 #210C4A #2E0A5A #3C0965 #4A0C6B #57106D #63146E #70196E #7D1E6D #89226A #962766 #A32B61 #AF315C #BB3755 #C63E4D #D14644 #DB4F3B #E35932 #EB6528 #F1711E #F67F14 #F98D0A #FB9C06 #FCAB0F #FBBA1F #F9CA32 #F5D949 #F2E865 #F3F586 #FCFFA4",
    :magma => "#000004 #030311 #0A0822 #130D33 #1D1146 #28115A #36106A #430F76 #50127C #5D177F #691C81 #762181 #822681 #8F2A81 #9C2E7F #A9327D #B63779 #C33B75 #CF4170 #DB486A #E65163 #EE5C5E #F5695C #F9785D #FB8761 #FD9668 #FEA571 #FEB47B #FEC387 #FED194 #FDE0A2 #FCEEB0 #FCFDBF",
    :cividis => "#00204D #00265A #002C68 #00306F #05366E #1E3C6D #2C426C #37476B #414D6B #4A536B #52596C #595E6D #61646F #686A71 #6F7073 #757676 #7C7B78 #848279 #8C8879 #948E78 #9C9477 #A49B76 #ACA174 #B4A872 #BDAF6F #C5B66C #CEBD68 #D7C463 #E0CB5E #E9D358 #F2DA50 #FBE248 #FFEA46",
    :turbo => "#30123B #392A73 #4040A1 #4456C7 #466BE3 #467FF6 #4293FF #37A7FA #29BBEC #1DCDD8 #18DCC3 #1EE8B0 #31F299 #4CF97E #6BFD64 #8AFF4D #A3FD3C #B8F735 #CCED34 #DEE037 #EDD03A #F8C03A #FDAE35 #FE982C #FB8022 #F56817 #EC520F #E04009 #D23105 #C02302 #AC1701 #950D01 #7A0403",
    :jet => "#00007F #00009F #0000BF #0000DF #0000FF #0020FF #003FFF #005FFF #007FFF #009FFF #00BFFF #00DFFF #00FFFF #20FFDF #3FFFBF #5FFF9F #7FFF7F #9FFF5F #BFFF3F #DFFF20 #FFFF00 #FFDF00 #FFBF00 #FF9F00 #FF7F00 #FF5F00 #FF3F00 #FF2000 #FF0000 #DF0000 #BF0000 #9F0000 #7F0000",
    :hot => "#0B0000 #200000 #340000 #490000 #5E0000 #730000 #880000 #9D0000 #B20000 #C70000 #DC0000 #F10000 #FF0700 #FF1C00 #FF3000 #FF4500 #FF5A00 #FF6F00 #FF8400 #FF9900 #FFAE00 #FFC300 #FFD800 #FFED00 #FFFF04 #FFFF23 #FFFF43 #FFFF62 #FFFF81 #FFFFA1 #FFFFC0 #FFFFE0 #FFFFFF",
    :cool => "#00FFFF #08F7FF #10EFFF #18E7FF #20DFFF #28D7FF #30CFFF #38C7FF #40BFFF #48B7FF #50AFFF #58A7FF #609FFF #6897FF #708FFF #7887FF #8080FF #8778FF #8F70FF #9768FF #9F60FF #A758FF #AF50FF #B748FF #BF40FF #C738FF #CF30FF #D728FF #DF20FF #E718FF #EF10FF #F708FF #FF00FF",
    :grays => "#000000 #030303 #090909 #121111 #191919 #212121 #292828 #302F2F #373736 #3E3E3D #454545 #4D4C4C #545353 #5B5A5A #626261 #6A6969 #717170 #797878 #80807F #888887 #90908F #989897 #A0A09F #A9A8A8 #B1B1B0 #BABAB9 #C3C3C2 #CCCCCB #D6D6D5 #E0E0DE #EAEAE8 #F4F4F3 #FFFFFD",
    :RdBu => "#67001F #7E0823 #960F27 #AD162A #BB2A34 #C6403E #D25749 #DC6D57 #E58268 #EE9878 #F5AC8B #F8BDA0 #FBCDB6 #FDDDCA #FBE5D9 #F9EEE8 #F7F7F7 #EBF1F5 #DFECF3 #D3E6F0 #C1DDEB #AED3E6 #9AC9E0 #83BCD9 #6AACD0 #529CC8 #3F8DC0 #347FB9 #2A71B2 #1F63A7 #165290 #0E4178 #053061",
    :balance => "#181C43 #20275B #263276 #293C93 #2548AF #1059BE #0E6ABD #2379BB #3887BA #4D95BA #64A2BC #7DADBF #96B9C5 #AFC5CD #C6D1D6 #DDDFE1 #F1ECEC #E9DBD7 #E3C8C0 #DDB5A9 #D7A392 #D2917B #CC7F65 #C66C4F #C0593C #B9452C #AF3024 #A11D25 #8F1029 #7B0E29 #650F24 #500D1C #3C0912",
    :thermal => "#042333 #052943 #082E54 #0E3167 #18337C #273491 #39339E #49369F #563B9C #614098 #6C4695 #774B91 #824F8F #8D548C #98588A #A45B86 #B05F82 #BC637D #C86676 #D36B6E #DE7065 #E8765B #F07E51 #F58748 #F99242 #FB9E3E #FCAB3C #FBB83D #F9C541 #F7D246 #F3DF4C #EEED53 #E8FA5B",
    :coolwarm => "#3B4CC0 #445ACC #4E68D7 #5775E1 #6282EA #6C8EF1 #779AF7 #82A5FB #8DB0FE #98B9FF #A3C2FE #AEC9FD #B8D0F9 #C2D5F4 #CCD9ED #D4DBE6 #DDDCDC #E5D8D1 #ECD3C5 #F1CCB9 #F4C4AD #F7BBA0 #F7B194 #F6A687 #F49A7B #F18D6F #EC7F63 #E57058 #DE604D #D55042 #CB3D38 #C0282F #B40426",
    :Blues => "#F7FBFF #F1F7FD #EBF3FB #E4EFF9 #DEEBF7 #D8E7F5 #D2E3F3 #CCDFF1 #C6DBEF #BCD7EB #B2D2E8 #A8CEE4 #9ECAE1 #91C3DE #84BCDC #78B5D9 #6BAED6 #61A7D2 #56A0CE #4C99CA #4292C6 #3A8AC2 #3282BE #2979B9 #2171B5 #1B69AF #1461A9 #0E59A2 #08519C #084990 #084084 #083877 #08306B",
    :Reds => "#FFF5F0 #FFF0E8 #FEEBE1 #FEE5DA #FEE0D2 #FED7C6 #FDCEBA #FCC4AD #FCBBA1 #FCB195 #FCA68A #FC9C7E #FC9272 #FC8868 #FC7E5E #FB7454 #FB6A4A #F85E42 #F5523B #F24734 #EF3B2C #E63228 #DD2A24 #D42121 #CB181D #C2161B #B81419 #AE1117 #A50F15 #960B13 #860811 #76040F #67000D",
    :Greens => "#F7FCF5 #F2FAF0 #EEF9EB #EAF7E5 #E5F5E0 #DEF2D8 #D6EFD0 #CEECC8 #C7E9C0 #BEE5B7 #B4E1AE #AADDA4 #A1D99B #96D492 #8ACE88 #7FC97F #74C476 #67BE70 #5AB86A #4EB163 #41AB5D #39A357 #329B51 #2B934B #238B45 #1A843F #127C38 #097432 #006D2C #006328 #005824 #004E1F #00441B",
)

const COLORMAP_ALIASES = Dict{Symbol, Symbol}(
    :gray => :grays, :grey => :grays, :greys => :grays, :Greys => :grays, :Grays => :grays,
    :rdbu => :RdBu, :blues => :Blues, :reds => :Reds, :greens => :Greens,
)

const COLORMAPS = Dict{Symbol, Vector{RGBAf}}()

"""A colour map in reverse order: `Reverse(:viridis)`."""
struct Reverse{T}
    data::T
end

"""The names `colormap = …` accepts."""
available_colormaps() = sort!(collect(union(keys(COLORMAP_DATA), keys(COLORMAP_ALIASES))))

to_color(c::RGBAf) = c
to_color(c::Colorant) = RGBAf(c)
to_color(s::Symbol) = to_color(String(s))
function to_color(s::AbstractString)
    s == "transparent" && return RGBAf(0, 0, 0, 0)
    return RGBAf(parse(Colorant, s))
end
to_color((c, a)::Tuple{Any, Real}) = (rgba = to_color(c); RGBAf(red(rgba), green(rgba), blue(rgba), alpha(rgba) * a))
to_color(::Nothing) = RGBAf(0, 0, 0, 0)
to_color(x) = throw(ArgumentError("cannot use $(repr(x)) as a colour (a Symbol, String, Colorant or (colour, alpha))"))

with_alpha(c, a::Real) = (rgba = to_color(c); RGBAf(red(rgba), green(rgba), blue(rgba), alpha(rgba) * a))

"""Mix two colours: `t = 0` gives `a`, `t = 1` gives `b`."""
function lerp(a::RGBAf, b::RGBAf, t::Real)
    t = Float32(t)
    return RGBAf(red(a) + (red(b) - red(a)) * t, green(a) + (green(b) - green(a)) * t,
        blue(a) + (blue(b) - blue(a)) * t, alpha(a) + (alpha(b) - alpha(a)) * t)
end

function to_colormap(cm::Symbol)
    key = haskey(COLORMAP_DATA, cm) ? cm : get(COLORMAP_ALIASES, cm, cm)
    haskey(COLORMAP_DATA, key) || throw(ArgumentError("unknown colormap :$cm; available: $(join(available_colormaps(), ", "))"))
    return get!(COLORMAPS, key) do
        RGBAf[to_color(h) for h in split(COLORMAP_DATA[key])]
    end
end
to_colormap(cm::AbstractString) = to_colormap(Symbol(cm))
to_colormap(cm::Reverse) = reverse(to_colormap(cm.data))
to_colormap(cm::AbstractVector) = RGBAf[to_color(c) for c in cm]
to_colormap((cm, a)::Tuple{Any, Real}) = [with_alpha(c, a) for c in to_colormap(cm)]

"""Sample a colour map at `t ∈ [0, 1]`."""
function sample(cmap::Vector{RGBAf}, t::Real)
    n = length(cmap)
    n == 1 && return cmap[1]
    isfinite(t) || return RGBAf(0, 0, 0, 0)
    x = clamp(Float64(t), 0.0, 1.0) * (n - 1) + 1
    i = min(floor(Int, x), n - 1)
    return lerp(cmap[i], cmap[i + 1], x - i)
end

"""Map `v` through `cmap` over `range = (lo, hi)`; NaN maps to `nan_color`."""
function colormap_value(cmap, v::Real, range; nan_color = RGBAf(0, 0, 0, 0))
    isfinite(v) || return nan_color
    lo, hi = range
    t = hi == lo ? 0.5 : (v - lo) / (hi - lo)
    return sample(cmap, t)
end

"""The finite extrema of `values`, or `(0, 1)` when there are none."""
function finite_extrema(values)
    lo, hi = Inf, -Inf
    for v in values
        v isa Real && isfinite(v) || continue
        lo = min(lo, v)
        hi = max(hi, v)
    end
    return isfinite(lo) ? (Float64(lo), Float64(hi)) : (0.0, 1.0)
end
