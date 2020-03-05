macro check_signature(function_def_expr)
    _target = splitdef(function_def_expr)
    _target[:head] = :function  # always make it a :function
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
        @check_signature f1(x) = 2x
        @check_signature f2(x::Int64) = 2x
        @check_signature f3(x::Int64, y) = 2x
    end

    @testset "Whereparams" begin
        @check_signature f4(x::T, y::T) where T = 2x

        @check_signature f5(x::S, y::T) where {S,T} = 2x
        @check_signature f6(x::S, y::T) where {T,S} = 2x
        @check_signature f7(x::S, y::T) where T where S = 2x
    end

    @testset "Whereparams with constraints" begin
        @check_signature f8(x::S) where S<:Integer = 2x
        @check_signature f9(x::S, y::S) where S<:Integer = 2x
        @check_signature f10(x::S, y::T) where {S<:Integer, T<:Real} = 2x
        @check_signature f11(x::S, y::Int64) where S<:Integer = 2x

        @check_signature f12(x::S) where {S>:Integer} = 2x
        @check_signature f13(x::S) where Integer<:S<:Number = 2x
    end

    @testset "Arg types with type-parameters" begin
        @check_signature f14(x::Array{Int64, 1}) = 2x
        @check_signature f15(x::Array{T, 1}) where T = 2x

        # Note: we don't test: `f16(x::Array{<:Real, 1}) = 2x` as it lowers to same
        # method as below, but has a different AST according to `splitdef` so we can't
        # generate a solution that would unlower to two different AST for same method
        @check_signature f16(x::Array{T, 1} where T<:Real) = 2x
    end

    @testset "anon functions" begin
        @check_signature (x)->2x
    end

    @testset "vararg" begin
        # we don't check `f18(xs...) = 2` as it lowers to the same method as below
        # but has a different AST according to `splitdef` so we can't
        # generate a solution that would unlower to two different AST for same method.
        @check_signature f17(xs::Vararg{Any, N} where N) = 2

        @check_signature f18(xs::Vararg{Int64, N} where N) = 2
        @check_signature f19(x, xs::Vararg{Any, N} where N) = 2x
    end

    @testset "kwargs" begin  # We do not support them right now
        #Following is broken:
        #@check_signature f17(x; y=3x) = 2x
    end
end
