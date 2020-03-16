# ExprTools

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://invenia.github.io/ExprTools.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://invenia.github.io/ExprTools.jl/dev)
[![Build Status](https://travis-ci.com/invenia/ExprTools.jl.svg?branch=master)](https://travis-ci.com/invenia/ExprTools.jl)
[![Coverage](https://codecov.io/gh/invenia/ExprTools.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/invenia/ExprTools.jl)

ExprTools provides tooling for working with Julia expressions during [metaprogramming](https://docs.julialang.org/en/v1/manual/metaprogramming/).
This package aims to provide light-weight performant tooling without requiring additional package dependencies.

Alternatively see the [MacroTools](https://github.com/MikeInnes/MacroTools.jl) package for a more powerful set of tools.

Currently, this package provides the `splitdef` and `combinedef` functions which are useful for inspecting and manipulating function definition expressions.

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

julia> def[:body] = :(x * y);

julia> combinedef(def)
:((g(x::T, y::T) where T) = x * y)
```
