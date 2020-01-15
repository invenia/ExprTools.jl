# ExprTools

ExprTools provides tooling for working with Julia expressions during [metaprogramming](https://docs.julialang.org/en/v1/manual/metaprogramming/).
This package aims to provide light-weight performant tooling without requiring additional package dependencies.

Alternatively see the [MacroTools](https://github.com/MikeInnes/MacroTools.jl) package for more powerful set of tools.

Currently, this package provides the `splitdef` and `combinedef` functions which are useful for inspecting and manipulating function definition expressions.

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

julia> combinedef(def)
:((g(x::T, y::T) where T) = x * y)
```