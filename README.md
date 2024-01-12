# ExprTools

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://invenia.github.io/ExprTools.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://invenia.github.io/ExprTools.jl/dev)
[![CI](https://github.com/Invenia/ExprTools.jl/workflows/CI/badge.svg)](https://github.com/Invenia/ExprTools.jl/actions?query=workflow%3ACI)
[![Coverage](https://codecov.io/gh/invenia/ExprTools.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/invenia/ExprTools.jl)

ExprTools provides tooling for working with Julia expressions during [metaprogramming](https://docs.julialang.org/en/v1/manual/metaprogramming/).
This package aims to provide light-weight performant tooling without requiring additional package dependencies.

Currently, this package provides the `splitdef`, `signature` and `combinedef` functions which are useful for inspecting and manipulating function definition expressions.
 - `splitdef` works on a function definition expression and returns a `Dict` of its parts.
 - `combinedef` takes a `Dict` from `splitdef` and builds it into an expression.
 - `signature` works on a `Method`, or the type-tuple `sig` field of a method, returning a similar `Dict` that holds the parts of the expressions that would form its signature.

As well as several helpers that are useful in combination with them.
 - `args_tuple_expr` applies to a `Dict` from `splitdef` or `signature` to generate an expression for a tuple of its arguments.
 - `parameters` which return the type-parameters of a type, and so is useful for working with the type-tuple that comes out of the `sig` field of a `Method`

e.g.
```julia
julia> using ExprTools

julia> ex = :(
           function Base.f(x::T, y::T) where T
               x + y
           end
       )
:(function Base.f(x::T, y::T) where T
      #= none:3 =#
      x + y
  end)

julia> def = splitdef(ex)
Dict{Symbol,Any} with 5 entries:
  :args        => Any[:(x::T), :(y::T)]
  :body        => quote…
  :name        => :(Base.f)
  :head        => :function
  :whereparams => Any[:T]


julia> def[:name] = :g;

julia> def[:head] = :(=);

julia> args_tuple_expr(def)
:((x, y))

julia> def[:body] = :(*($(args_tuple_expr(def))...));

julia> g_expr = combinedef(def)
:((g(x::T, y::T) where T) = (*)((x, y)...))

julia> eval(g_expr)
g (generic function with 1 method)

julia> g_method = first(methods(g))
g(x::T, y::T) where T in Main

julia> parameters(g_method.sig)
svec(typeof(g), T, T)

julia> signature(g_method)
Dict{Symbol, Any} with 3 entries:
  :name        => :g
  :args        => Expr[:(x::T), :(y::T)]
  :whereparams => Any[:T]
```

### JuliaCon 2021 Video
"ExprTools: Metaprogramming from reflection" by Frames White

[![YouTube Video](https://img.youtube.com/vi/CREWoLxpDMo/0.jpg)](https://www.youtube.com/watch?v=CREWoLxpDMo)
