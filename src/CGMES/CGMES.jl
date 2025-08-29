module CGMES

using XML: XML, Node, nodetype, attributes, children, tag,
           is_simple, simple_value
using OrderedCollections: OrderedDict
using PowerDynamics: Library, Line, MTKLine
using NetworkDynamics: EdgeModel, VertexModel, set_graphelement!, initialize_component, get_initial_state

export rdf_node, CIMObject, CIMRef, CIMBackref, CIMCollection, CIMFile, CIMDataset
export plain_name, is_reference, is_object, is_extension, parse_metadata
export resolve_references!
export objects, extensions, hasname, getname, properties
export inspect_collection, inspect_node, inspect_comparison
export follow_ref
export CIMCollectionComparison

SBASE = 100 # Base power in MVA

abstract type CIMEntity end
abstract type AbstractCIMReference end
abstract type AbstractCIMCollection <: CIMEntity end

mutable struct CIMRef <: AbstractCIMReference
    id::String
    resolved::Bool
    target::Union{CIMEntity, Nothing}

    function CIMRef(id::String)
        id = replace(id, r"^#" => "")
        new(id, false, nothing)
    end
end
is_resolved(ref::CIMRef) = ref.resolved
is_external_ref(ref::CIMRef) = startswith(ref.id, "http")

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

struct CIMExtension <: CIMEntity
    profile::Symbol
    base::CIMRef
    class_name::String
    properties::OrderedDict{String, Any}
end

struct CIMCollection <: AbstractCIMCollection
    objects::OrderedDict{String, CIMObject}
    extensions::Vector{CIMExtension}
    metadata::OrderedDict{Symbol,Any}
    CIMCollection(objs, exts) = new(objs, exts, OrderedDict{Symbol,Any}())
end

struct CIMFile <: AbstractCIMCollection
    collection::CIMCollection
    profile::Symbol
    uuid::String
    created::String
    scenario_time::String
    dependencies::Vector{CIMRef}
    modeling_authority::String
    filename::String
end

struct CIMDataset <: AbstractCIMCollection
    files::OrderedDict{Symbol, CIMFile}
    directory::String
    function CIMDataset(files, directory)
        allkeys = mapreduce(f -> collect(keys(objects(f))), vcat, values(files))
        allunique(allkeys) || error("Duplicate object IDs found in dataset files.")
        new(files, directory)
    end
end
CIMCollection(ds::CIMDataset) = CIMCollection(objects(ds), extensions(ds))

Base.getindex(o::CIMObject, key::String) = follow_ref(properties(o)[key])
function Base.getindex(o::CIMObject, s::Regex)
    props = properties(o)
    allkeys = collect(keys(props))
    keyidxs = findall(k -> contains(k, s), allkeys)
    if isempty(keyidxs)
        throw(KeyError("No property matching $s found in object $(o.id) of class $(o.class_name). Available properties: $(allkeys)"))
    elseif length(keyidxs) == 1
        return props[allkeys[only(keyidxs)]]
    else
        throw(KeyError("Multiple properties matching $s found in object $(o.id) of class $(o.class_name). Available properties: $(allkeys)"))
    end
end
Base.getindex(c::CIMCollection, id::String) = c.objects[id]
Base.getindex(c::CIMCollection, i::Int) = collect(values(c.objects))[i]
Base.getindex(f::CIMFile, id::String) = f.collection.objects[id]
Base.getindex(f::CIMFile, i::Int) = collect(values(f.collection.objects))[i]
Base.getindex(ds::CIMDataset, profile::Symbol) = ds.files[profile]

Base.keys(ds::CIMDataset) = keys(ds.files)
Base.keys(c::CIMCollection) = keys(c.objects)
Base.values(ds::CIMDataset) = values(ds.files)
Base.values(c::CIMCollection) = values(c.objects)

Base.haskey(o::CIMObject, key::String) = haskey(properties(o), key)
Base.haskey(c::CIMCollection, id::String) = haskey(c.objects, id)
Base.haskey(ds::CIMDataset, profile::Symbol) = haskey(ds.files, profile)

# Copy methods for CIM types
Base.copy(ref::CIMRef) = CIMRef(ref.id)

