using PowerDynamics
using PowerDynamics.Library
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
# using CairoMakie
using WGLMakie

dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data","1-EHVHV-mixed-all-2-sw-minimal-komplex"))


reduced_dataset = reduce_complexity(dataset)
@hover inspect_collection(reduced_dataset; edge_labels=false, node_labels=:short, size=(1000,1000))

nodes, edges = split_topologically(dataset; warn=false, verbose=true);

#=
Bus 1
=#
@hover inspect_collection(edges[2]; size=(900,900))

@hover inspect_collection(nodes[6]; size=(900,900))


@hover inspect_collection(edges[10].metadata[:branches][1]; size=(900,900))
@hover inspect_collection(edges[10].metadata[:branches][2]; size=(900,900))
@hover inspect_collection(edges[10].metadata[:branches][3]; size=(900,900))

e = edges[10]
b1 = edges[10].metadata[:branches][1]
b2 = edges[10].metadata[:branches][2]
b3 = edges[10].metadata[:branches][3]

b1.metadata[:discovered_from_lineend]
b2.metadata[:discovered_from_lineend]
b3.metadata[:discovered_from_lineend]
b4.metadata[:discovered_from_lineend]

filter(CGMES.is_lineend, e("Terminal"))

findfirst(t->getname(t) == "HV Bus 15", dataset("Terminal"))
dataset(r"Load")[2]



length(edges)
CGMES.is_single_branch_subgraph(edges[10].metadata[:branches][4])
CGMES.is_multi_branch_subgraph(edges[10].metadata[:branches][2])

pfnw = Network(dataset)
pfs0 = NWState(pfnw)
pfs0.v[6][:pv₊P] = 0.330231
pfs = find_fixpoint(pfnw, pfs0)

show_powerflow(pfs)
show_powerflow(dataset)

for i in 1:14
    println("Edge $i")
    CGMES.test_powerflow(pfnw[EIndex(i)])
end

pfnw[VIndex(1)].metadata

pfnw[EIndex(2)]
pfnw


ModelingToolkit.getname(pfnw[EIndex(1)].metadata[:odesystem])
ModelingToolkit.setname(pfnw[EIndex(1)].metadata[:odesystem], :foobar)

getname

CGMES.determine_branch_parameters(edges[1].metadata[:branches][1])


for (i, n) in enumerate(nodes)
    @info "Bus $i" CGMES.get_injected_power_pu.(n("Terminal"))
end
nodes
