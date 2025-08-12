using PowerDynamicsCGMES
using Test
using OrderedCollections
using XML

@testset "PowerDynamicsCGMES.jl" begin
    # Write your tests here.
end

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data")
DL = joinpath(DATA, "20151231T2300Z_XX_YYY_DL_.xml")
DY = joinpath(DATA, "20151231T2300Z_XX_YYY_DY_.xml")
GL = joinpath(DATA, "20151231T2300Z_XX_YYY_GL_.xml")
SSH = joinpath(DATA, "20151231T2300Z_XX_YYY_SSH_.xml")
SV = joinpath(DATA, "20151231T2300Z_XX_YYY_SV_.xml")
TP = joinpath(DATA, "20151231T2300Z_XX_YYY_TP_.xml")
EQ = joinpath(DATA, "20151231T2300Z_YYY_EQ_.xml")

collect(values(CIMFile(DL).objects))[1]

CIMFile(DL)
CIMFile(DY)
CIMFile(GL)
CIMFile(SSH)
CIMFile(SV)
CIMFile(TP)
CIMFile(EQ).objects["#_b767a615-69c9-46cb-89fb-998824454f6d"]
collect(keys(CIMFile(EQ).objects))

dataset = CIMDataset(DATA)
resolve_references!(dataset)

eq = dataset[:Equipment]
terminals = eq("Terminal")
terminals[1]
