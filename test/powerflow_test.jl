using PowerDynamics
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using WGLMakie

# DATA = joinpath(pkgdir(PowerDynamicsParsers), "test", "data", "testdata1")
DATA = joinpath(pkgdir(PowerDynamicsParsers), "test", "data", "1-EHVHV-mixed-all-2-sw-Ausschnitt")
dataset = CIMCollection(CIMDataset(DATA))

inspect_collection(reduce_complexity(dataset))

nodes, edges = split_topologically(dataset);

inspect_collection(nodes[3])
dump_properties(nodes[3])

inspect_collection(edges[1])
dump_properties(edges[1])
