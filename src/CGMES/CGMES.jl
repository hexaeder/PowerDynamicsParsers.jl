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
export CIMCollectionComparison, compare_objects
export descend, ascend, descendants, ascendants, byprop, byclass

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
Base.iterate(ref::CIMRef) = (ref, nothing)
Base.iterate(ref::CIMRef, state) = nothing

struct CIMBackref <: AbstractCIMReference
    source::CIMEntity
    prop::Union{Nothing,String}
end
CIMBackref(source) = CIMBackref(source, nothing)

struct CIMObject <: CIMEntity
    profile::Symbol
    id::String
    class_name::String
    properties::OrderedDict{String, Any}
    backrefs::Vector{CIMBackref}
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
end
CIMCollection(objs, exts) = CIMCollection(objs, exts, OrderedDict{Symbol,Any}())

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
        props_copy[key] = if val isa CIMRef
            copy(val)
        elseif val isa Vector{CIMRef}
            copy.(val)
        else
            val
        end
    end
    # Create new object with empty reference vectors (rebuilt by resolve_references!)
    CIMObject(obj.profile, obj.id, obj.class_name, props_copy)
end

function Base.copy(ext::CIMExtension)
    base_copy = copy(ext.base) # gets rid of resolve reference by copying
    props_copy = OrderedDict{String, Any}()
    for (key, val) in ext.properties
        props_copy[key] = if val isa CIMRef
            copy(val)
        elseif val isa Vector{CIMRef}
            copy.(val)
        else
            val
        end
    end
    CIMExtension(ext.profile, base_copy, ext.class_name, props_copy)
end

function _register_backref!(target::CIMObject, source::Union{CIMObject,CIMExtension}, prop)
    backref = CIMBackref(source, prop)
    push!(target.backrefs, backref)
end

function _register_extension!(target::CIMObject, extension::CIMExtension)
    backref = CIMBackref(extension)
    push!(target.extension, backref)
end

function _resolve_property_refs!(source_object::Union{CIMObject,CIMExtension}, objectdict; warn)
    for (prop_name, prop_value) in source_object.properties
        if prop_value isa Union{CIMRef, Vector{CIMRef}}
            for ref in prop_value
                if !ref.resolved && !startswith(ref.id, "http://")
                    try
                        target_object = objectdict[ref.id]
                        ref.resolved = true
                        ref.target = target_object
                        _register_backref!(target_object, source_object, prop_name)
                    catch e
                        warn && @warn "Failed to resolve reference for property $(prop_name) in object $(source_object): $e"
                        # rethrow(e)
                    end
                end
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

"""
    base_object(x)

Follows references, in case of extensions also returns the base object being extended.
"""
base_object(x::AbstractCIMReference) = base_object(follow_ref(x))
base_object(x::CIMObject) = x
base_object(x::CIMExtension) = follow_ref(x.base)


is_class(x, class::String) = (typeof(x) <: CIMObject) && (x.class_name == class)
is_class(x, class::Regex) = (typeof(x) <: CIMObject) && (contains(x.class_name, class))
is_class(x, classes) = any(class -> is_class(x, class), classes)
is_class(class_es) = Base.Fix2(is_class, class_es)

"""
    Relation(this, other, property)

Models a relationship between two CIMObjects via a property.
This works for both forward and backward references!

Forward ref:  this[property] -> other
Backward ref: this <- other[property]

It is used as collections for this to follow to other.
"""
struct Relation
    this::CIMObject
    other::CIMObject
    property::String
end

function byprop(prop::String)
    (rel::Relation) -> rel.property == prop
end
function byprop(prop::Regex)
    (rel::Relation) -> contains(rel.property, prop)
end
function byclass(class; via=nothing)
    if via != nothing
        (rel::Relation) -> is_class(rel.other, class) && rel.property == via
    else
        (rel::Relation) -> is_class(rel.other, class)
    end
end

"""
    descendants(obj, matcher)
    descendants(matcher) # obj |> descendants(matcher)

Get all forward references matching the criteria (plural noun form).

Returns a `Vector{CIMObject}` containing all matching descendants (0 or more).
Matcher can be `byprop` or `byclass`.

See also: `descend()` to get exactly one match with error checking.
"""
function descendants(obj, matcher)
    relations = forward_relations(obj)
    matching = filter(matcher, relations)
    return getproperty.(matching, :other)
end
descendants(matcher) = Base.Fix2(descendants, matcher)

