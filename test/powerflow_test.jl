using PowerDynamics
using PowerDynamicsCGMES
using WGLMakie

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "testdata1")
dataset = CIMDataset(DATA)


t = dataset("Terminal")[3]
t["ConductingEquipment"]
