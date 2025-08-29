using PowerDynamics
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using CairoMakie

datasetA = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt"))
datasetB = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt_reexport"))

reduced_datasetA = reduce_complexity(datasetA)
@hover inspect_collection(reduced_datasetA; edge_labels=false, node_labels=:short, size=(1000,1000))
#-
reduced_datasetB = reduce_complexity(datasetB)
@hover inspect_collection(reduced_datasetB; edge_labels=false, node_labels=:short, size=(1000,1000))
#-

nodesA, edgesA = split_topologically(datasetA; warn=false)
nodesB, edgesB = split_topologically(datasetB; warn=false)

#=
## Bus 1 Comparison
Normal dataset
=#
@hover inspect_collection(nodesA[1]; size=(900,900))
#=
Reexported dataset
=#
@hover inspect_collection(nodesB[1]; size=(900,900))

#=
## Bus 2 Comparison
Normal dataset
=#
@hover inspect_collection(nodesA[2]; size=(900,900))
#=
Reexported dataset
=#
@hover inspect_collection(nodesB[2]; size=(900,900))

#=
## Bus 3 Comparison
Normal dataset
=#
@hover inspect_collection(nodesA[3]; size=(900,900))
#=
Reexported dataset
=#
@hover inspect_collection(nodesB[3]; size=(900,900))

#-
comparison = PowerDynamicsParsers.CGMES.CIMCollectionComparison(nodesA[1], nodesB[1])




# Create side-by-side comparison plot
@hover inspect_comparison(comparison; size=(1600, 800))

# CGMES.get_graphplots(fig)

# CGMES.html_hover_map(fig)
