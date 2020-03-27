macro test_signature(function_def_expr)
    _target = splitdef(function_def_expr)
    delete!(_target, :head) # never look at :head
    delete!(_target, :body) # never looking at body
    ret = quote
        fun = $(esc(function_def_expr))
        meths = methods(fun)
        target = $(_target)
        if length(meths) > 1
            error("can only check signatures of functions with only one method")
        end
        sig = signature(first(meths))
    end
    for key in keys(_target)
        # interpolate in the `key` to make test results easy to read
        push!(
            ret.args,
            :(@test target[$(QuoteNode(key))] == get(sig, $(QuoteNode(key)), nothing)),
        )
    end
    return ret
end




@testset "method.jl: signature" begin
    @testset "Basics" begin
        @test_signature f1(x) = 2x
        @test_signature f2(x::Int64) = 2x
        @test_signature f3(x::Int64, y) = 2x
    end

    @testset "missing argnames" begin
        @test_signature ma1(::Int32) = 2x
        @test_signature ma2(::Int32, ::Bool) = 2x
        @test_signature ma3(x, ::Int32) = 2x
    end

    @testset "Whereparams" begin
        @test_signature f4(x::T, y::T) where T = 2x

        @test_signature f5(x::S, y::T) where {S,T} = 2x
        @test_signature f6(x::S, y::T) where {T,S} = 2x
        @test_signature f7(x::S, y::T) where T where S = 2x
    end

    @testset "Whereparams with constraints" begin
        @test_signature f8(x::S) where S<:Integer = 2x
        @test_signature f9(x::S, y::S) where S<:Integer = 2x
        @test_signature f10(x::S, y::T) where {S<:Integer, T<:Real} = 2x
        @test_signature f11(x::S, y::Int64) where S<:Integer = 2x

        @test_signature f12(x::S) where {S>:Integer} = 2x
        @test_signature f13(x::S) where Integer<:S<:Number = 2x
    end

    @testset "Arg types with type-parameters" begin
        @test_signature f14(x::Array{Int64, 1}) = 2x
        @test_signature f15(x::Array{T, 1}) where T = 2x

        # Note: we don't test: `f16(x::Array{<:Real, 1}) = 2x` as it lowers to same
        # method as below, but has a different AST according to `splitdef` so we can't
        # generate a solution that would unlower to two different AST for same method
        @test_signature f16(x::Array{T, 1} where T<:Real) = 2x

        #==
        # noncanonical form works
        old_sig = signature(first(methods(f16)))
        f16(x::Array{<:Real, 1} = 2x  # redefine it
        @assert length(methods(f16)) == 1  # no new method should have been created
        new_sig = signature(first(methods(f16)))
        ==#
    end

    @testset "anon functions" begin
        @test_signature (x)->2x
        # following is broken:
        # @test_signature ((::T) where T) -> 0

    end

    @testset "vararg" begin
        # we don't check `f18(xs...) = 2` as it lowers to the same method as below
        # but has a different AST according to `splitdef` so we can't
        # generate a solution that would unlower to two different AST for same method.
        @test_signature f17(xs::Vararg{Any, N} where N) = 2

        @test_signature f18(xs::Vararg{Int64, N} where N) = 2
        @test_signature f19(x, xs::Vararg{Any, N} where N) = 2x
    end

    @testset "kwargs" begin  # We do not support them right now
        #Following is broken:
        #@test_signature f17(x; y=3x) = 2x
    end
end

#==

julia> signature(first(methods(((::T) where T) -> 0)))  # Anonymous parameter
Dict{Symbol,Any} with 4 entries:
  :name        => Symbol("#35")
  :args        => Expr[:(var"#unused#"::T)]
  :head        => :function
  :whereparams => Any[:T]

julia> signature(first(methods((x=1) -> x)))  # Missing arg
Dict{Symbol,Any} with 3 entries:
  :name => Symbol("#42")
  :args => Union{Expr, Symbol}[]
  :head => :function

julia> signature(first(methods(Rational{Int8}, (Integer,))))  # No `:params`
Dict{Symbol,Any} with 4 entries:
  :name        => :Rational
  :args        => Expr[:(x::Integer)]
  :head        => :function
  :whereparams => Any[:(T <: Integer)]
  ==#
