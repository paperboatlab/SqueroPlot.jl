# Third-party notices

SqueroPlot does not depend on Makie. It keeps Makie's user-facing API shape and adapts a few
small pieces, each marked in the source:

| Piece | Source | Licence | Where |
| --- | --- | --- | --- |
| `stairs` step modes and `stem` (offset, trunk, stems, markers) | Makie.jl `basic_recipes/stairs.jl`, `stem.jl` | MIT, © 2018-2025 Simon Danisch, Julius Krumbiegel and contributors | `src/recipes.jl`, `src/render2d.jl` |
| Default theme values (Wong palette, 14 pt text, 600 × 450, gaps, Axis/Axis3 defaults) | Makie.jl `theming.jl`, `makielayout/types.jl` | MIT, as above | `src/theme.jl`, `src/figure.jl` |
| Wilkinson tick search (`optimize_ticks`) | PlotUtils.jl `ticks.jl` (from Gadfly.jl, Daniel C. Jones) | MIT, © 2016 Thomas Breloff and contributors | `src/ticks.jl` |
| Colour map samples | ColorSchemes.jl | MIT; matplotlib maps CC0; cmocean maps MIT | `src/colors.jl` |
| TeX Gyre Heros Makie (Regular, Bold) | Makie.jl assets (a renamed TeX Gyre Heros) | GUST Font License (LPPL 1.3c) | `assets/fonts/` |
| DejaVu Sans (fallback glyphs) | DejaVu fonts | Bitstream Vera licence; DejaVu changes public domain | `assets/fonts/` |

The font licences are reproduced in `assets/fonts/LICENSES.md`.

## Makie.jl (MIT)

> Copyright (c) 2018-2025: Simon Danisch, Julius Krumbiegel.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software
> and associated documentation files (the "Software"), to deal in the Software without
> restriction, including without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
> Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or
> substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
> BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
> NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## PlotUtils.jl (MIT)

> Copyright (c) 2016: Thomas Breloff.
>
> The same MIT permission notice as above applies.

## ColorSchemes.jl (MIT)

> Copyright (c) 2017-2025: cormullion and contributors.
>
> The same MIT permission notice as above applies.
