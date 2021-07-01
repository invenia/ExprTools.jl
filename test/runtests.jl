using ExprTools
using Test

@testset "ExprTools.jl" begin
    include("function.jl")
    include("method.jl")
    include("def_tools.jl")
    include("type_utils.jl")
end
