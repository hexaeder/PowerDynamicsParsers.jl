using PowerDynamics
using PowerDynamics.Library
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using CairoMakie
using XML
using WGLMakie

###
### first export
###
_dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "2025-10-27_Simbench"))
dataset = copy(CIMCollection(_dataset))
dataset = filter_loopback_breakers(dataset);
dataset = rename_dangling_tpn(dataset);

reduced_dataset = reduce_complexity(dataset)

nodes, edges = split_topologically(dataset; verbose=true);

@hover inspect_collection(node_subgraph; edge_labels=false, node_labels=:short, size=(1000,1000))

###
### second export
###

_dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "2025-11-21_simbench_full"))

dataset = copy(CIMCollection(_dataset))
dataset = filter_loopback_breakers(dataset)
dataset = rename_dangling_tpn(dataset);

nodes, edges = split_topologically(dataset; verbose=true);

@hover inspect_collection(nodes[100]; edge_labels=true, node_labels=:short, size=(1000,1000))
@hover inspect_collection(edges[1]; edge_labels=true, node_labels=:short, size=(1000,1000))


using PowerDynamicsParsers.CGMES: get_edge_model, get_static_vertex_model
get_edge_model(edges[1])


Network(dataset)
