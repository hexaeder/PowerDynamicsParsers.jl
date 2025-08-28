using PowerDynamicsParsers
using Documenter
using Literate

DocMeta.setdocmeta!(PowerDynamicsParsers, :DocTestSetup, :(using PowerDynamicsParsers); recursive=true)

# Generate examples using Literate
example_dir = joinpath(@__DIR__, "examples")
outdir = joinpath(@__DIR__, "src", "generated")
isdir(outdir) && rm(outdir, recursive=true)
mkpath(outdir)

for example in filter(contains(r".jl$"), readdir(example_dir, join=true))
    Literate.markdown(example, outdir;
                      preprocess=c->replace(c, "@hover " => ""))
end
function preprocess_html_hover(c)
    replace(c, r"^(\s*)@hover\s+(.*)$"m => s"""
    \1\2
    #-
    PowerDynamicsParsers.CGMES.html_hover_map() #hide
    #-
    """)
end
function preprocess_script(c)
    no_hover = replace(c, r"^(\s*)@hover\s+(.*)$"m => s"""
    \1\2
    """)
    replace(no_hover, r"^\s*@collapse_codeblock.*\n?"m => "")
end

function collapsible_code_cell(c)
    regex =  r"^````(.*)\n\s*@collapse_codeblock(?:\s*\"(.*)\")?\s*\n"m
    new = replace(c, regex => function(full_match)
        # need to match again becaus full match isa SubString
        m = match(regex, full_match)
        example = m[1]
        summary = isnothing(m[2]) ? "Expand hidden code block" : m[2]
        """
        ````@raw html
        <script>
        (function() {
            const thisScript = document.currentScript;
            setTimeout(function() {
                let current = thisScript.nextElementSibling;
                while (current) {
                    const code = current.querySelector('code');
                    if (code) {
                        const details = document.createElement('details');
                        const summary = document.createElement('summary');
                        summary.textContent = '$summary';
                        const parent = code.parentNode;
                        parent.parentNode.insertBefore(details, parent);
                        details.appendChild(summary);
                        details.appendChild(parent);
                        break;
                    }
                    current = current.nextElementSibling;
                }
            }, 100);
        })();
        </script>
        ````
        ````$example
        """
    end)

    if contains(new, "@collapse_codeblock")
        error("Could not expand @collapse_codeblock, are you sure it is at the beginning of a code block?")
    end
    new
end

# Process any .jl files in examples directory
if isdir(example_dir)
    for example in filter(contains(r".jl$"), readdir(example_dir, join=true))
        Literate.markdown(example, outdir;
            preprocess=preprocess_html_hover,
            postprocess=collapsible_code_cell,)
        Literate.script(example, outdir; preprocess=preprocess_script, keep_comments=true)
    end
end

# Build kwargs with strict and warn-only variants
kwargs = (;
    modules=[PowerDynamicsParsers],
    authors="Hans Würfel <git@wuerfel.io> and contributors",
    sitename="PowerDynamicsParsers.jl",
    root=joinpath(pkgdir(PowerDynamicsParsers), "docs"),
    linkcheck=true, # checks if external links resolve
    pagesonly=true,
    format=Documenter.HTML(;
        canonical="https://hexaeder.github.io/PowerDynamicsParsers.jl",
        edit_link="main",
        assets=String[],
        ansicolor = true,
        size_threshold=1_000_000_000
    ),
    pages=[
        "Home" => "index.md",
        "Tutorials" => [
            "Inspection of CGMES Test Data" => "generated/cgmes_testdata.md",
            "Wrong Powerflow data in CGMES Export" => "generated/cgmes_linemodel.md",
            "Reexported Dataset" => "generated/cgmes_testdata_reexport.md",
        ]
    ],
    draft=haskey(ENV, "DOCUMENTER_DRAFT"),
    warnonly=[:missing_docs],
)
kwargs_warnonly = (; kwargs..., warnonly=true)

# Build with strict mode first, fallback to warn-only on failure
if haskey(ENV,"GITHUB_ACTIONS")
    success = true
    thrown_ex = nothing
    try
        makedocs(; kwargs...)
    catch e
        @info "Strict doc build failed, try again with warnonly=true"
        global success = false
        global thrown_ex = e
        makedocs(; kwargs_warnonly...)
    end

    deploydocs(;
        repo="github.com/hexaeder/PowerDynamicsParsers.jl",
        devbranch="main",
        push_preview=true
    )

    success || throw(thrown_ex)
else # local build
    makedocs(; kwargs_warnonly...)
end
