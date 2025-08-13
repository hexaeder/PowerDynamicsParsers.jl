using PowerDynamicsCGMES
using OrderedCollections
using XML
using Graphs
using GraphMakie, WGLMakie

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data")
dataset = CIMDataset(DATA)

eq = dataset[:Equipment]
terminals = eq("Terminal")
terminals[1]

# show methods for objects
dataset("Terminal")
dataset("Terminal")[3]

# show methods for extensions
tp = dataset[:Topology]
tp.extensions
tp.extensions[1]

properties(terminals[1])

dataset("ACLineSegment")[1]

dataset("Terminal")[1]
dataset("BusbarSection")[1]

inspect_dataset(dataset; filter_out=["Limit","Area","Diagram","BaseVoltage","CoordinateSystem","Region", "Position", "Location","VoltageLevel","Substation"])

using CairoMakie
fig = inspect_dataset(dataset; filter_out=["Limit","Area","Diagram","BaseVoltage","CoordinateSystem","Region", "Position", "Location","VoltageLevel","Substation"])
save("3bus_overview.pdf", fig)

fig = inspect_dataset(dataset)
save("3bus_full.pdf", fig)

# sinpect single thing
terminal = dataset("Terminal")[15] # feld2
# fig = inspect_node(terminal; stop_classes=["BaseVoltage", "Topological", "OperationalLimitType"])
fig = inspect_node(
    terminal;
    stop_classes=["BaseVoltage", "VoltageLevel", "TopologicalNode", "OperationalLimitType", "Substation"],
    # filter_out=["BaseVoltage"],
    max_depth=100
)

dataset("VoltageLevel")[1]
