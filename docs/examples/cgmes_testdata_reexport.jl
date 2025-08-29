using PowerDynamics
using PowerDynamics.Library
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using CairoMakie

datasetA = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt"))
datasetB = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt_reexport"))
nothing #hide

#=
## Compare the two datasets
=#
reduced_datasetA = reduce_complexity(datasetA)
reduced_datasetB = reduce_complexity(datasetB)
comp = PowerDynamicsParsers.CGMES.CIMCollectionComparison(reduced_datasetA, reduced_datasetB)
@hover inspect_comparison(comp; size=(1000, 1500), node_labels=:short, edge_labels=false)
#-

nodesA, edgesA = split_topologically(datasetA; warn=false);
nodesB, edgesB = split_topologically(datasetB; warn=false)
nothing #hide

#=
## Bus 1 Comparison
=#
comparison1 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[1], nodesB[1])
@hover inspect_comparison(comparison1; size=(1000, 1500))
#=
Data looks better now!
- $\delta=0$ implies slack node
- slack voltage now matches the regulating control!
=#
#=
## Bus 2 Comparison
=#
comparison2 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[2], nodesB[2])
@hover inspect_comparison(comparison2; size=(1000, 1500))
#=
Bus has load + SynchornousMachine
- "Sgen" implies PQ-Machine (no dynamic)
- load is PQ
- bus P/Q is what we would expect from a PQ bus with P=Pload+PSgen and Q=Qload+QSgen
=#
#=
## Bus 3 Comparison
=#
comparison3 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[3], nodesB[3])
@hover inspect_comparison(comparison3; size=(1000, 1500))
#=
Single load bus. Load setpoint matches powerflor result so just plain PQ node
=#

#=
## Edge 1 Comparison
=#
comparison1 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(edgesA[1], edgesB[1])
@hover inspect_comparison(comparison1; size=(1000, 1500))

#=
## Edge 2 Comparison
=#
comparison2 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(edgesA[2], edgesB[2])
@hover inspect_comparison(comparison2; size=(1000, 1500))

#=
## Build full powerflow network
### Dataset A (pre reexport)
**Powerflow from PowerDynamics.jl**
=#
pfnw = Network(datasetA)
pfs = find_fixpoint(pfnw)
show_powerflow(pfs)
#=
**Powerflow from CGMES data**
=#
show_powerflow(datasetA)

#=
### Dataset B (post reexport)
**Powerflow from PowerDynamics.jl**
=#
pfnw = Network(datasetB)
pfs = find_fixpoint(pfnw)
show_powerflow(pfs)
#=
**Powerflow from CGMES data**
=#
show_powerflow(datasetB)

#=
### Original Test dataset
While we're at it let's also check the original test dataset
=#
first_dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "testdata1"))
pfnw = Network(first_dataset)
pfs = find_fixpoint(pfnw)
show_powerflow(pfs)
#-
show_powerflow(first_dataset)
#=
This does not match, which is weird. The differnece is on the third vertex where i used
a PV model witn P=2 and V=1:
=#
pfnw[VIndex(3)]
#=
Which seems to match what we see in the graph:
=#
vertices, edges = split_topologically(first_dataset; warn=false)
@hover inspect_collection(vertices[3]; size=(900,900))
#=
so no idea whats going wrong here...
=#
