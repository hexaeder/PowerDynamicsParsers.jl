using PowerDynamics
using PowerDynamicsCGMES
using WGLMakie

# DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "testdata1")
DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "1-EHVHV-mixed-all-2-sw-Ausschnitt")
dataset = CIMCollection(CIMDataset(DATA))

inspect_collection(reduce_complexity(dataset))


nodes, edges = split_topologically(dataset)
