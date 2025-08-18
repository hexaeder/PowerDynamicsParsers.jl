using PowerDynamicsCGMES
using OrderedCollections
using XML
using Graphs
using GraphMakie

# using WGLMakie; WGLMakie.activate!()
using CairoMakie; CairoMakie.activate!()

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

properties(terminals[1])

dataset("ACLineSegment")[1]

dataset("Terminal")[1]
dataset("BusbarSection")[1]

inspect_collection(dataset; filter_out=["Limit","Area","Diagram","BaseVoltage","CoordinateSystem","Region", "Position", "Location","VoltageLevel","Substation"])

fig = inspect_collection(dataset; filter_out=["Limit","Area","Diagram","BaseVoltage","CoordinateSystem","Region", "Position", "Location","VoltageLevel","Substation"])
save("3bus_overview.pdf", fig)

# fig = inspect_collection(dataset)
fig = inspect_collection(dataset; filter_out=["BaseVoltage", "OperationalLimitType", r"^Diagram$", "CoordinateSystem", "Substation", "Geographical"])
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

subg = discover_subgraph(topo; filter_out = is_lineend, maxdepth=10)
inspect_collection(subg)



dataset("ConformLoad")[1]
dataset("SynchronousMachine")[1]
dataset("SynchronousMachine")[3]

dataset("ThermalGeneratingUnit")[1]
dataset("FossilFuel")[1]

extensions(dataset[:SteadyStateHypothesis])
extensions(dataset[:SteadyStateHypothesis])[1] # GeneratingUnit
extensions(dataset[:SteadyStateHypothesis])[3] # RegulatingControl
extensions(dataset[:SteadyStateHypothesis])[5] # ConformLoad
extensions(dataset[:SteadyStateHypothesis])[21] # Machine

dataset[:Dynamics]("LoadAggregate")[1]
dataset[:Dynamics]("LoadStatic")[1]
dataset[:Dynamics]("Synchronous")[1]
