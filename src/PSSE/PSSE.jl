module PSSE

using CSV
using DataFrames
using OrderedCollections

export parse_psse, PSSEData, DynamicDevice, show_summary
export parse_raw_file, parse_dyr_file  # Keep for backward compatibility

struct DynamicDevice
    busid::Int
    name::String
    parameters::Union{NamedTuple, Tuple}
end

struct PSSEData
    filename::String
    revision::Int
    sections::OrderedDict{String, DataFrame}
    dynamic_devices::Dict{Int, Vector{DynamicDevice}}
end

function parse_psse(raw_file::String, dyr_file=replace(raw_file, r"RAW$|raw$"=>"dyr"); verbose=false)
    # Parse RAW file
    raw_data = parse_raw_file(raw_file; verbose)
    
    # Parse DYR file  
    dyr_data = parse_dyr_file(dyr_file)
    
    # Extract metadata
    global_info = parse_global(raw_file)
    
    return PSSEData(
        basename(raw_file),
        global_info.rev,
        raw_data,
        dyr_data
    )
end

# Include parsing modules
include("raw_parsing.jl")
include("dyr_parsing.jl")
include("show.jl")

end
