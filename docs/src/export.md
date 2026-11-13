# Export

Every format is drawn from the figure model by Cairo, never captured from a screen.

```julia
save("figure.png", fig)                       # raster, px_per_unit = 2 (1200 × 900 for 600 × 450)
save("figure.svg", fig)                       # vector; text as glyph outlines
save("figure.pdf", fig)                       # vector; 1 unit = 0.75 pt (pt_per_unit)
save("figure.eps", fig)                       # vector (EPSF-3.0)
save("figure.html", fig)                      # a standalone page with the SVG inline

bytes = render(fig; format = :pdf)            # the same bytes, in memory
page = to_html(fig; interactive = true)       # + a small inline pan/zoom script
```

| Format | Kind | Header | Notes |
| --- | --- | --- | --- |
| PNG | raster | `\x89PNG` | `px_per_unit` scales the pixel size |
| SVG | vector | `<?xml … <svg` | has `<title>`, `<desc>` with the figure's text, `role="img"` |
| PDF | vector | `%PDF-` | fonts embedded (subset) |
| EPS | vector | `%!PS-Adobe-3.0 EPSF-3.0` | `%%BoundingBox` in points |
| HTML | vector | `<!DOCTYPE html>` | no external CSS, JS or fonts; opens offline |

Large regular heatmaps (more than 2500 cells) and `image` are embedded as raster images inside
the vector formats, as other plotting libraries do; everything else is paths.

Fonts are bundled (TeX Gyre Heros, DejaVu Sans for missing glyphs), so the output is the same on
every machine and in containers without fonts.