"""
    ascendants(obj, matcher)
    ascendants(matcher) # obj |> ascendants(matcher)

Get all backward references matching the criteria (plural noun form).

Returns a `Vector{CIMObject}` containing all matching ascendants (0 or more).
Matcher can be `byprop` or `byclass`.

See also: `ascend()` to get exactly one match with error checking.
"""
function ascendants(obj, matcher)
    relations = backward_relations(obj)
    matching = filter(matcher, relations)
    return getproperty.(matching, :other)
end
ascendants(matcher) = Base.Fix2(ascendants, matcher)

"""
    descend(obj, matcher)
    descend(matcher) # obj |> descend(matcher)

Follow forward references to find exactly one matching CIMObject (verb form).

Returns a single `CIMObject`. Errors if 0 or multiple matches are found.
Matcher can be `byprop` or `byclass`.

See also: `descendants()` to get all matches without error checking.
"""
function descend(obj, matcher)
    matches = descendants(obj, matcher)
    if length(matches) == 1
        return only(matches)
    else
        error("Expected exactly 1 descendant matching criteria, found $(length(matches)). Use descendants() to get all matches.")
    end
end
descend(matcher) = Base.Fix2(descend, matcher)

"""
    ascend(obj, matcher)
    ascend(matcher) # obj |> ascend(matcher)

Follow backward references to find exactly one matching CIMObject (verb form).

Returns a single `CIMObject`. Errors if 0 or multiple matches are found.
Matcher can be `byprop` or `byclass`.

See also: `ascendants()` to get all matches without error checking.
"""
function ascend(obj, matcher)
    matches = ascendants(obj, matcher)
    if length(matches) == 1
        return only(matches)
    else
        error("Expected exactly 1 ascendant matching criteria, found $(length(matches)). Use ascendants() to get all matches.")
    end
end
ascend(matcher) = Base.Fix2(ascend, matcher)

function forward_relations(this)
    relations = Relation[]
    for (key, val) in properties(this)
        if val isa Union{CIMRef, Vector{CIMRef}}
            for ref in val
                is_resolved(ref) || continue
                other = follow_ref(ref)
                push!(relations, Relation(this, other, key))
            end
        end
    end
    relations
end
function backward_relations(this)
    relations = Relation[]
    for backref in this.backrefs
        other = base_object(backref)
        property = backref.prop
        push!(relations, Relation(this, other, property))
    end
    relations
end

ascend(obj::CIMObject) = Base.Fix1(ascend, obj)

function merge_collection(c1::CIMCollection, c2::CIMCollection; warn=true, metadatakey=:merger_of)
    merged_objects = Dict{String, CIMObject}()
    for (k, v) in objects(c1)
        merged_objects[k] = copy(v)
    end
    for (k, v) in objects(c2)
        merged_objects[k] = copy(v)
    end

    ext1 = copy.(extensions(c1))
    ext2 = copy.(extensions(c2))
    merged_extensions = vcat(ext1, ext2)

    # sanity checks
    full_extensions = Dict{String, Dict{Symbol, Any}}()
    for ex in merged_extensions
        key = ex.base.id
        subdict = get(full_extensions, key, Dict{Symbol, Any}())
        for (k,v) in ex.properties
            if haskey(subdict, Symbol(k))
                @warn "Merging collections with overlapping extension properties for object $key property $k"
            else
                subdict[Symbol(k)] = v
            end
        end
    end
    merged_metadata = copy(c1.metadata)
    delete!(merged_metadata, metadatakey)
    for (k,v) in c2.metadata
        k == metadatakey && continue
        if haskey(merged_metadata, k) && merged_metadata[k] != v
            @warn "Merging collections with overlapping metadata key $k: $(merged_metadata[k]) vs $v"
        else
            merged_metadata[k] = v
        end
    end

    col = CIMCollection(merged_objects, merged_extensions, merged_metadata)
    resolve_references!(col; warn)

    # if one collection is alrleady a merger, take its components, else take it self
    c1merger = get!(c1.metadata, metadatakey, CIMCollection[c1])
    c2merger = get!(c2.metadata, metadatakey, CIMCollection[c2])
    col.metadata[metadatakey] = vcat(c1merger, c2merger)

    col
end

include("parsing.jl")
include("compare.jl")
include("inspect.jl")
include("subgraph.jl")
include("show.jl")
include("static_models.jl")

function symbolify(s::String)
    s = replace(s, r"\s" => "_")
    Symbol(s)
end

end
