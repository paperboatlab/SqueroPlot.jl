# GUI snapshots

An application that shows figures (Squero Studio MX, a notebook, a dashboard) keeps *snapshots*:
rendered artifacts plus metadata. A snapshot never changes after it is taken, and it exports
without the live figure, so a history of figures survives the session that made them.

```julia
fig = Figure()
ax = Axis(fig[1, 1]; title = "Run 1")
lines!(ax, 1:10, rand(10))

snap = snapshot(fig; formats = (:png, :svg, :pdf, :eps))
snap.id        # "figure-1": the figure's id, in creation order (figure_id(fig))
snap.version   # a digest of the SVG: equal versions mean identical output
snap.title     # "Run 1": figure_title!/Figure(title=…), else the first axis title
snap.width, snap.height, snap.plots, snap.axes
snap.png       # bytes (a copy)
snap.svg       # a string
```

## Only what changed

`snapshot(fig; since = old.version)` returns `nothing` when the figure would draw the same, and
renders only the SVG to find out. A kernel can call it for every figure after each evaluation and
keep a new history entry only when something changed:

```julia
last = Dict{String, String}()
for fig in figures
    snap = snapshot(fig; formats = (:png, :svg, :pdf, :eps), since = get(last, figure_id(fig), nothing))
    snap === nothing && continue
    last[snap.id] = snap.version
    store(snap)
end
```

## Exporting history

```julia
save_snapshot(snap, :pdf)          # bytes of a stored artifact
save_snapshot(snap, :html)         # a standalone page built from the stored SVG
save("run1.svg", snap)             # write it
```

The figure can be changed, closed or gone; `save_snapshot` only reads the snapshot.

## Helpers

- `figure_id(fig)`: a stable id for the figure in this session.
- `figure_version(fig)`: the digest the next snapshot would get.
- `title(fig)`, `plot_count(fig)`, `axes_count(fig)`: metadata for a history list.
