using ExprTools
using Documenter

makedocs(;
    modules=[ExprTools],
    authors="Curtis Vogt <curtis.vogt@gmail.com>",
    repo="https://github.com/invenia/ExprTools.jl/blob/{commit}{path}#L{line}",
    sitename="ExprTools.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://invenia.github.io/ExprTools.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/invenia/ExprTools.jl",
)
