using PowerDynamics
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES

datasetA = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt"))
datasetB = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "reexport", "1-EHVHV-mixed-all-2-sw-Ausschnitt_reexport"))

nodesA, edgesA = split_topologically(datasetA; warn=false)



nodesB, edgesB = split_topologically(datasetB; warn=false)
