using PowerDynamics
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES

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

#-
# @hover inspect_collection(nodes[1]; size=(900,900))
#-
# PowerDynamicsParsers.CGMES.html_hover_map() #hide
