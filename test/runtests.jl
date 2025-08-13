using PowerDynamicsCGMES
using Test
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


inspect_dataset(dataset; filter_out=["Limit","Area","Diagram","BaseVoltage","CoordinateSystem","Region", "Position", "Location","VoltageLevel","Substation"])
