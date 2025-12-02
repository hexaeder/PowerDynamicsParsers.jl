using PowerDynamics
using PowerDynamics.Library
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using CairoMakie
using XML
using WGLMakie
using ModelingToolkit
using Graphs
using NonlinearSolve

###
### first export
###
# _dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "2025-10-27_Simbench"))
# dataset = copy(CIMCollection(_dataset))
# dataset = filter_loopback_breakers(dataset);
# dataset = rename_dangling_tpn(dataset);

# reduced_dataset = reduce_complexity(dataset)

# nodes, edges = split_topologically(dataset; verbose=true);

# @hover inspect_collection(node_subgraph; edge_labels=false, node_labels=:short, size=(1000,1000))

###
### second export
###

_dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "2025-11-21_simbench_full"))

dataset = copy(CIMCollection(_dataset))
dataset = filter_loopback_breakers(dataset)
dataset = rename_dangling_tpn(dataset);
dataset = reattach_regulating_control(dataset);
nodes, edges = split_topologically(dataset; verbose=true);

# @hover inspect_collection(nodes[4]; edge_labels=true, node_labels=:short, size=(1000,1000))
@hover inspect_collection(nodes[956]; edge_labels=false, node_labels=:short, size=(1000,1000))
# @hover inspect_collection(edges[126]; edge_labels=true, node_labels=:short, size=(1000,1000))


pfnw = Network(nodes, edges)

eresid = CGMES.test_edge_powerflow(pfnw)
sortperm(eresid)[end-10:end]
eresid[811]
@hover inspect_collection(edges[811]; edge_labels=true, node_labels=:short, size=(1000,1000))

vresid = CGMES.test_vertex_powerflow(pfnw)

pfs0 = NWState(pfnw)
for (i, idx) in enumerate(NetworkDynamics.SII.variable_symbols(pfs0))
    isnan(uflat(pfs0)[i]) || continue
    has_guess(pfnw, idx) || continue
    uflat(pfs0)[i] = get_guess(pfnw, idx)
end
pfs = find_fixpoint(pfnw, pfs0)
pfnw[VIndex(1)]
pfnw[VIndex(1)].metadata[:equations]
pfnw[VIndex(1)].metadata[:outputeqs]
pfnw[VIndex(1)].metadata[:observed]

pfs0.v[1]
pfs0[vidxs(pfnw, : ,:shunt₊terminal₊i_i; s=true, obs=false)] .= 0.1


# set_jac_prototype!(pfnw; remove_conditions=true)
alg = FastShortcutNLLSPolyalg(linsolve=QRFactorization())
solve_powerflow(nothing; pfnw=pfnw)
pfnw