function Base.copy(obj::CIMObject)
    props_copy = OrderedDict{String, Any}()
    for (key, val) in obj.properties
        props_copy[key] = val isa CIMRef ? copy(val) : val
    end
    # Create new object with empty reference vectors (rebuilt by resolve_references!)
    CIMObject(obj.profile, obj.id, obj.class_name, props_copy)
end

function Base.copy(ext::CIMExtension)
    base_copy = copy(ext.base) # gets rid of resolve reference by copying
    props_copy = OrderedDict{String, Any}()
    for (key, val) in ext.properties
        props_copy[key] = val isa CIMRef ? copy(val) : val
    end
    CIMExtension(ext.profile, base_copy, ext.class_name, props_copy)
end

function _register_reference!(target::CIMObject, source::Union{CIMObject,CIMExtension})
    backref = CIMBackref(source)
    push!(target.references, backref)
end

function _register_extension!(target::CIMObject, extension::CIMExtension)
    backref = CIMBackref(extension)
    push!(target.extension, backref)
end

function _resolve_property_refs!(source_object::Union{CIMObject,CIMExtension}, objectdict; warn)
    for (prop_name, prop_value) in source_object.properties
        if prop_value isa CIMRef && !prop_value.resolved && !startswith(prop_value.id, "http://")
            try
                target_object = objectdict[prop_value.id]
                prop_value.resolved = true
                prop_value.target = target_object
                _register_reference!(target_object, source_object)
            catch e
                warn && @warn "Failed to resolve reference for property $(prop_name) in object $(source_object): $e"
                # rethrow(e)
            end
        end
    end
end

function _resolve_extension_refs!(extension::CIMExtension, objectdict)
    # Resolve the base reference
    if !extension.base.resolved
        try
            base_object = objectdict[extension.base.id]
            extension.base.resolved = true
            extension.base.target = base_object
            _register_extension!(base_object, extension)
        catch e
            # @warn "Failed to resolve extension base reference $(extension.base.id): $e"
            error("Failed to resolve extension $extension: $e")
        end
    end
end

function resolve_references!(collection::AbstractCIMCollection; warn=true)
    objectdict = objects(collection)
    # Stage 1: Resolve extension references
    for extension in extensions(collection)
        _resolve_extension_refs!(extension, objectdict)
        _resolve_property_refs!(extension, objectdict; warn)
    end

    # Stage 2: Resolve property references in all objects
    for obj in values(objects(collection))
        _resolve_property_refs!(obj, objectdict; warn)
    end

    collection
end

function (c::AbstractCIMCollection)(s::Union{AbstractString, Regex})
    _comparer = s isa AbstractString ? isequal : contains
    Iterators.filter(
        obj -> _comparer(obj.class_name, s),
        values(objects(c))
    ) |> collect
end
function (c::AbstractCIMCollection)(vec::AbstractVector)
    mapreduce(vcat, vec) do pattern
        c(pattern)
    end |> union!
end


hasname(obj::Union{CIMObject, CIMExtension}) = haskey(obj.properties, "name")
getname(obj::Union{CIMObject, CIMExtension}) = obj.properties["name"]

objects(c::CIMCollection) = c.objects
objects(f::CIMFile) = objects(f.collection)
function objects(d::CIMDataset)
    dicts = objects.(values(d.files))
    mergewith(dicts...) do args...
        error("The dataset contains files which define objects with the same ID!")
    end
end

extensions(c::CIMCollection) = c.extensions
extensions(f::CIMFile) = extensions(f.collection)
extensions(ds::CIMDataset) = mapreduce(extensions, vcat, values(ds.files))

properties(obj::CIMObject) = merge(obj.properties, [ext.source.properties for ext in obj.extension]...)

follow_ref(x) = x
follow_ref(x::CIMRef) = x.target
follow_ref(x::CIMBackref) = x.source

base_object(x::AbstractCIMReference) = base_object(follow_ref(x))
base_object(x::CIMObject) = x
base_object(x::CIMExtension) = follow_ref(x.base)

include("parsing.jl")
include("inspect.jl")
include("subgraph.jl")
include("show.jl")
include("static_models.jl")
include("compare.jl")

end
