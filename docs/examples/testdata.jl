#=
# Inspection of Test 1-EHVHV-mixed-all-2-sw-Ausschnitt
=#
using PowerDynamics
using PowerDynamicsCGMES
using CairoMakie

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "1-EHVHV-mixed-all-2-sw-Ausschnitt")
dataset = CIMCollection(CIMDataset(DATA))
nothing #hide

#=
!!! tip
    Hover the nodes to inspect the properties!

=#
reduced_dataset = reduce_complexity(dataset)
inspect_collection(reduced_dataset; edge_labels=false, node_labels=:short, size=(1000,1000))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), reduced_dataset) #hide
#=
Well thats still a bit to much. Let split the dataset topologicially
=#
nodes, edges = split_topologically(dataset; warn=false)
nothing #hide
#=
## Bus 1: Load
=#
inspect_collection(nodes[1]; size=(900,900))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), nodes[1]) #hide

#=
## Bus 2: Load + Machine
=#
inspect_collection(nodes[2]; size=(900,900))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), nodes[2]) #hide

#=
## Bus 3: Three Machines
=#
inspect_collection(nodes[3]; size=(900,900))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), nodes[3]) #hide

#=
## Powerline 1: AC Pi-Line
=#
inspect_collection(edges[1]; size=(900,900))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), edges[1]) #hide

#=
## Powerline 2: Transformer
=#
inspect_collection(edges[2]; size=(900,900))
#-
PowerDynamicsCGMES.add_property_hover(current_figure(), edges[2]) #hide
