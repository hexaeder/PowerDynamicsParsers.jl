module PowerDynamicsCGMES

using XML: XML, Node, nodetype, attributes, children, tag,
           is_simple, simple_value
using OrderedCollections: OrderedDict

export rdf_node, CIMObject, CIMRef, CIMBackref, CIMFile, CIMDataset
export plain_name, is_reference, is_object, is_extension, parse_metadata
export get_by_id, resolve_references!
export objects, hasname, getname, properties
export inspect_dataset, inspect_node
export follow_ref

abstract type CIMEntity end
abstract type AbstractCIMReference end

mutable struct CIMRef <: AbstractCIMReference
    id::String
    resolved::Bool
    target::Union{CIMEntity, Nothing}

    function CIMRef(id::String)
        id = replace(id, r"^#" => "")
        new(id, false, nothing)
    end
end
struct CIMBackref <: AbstractCIMReference
    source::CIMEntity
end

struct CIMObject <: CIMEntity
    profile::Symbol
    id::String
    class_name::String
    properties::OrderedDict{String, Any}
    references::Vector{CIMBackref}
    extension::Vector{CIMBackref}
    CIMObject(profile, id, n, p) = new(profile, id, n, p, CIMBackref[], CIMBackref[])
end
Base.getindex(o::CIMObject, key::String) = follow_ref(properties(o)[key])
Base.haskey(o::CIMObject, key::String) = haskey(properties(o), key)

struct CIMExtension <: CIMEntity
    profile::Symbol
    base::CIMRef
    class_name::String
    properties::OrderedDict{String, Any}
end

struct CIMFile <: CIMEntity
    profile::Symbol
    uuid::String
    created::String
    scenario_time::String
    dependencies::Vector{CIMRef}
    modeling_authority::String
    objects::OrderedDict{String, CIMObject}
    extensions::Vector{CIMExtension}
    filename::String
end
Base.getindex(f::CIMFile, id::String) = f.objects[id]
Base.getindex(f::CIMFile, i::Int) = collect(values(f.objects))[i]

struct CIMDataset <: CIMEntity
    files::OrderedDict{Symbol, CIMFile}
    directory::String
end
Base.keys(ds::CIMDataset) = keys(ds.files)
Base.values(ds::CIMDataset) = values(ds.files)
Base.getindex(ds::CIMDataset, profile::Symbol) = ds.files[profile]
Base.haskey(ds::CIMDataset, profile::Symbol) = haskey(ds.files, profile)

function get_by_id(dataset::CIMDataset, id::String)
    found_objects = CIMObject[]

    # Search through all profiles
    for (profile, cim_file) in dataset.files
        if haskey(cim_file.objects, id)
            push!(found_objects, cim_file.objects[id])
        end
    end

    # Check uniqueness
    if isempty(found_objects)
        error("Object with ID '$id' not found in any profile")
    elseif length(found_objects) > 1
        error("Object with ID '$id' found in multiple profiles.")
    end

    only(found_objects)
end

get_by_id(cimfile::CIMFile, id::String) = cimfile.objects[id]

function _register_reference!(target::CIMObject, source::Union{CIMObject,CIMExtension})
    backref = CIMBackref(source)
    push!(target.references, backref)
end

function _register_extension!(target::CIMObject, extension::CIMExtension)
    backref = CIMBackref(extension)
    push!(target.extension, backref)
end

function _resolve_property_refs!(source_object::Union{CIMObject,CIMExtension}, dataset::CIMDataset)
    for (prop_name, prop_value) in source_object.properties
        if prop_value isa CIMRef && !prop_value.resolved && !startswith(prop_value.id, "http://")
            try
                target_object = get_by_id(dataset, prop_value.id)
                prop_value.resolved = true
                prop_value.target = target_object
                _register_reference!(target_object, source_object)
            catch e
                @warn "Failed to resolve reference $(prop_value) in object $(source_object): $e"
                # rethrow(e)
            end
        end
    end
end

function _resolve_extension_refs!(extension::CIMExtension, dataset::CIMDataset)
    # Resolve the base reference
    if !extension.base.resolved
        try
            base_object = get_by_id(dataset, extension.base.id)
            extension.base.resolved = true
            extension.base.target = base_object
            _register_extension!(base_object, extension)
        catch e
            # @warn "Failed to resolve extension base reference $(extension.base.id): $e"
            error("Failed to resolve extension $extension: $e")
        end
    end
end

function resolve_references!(dataset::CIMDataset)
    # Stage 1: Resolve extension references
    for (profile, cim_file) in dataset.files
        for extension in cim_file.extensions
            _resolve_extension_refs!(extension, dataset)
            _resolve_property_refs!(extension, dataset)
        end
    end

    # Stage 2: Resolve property references in all objects
    for (profile, cim_file) in dataset.files
        for obj in values(cim_file.objects)
            _resolve_property_refs!(obj, dataset)
        end
    end

    dataset
end

function (cm::CIMFile)(s)
    keys = findall(obj -> contains(obj.class_name, s), cm.objects)
    map(k -> cm.objects[k], keys)
end
function (cd::CIMDataset)(s)
    found_objects = CIMObject[]
    for (profile, cm) in cd.files
        append!(found_objects, cm(s))
    end
    found_objects
end

hasname(obj::Union{CIMObject, CIMExtension}) = haskey(obj.properties, "name")
getname(obj::Union{CIMObject, CIMExtension}) = obj.properties["name"]

objects(f::CIMFile) = collect(values(f.objects))
objects(d::CIMDataset) = mapreduce(objects, vcat, values(d.files))

properties(obj::CIMObject) = merge(obj.properties, [ext.source.properties for ext in obj.extension]...)


follow_ref(x) = x
follow_ref(x::CIMRef) = x.target
follow_ref(x::CIMBackref) = x.source

include("parsing.jl")
include("inspect.jl")
include("subgraph.jl")
include("show.jl")

end
