# # Basic Usage of PowerDynamicsCGMES
#
# This example demonstrates the basic usage of PowerDynamicsCGMES for parsing
# CGMES XML files and visualizing the resulting data.

using PowerDynamicsCGMES

# ## Loading CGMES Data
#
# First, we load a CGMES dataset from XML files. The package includes test data
# that we can use for demonstration purposes.

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "test", "data", "testdata1")
dataset = CIMDataset(DATA)

# The dataset contains multiple CGMES profiles:

println("Available profiles:")
for key in keys(dataset)
    println("  ", key)
end

# ## Exploring CIM Objects
#
# We can access specific types of CIM objects using the call syntax:

terminals = dataset("Terminal")
println("Found $(length(terminals)) Terminal objects")

# Or we can look at equipment objects:

eq_objects = dataset.profiles[:Equipment]
println("Equipment profile contains $(length(eq_objects)) objects")

# ## Filtering Objects
#
# The package provides convenient filtering functions:

aclines = eq_objects("ACLineSegment")
println("Found $(length(aclines)) ACLineSegment objects")

# ## Visualization
#
# We can create network visualizations using the inspect functionality:

using CairoMakie

# Create a filtered visualization (excluding some object types for clarity)
fig = inspect_collection(dataset; 
    filter_out=["Limit", "Area", "Diagram", "BaseVoltage", 
                "CoordinateSystem", "Region", "Position", 
                "Location", "VoltageLevel", "Substation"])
fig