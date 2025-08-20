using Test
using SafeTestsets

@testset "PowerDynamicsParsers Tests" begin
    @testset "CGMES Tests" begin
        @safetestset "CGMES Tests" begin include("CGMES/parsing_test.jl") end
        @safetestset "CGMES Powerflow Tests" begin include("CGMES/powerflow_test.jl") end
    end
end
