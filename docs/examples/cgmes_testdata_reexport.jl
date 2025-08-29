using PowerDynamics
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

nodesA, edgesA = split_topologically(datasetA; warn=false)
nodesB, edgesB = split_topologically(datasetB; warn=false)

#=
## Bus 1 Comparison
=#
comparison1 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[1], nodesB[1])
@hover inspect_comparison(comparison1; size=(1000, 1500))
#=
## Bus 2 Comparison
=#
comparison2 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[2], nodesB[2])
@hover inspect_comparison(comparison2; size=(1000, 1500))
#=
## Bus 3 Comparison
=#
comparison3 = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[3], nodesB[3])
@hover inspect_comparison(comparison3; size=(1000, 1500))


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
## Calculate Powerflow for edge again
=#
#-
emA = CGMES.get_edge_model(edgesA[2])
CGMES.test_powerflow(emA)

#-
emB = CGMES.get_edge_model(edgesB[2])
CGMES.test_powerflow(emB)
