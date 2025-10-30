using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES

DATA = joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data")

@testest "parse testdata" begin
    for (path, dirs, files) in walkdir(DATA)
        if any(endswith(".xml"), files)
            println("Parsing dataset $(replace(path, DATA * "/" => ""))")
            CIMDataset(path)
        end
    end
end
