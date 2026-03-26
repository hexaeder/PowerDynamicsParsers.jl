# # 2 Bus Example Export

using PowerDynamics
using PowerDynamics.Library
using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES
using CairoMakie

# # Load Dataset and Inspect
#
# First wie load the full data set.
# Consists of lots of files, but most of them are actually empty.

dataset = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "simbench_2bus"))

# Lets then plot the full dataset.
# Those are all entities defined in the CGMES data.
#
# > **Tip**
# >
# > Hover on the nodes of the network to see the properties.

inspect_collection(dataset; edge_labels=false, node_labels=:short, size=(1000,1000))

# # Filtered Dataset and Reduced Complexity
# Lets filter out all thos `Diagram` classes, as they just clutter the view.
#
# We can already see, that we have two `TopologicalNodes` which will form the Buses
# in the network later.
# There isa single `ACLineSigment` connecting both topoloical busses.

no_diagram = filter(!is_class(r"Diagram"), dataset)
inspect_collection(no_diagram; edge_labels=false, node_labels=:short, size=(1000,1000))

# Lets reduce the complexity further by throwing away some more nodes like substations, geographical areas and so on:
# Now the network structure is more visible, because we have less "non electrical" pathes between the topological nodes.

reduced_dataset = reduce_complexity(dataset)
inspect_collection(reduced_dataset; edge_labels=false, node_labels=:short, size=(1000,1000))

# The picture is much clearer now.
# However there is a problem: there is nothing connected to the busses!
# The only thing is the "EnergySource", but that thing does not have lots of information either.

only(dataset("EnergySource"))

# ## Topological Splitting
#
# Eventually, we want to split the dataset into its topological components.
# We'll use those subgraphs to build bus in edge models.
#
# ### Bus 1: DUT

nodes, edges = split_topologically(dataset; warn=false, verbose=true);
inspect_collection(nodes[1]; size=(900,900))

# ### Bus 2: Slack

inspect_collection(nodes[2]; size=(900,900))

# ### Powerline from 1 to 2

inspect_collection(edges[1]; size=(900,900))

# This file was generated using Literate.jl, https://github.com/fredrikekre/Literate.jl
