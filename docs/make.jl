using PowerDynamicsCGMES
using Documenter

DocMeta.setdocmeta!(PowerDynamicsCGMES, :DocTestSetup, :(using PowerDynamicsCGMES); recursive=true)

makedocs(;
    modules=[PowerDynamicsCGMES],
    authors="Hans Würfel <git@wuerfel.io> and contributors",
    sitename="PowerDynamicsCGMES.jl",
    format=Documenter.HTML(;
        canonical="https://hexaeder.github.io/PowerDynamicsCGMES.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/hexaeder/PowerDynamicsCGMES.jl",
    devbranch="main",
)
