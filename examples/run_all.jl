# Run every example: julia --project=. examples/run_all.jl   (from the package folder)
for file in sort(filter(f -> occursin(r"^\d\d_.*\.jl$", f), readdir(@__DIR__)))
    t = time()
    include(joinpath(@__DIR__, file))
    println(rpad(file, 32), round(time() - t; digits = 2), " s")
end
println("output in ", joinpath(@__DIR__, "out"))
