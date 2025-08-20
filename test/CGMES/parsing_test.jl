using PowerDynamicsParsers
using PowerDynamicsParsers.CGMES

DATA = joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "testdata1")
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

terminal = dataset("Terminal")[15] # feld2

dataset("VoltageLevel")[1]

topo = dataset("TopologicalNode")[1]
subg = discover_subgraph(topo; filter_out = is_lineend, maxdepth=10)

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


DATA = joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "1-EHVHV-mixed-all-2-sw-Ausschnitt")
CIMDataset(DATA)
