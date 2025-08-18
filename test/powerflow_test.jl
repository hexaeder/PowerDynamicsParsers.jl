using PowerDynamics
using PowerDynamicsCGMES
using WGLMakie

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "testdata1")
dataset = CIMDataset(DATA)

topological_nodes = dataset("TopologicalNode")

b1 = discover_subgraph(topological_nodes[1]; filter_out = is_lineend)
b2 = discover_subgraph(topological_nodes[2]; filter_out = is_lineend)
b3 = discover_subgraph(topological_nodes[3]; filter_out = is_lineend)

inspect_collection(b1)

b1("BusbarSection")[2]
