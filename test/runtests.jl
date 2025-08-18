using PowerDynamicsCGMES
using OrderedCollections
using XML
using Graphs
using WGLMakiesing GraphMakie, WGLMakie

using WGLMakie
WGLMakie.activate!

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "testdata1")
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

# fig = inspect_dataset(dataset)
fig = inspect_dataset(dataset; filter_out=["BaseVoltage", "OperationalLimitType", r"^Diagram$", "CoordinateSystem", "Substation", "Geographical"])
save("3bus_nealy_full.pdf", fig)

# save("3bus_full.pdf", fig)

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

topo = dataset("TopologicalNode")[1]
fig = inspect_node(
    topo;
    stop_classes=["BaseVoltage", "VoltageLevel", "OperationalLimitType", "Substation", "LineSegment"],
    filter_out=[],
    max_depth=100
)
save("topological_bus_details.pdf", fig)


dataset("ConformLoad")[1]
dataset("SynchronousMachine")[1]
dataset("SynchronousMachine")[3]

dataset("ThermalGeneratingUnit")[1]
dataset("FossilFuel")[1]

dataset[:SteadyStateHypothesis].extensions
dataset[:SteadyStateHypothesis].extensions[1] # GeneratingUnit
dataset[:SteadyStateHypothesis].extensions[3] # RegulatingControl
dataset[:SteadyStateHypothesis].extensions[5] # ConformLoad
dataset[:SteadyStateHypothesis].extensions[21] # Machine

dataset[:Dynamics]("LoadAggregate")[1]
dataset[:Dynamics]("LoadStatic")[1]
dataset[:Dynamics]("Synchronous")[1]
