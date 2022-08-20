# ExprTools

ExprTools provides tooling for working with Julia expressions during [metaprogramming](https://docs.julialang.org/en/v1/manual/metaprogramming/).
This package aims to provide light-weight performant tooling without requiring additional package dependencies.

Alternatively see the [MacroTools](https://github.com/MikeInnes/MacroTools.jl) package for more powerful set of tools.

Currently, this package provides the `splitdef`, `signature` and `combinedef` functions which are useful for inspecting and manipulating function definition expressions.
 - [`splitdef`](@ref) works on a function definition expression and returns a `Dict` of its parts.
 - [`combinedef`](@ref) takes `Dict` from `splitdef` and builds it into an expression.
 - [`signature`](@ref) works on a `Method` returning a similar `Dict` that holds the parts of the expressions that would form its signature.

e.g.
```jldoctest
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

julia> def[:body] = :(x * y);

julia> g_expr = combinedef(def)
:((g(x::T, y::T) where T) = x * y)

julia> eval(g_expr)
g (generic function with 1 method)

julia> g_method = first(methods(g))
g(x::T, y::T) where T in Main

julia> signature(g_method)
Dict{Symbol,Any} with 3 entries:
  :name        => :g
  :args        => Expr[:(x::T), :(y::T)]
  :whereparams => Any[:T]
```
