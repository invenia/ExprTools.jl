@testset "type_utils.jl" begin
    @testset "parameters" begin
        # basic case
        @test collect(parameters(AbstractArray{Float32,3})) == [Float32, 3]
        # Type-alias
        @test collect(parameters(Vector{Float64})) == [Float64, 1]

        # Tuple
        @test collect(parameters(Tuple{Int8,Bool})) == [Int8, Bool]
        # Tuple with fixed count Vararg
        @test collect(parameters(Tuple{Int8,Vararg{Bool,3}})) == [Int8, Bool, Bool, Bool]

        # Tuple with varadic Vararg
        a, b = collect(parameters(Tuple{Int8,Vararg{Bool}}))
        @test a == Int8
        @test b == Vararg{Bool}

        # TypeVar
        tvar1 = parameters(Tuple{T} where {T<:Number})[1]
        @test tvar1 isa TypeVar
        @test tvar1.name == :T
        @test tvar1.lb == Union{}
        @test tvar1.ub == Number
        
        # Shared TypeVar
        tvar2, tvar3 = parameters(Tuple{X,X} where X<:Integer)
        @test tvar2 === tvar3
        @test tvar2.name == :X
        @test tvar2.lb == Union{}
        @test tvar2.ub == Integer
        
        # Shared TypeVar in different parameter 
        tvar4, part = parameters(Tuple{Y,Tuple{Y}} where Integer <: Y <: Real)
        @test part <: Tuple
        tvar5 = parameters(part)[1]
        @test tvar4 === tvar5
        @test tvar4.name == :Y
        @test tvar4.lb == Integer
        @test tvar4.ub == Real

        # Union
        @test Set(parameters(Union{Int8,Bool})) == Set([Int8, Bool])
        @test Set(parameters(Union{Int8,Bool,Set})) == Set([Int8, Bool, Set])
        # Partially collapsing Union
        @test Set(parameters(Union{Int8,Real,Set})) == Set([Real, Set])

        # Unions with type-vars
        umem1, umem2 = parameters(Union{Tuple{Z},Set{Z}} where {Z})
        utvar1 = parameters(umem1)[1]
        utvar2 = parameters(umem2)[1]
        @test utvar1 == utvar2
        @test utvar1 isa TypeVar
        @test utvar1.name == :Z
        @test utvar1.lb == Union{}
        @test utvar1.ub == Any

        # Non-parametric type
        @test isempty(parameters(Bool))

        # type-vars in signatures
        s = only(parameters(TypeVar(:T)))
        @test s.name == :T
        @test s.lb == Union{}
        @test s.ub == Any

        # https://github.com/invenia/ExprTools.jl/issues/39
        @testset "#39" begin
            s = signature(Tuple{Type{T},T} where {T<:Number})
            @test only(s[:whereparams]).args[1] == :T
        end
    end
end
