@testset "def_tools.jl" begin
    @testset "args_tuple_expr" begin
        @test args_tuple_expr(splitdef(:(f(x, y)=1))) == :((x, y))
        @test args_tuple_expr(splitdef(:(f(x::Int, y::Float64)=1))) == :((x, y))
        @test args_tuple_expr(splitdef(:(f(x::Vector{T}) where T=1))) == :((x,))
        @test args_tuple_expr(splitdef(:(f(x::Vararg)=1))) == :((x...,))
        @test args_tuple_expr(splitdef(:(f(x::Vararg{Int})=1))) == :((x...,))
        @test args_tuple_expr(splitdef(:(f(x...)=1))) == :((x...,))
        @test args_tuple_expr(splitdef(:(f(x::Int...)=1))) == :((x...,))
        @test args_tuple_expr(splitdef(:(f(x::(Vector{T} where T)...)=1))) == :((x...,))
    end
end