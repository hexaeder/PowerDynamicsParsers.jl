module PowerDynamicsCGMES

using XML: XML, Node, nodetype, attributes, children, tag,
           is_simple, simple_value
using OrderedCollections: OrderedDict

export rdf_node, CIMObject, CIMRef, CIMBackref, CIMFile
export plain_name, is_reference, is_object, parse_metadata

"""
Extract the "Rescource Description Framework" (RDF) node from the XML document.
"""
function rdf_node(headnode)
    childs = children(headnode)
    # filter out declaration
    filter!(n -> !(nodetype(n) == XML.Declaration), childs)
    # filter out comments
    filter!(n -> !(nodetype(n) == XML.Comment), childs)
    # only one rdf node should remain
    only(childs)
end

abstract type CIMEntity end
abstract type AbstractCIMReference end

struct CIMRef <: AbstractCIMReference
    id::String
    resolved::Bool
    target::Union{CIMEntity, Nothing}

    CIMRef(id::String) = new(id, false, nothing)
end
struct CIMBackref <: AbstractCIMReference
    id::String
    target::CIMEntity
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

struct CIMFile <: CIMEntity
    profile::Symbol
    uuid::String
    created::String
    scenario_time::String
    dependencies::Vector{CIMRef}
    modeling_authority::String
    objects::OrderedDict{String, CIMObject}
    filename::String
end

plain_name(el::Node, prefix::String; kw...) = plain_name(el, [prefix]; kw...)
function plain_name(el::Node, prefixes; strip_ns=[])
    noprefix = nothing
    for prefix in prefixes
        regex = Regex("^"*prefix*":(.*)\$")
        m = match(regex, tag(el))
        if !isnothing(m)
            noprefix = m[1]
            break
        end
    end
    if isnothing(noprefix)
        error("Element $(tag(el)) does not match any of the expected prefixes $prefixes.")
    end
    for ns in strip_ns
        noprefix = replace(noprefix, ns*"." => "")
    end
    noprefix
end

function is_reference(el::Node)
    haskey(attributes(el), "rdf:resource")
end

function is_object(el::Node)
    nodetype(el) == XML.Element && contains(tag(el), r"^cim:")
end
function is_metadata(el::Node)
    nodetype(el) == XML.Element && tag(el) == "md:FullModel"
end

CIMRef(el::Node) = CIMRef(attributes(el)["rdf:resource"])

function parse_metadata(md_node::Node)
    attrs = attributes(md_node)
    uuid = get(attrs, "rdf:about", "")
    uuid = replace(uuid, "urn:uuid:" => "")

    _profiles = String[]
    dependencies = CIMRef[]
    created = ""
    scenario_time = ""
    modeling_authority = ""

    for child in children(md_node)
        tag_name = tag(child)
        if tag_name == "md:Model.profile"
            if XML.is_simple(child)
                val = XML.simple_value(child)
                if !isnothing(val)
                    push!(_profiles, val)
                end
            end
        elseif tag_name == "md:Model.DependentOn"
            dep_uuid = replace(attributes(child)["rdf:resource"], "urn:uuid:" => "")
            push!(dependencies, CIMRef(dep_uuid))
        elseif tag_name == "md:Model.created"
            if XML.is_simple(child)
                val = XML.simple_value(child)
                if !isnothing(val)
                    created = val
                end
            end
        elseif tag_name == "md:Model.scenarioTime"
            if XML.is_simple(child)
                val = XML.simple_value(child)
                if !isnothing(val)
                    scenario_time = val
                end
            end
        elseif tag_name == "md:Model.modelingAuthoritySet"
            if XML.is_simple(child)
                val = XML.simple_value(child)
                if !isnothing(val)
                    modeling_authority = val
                end
            end
        end
    end

    profile = _determine_profile(_profiles)
    return (uuid=uuid, profile=profile, dependencies=dependencies,
            created=created, scenario_time=scenario_time, modeling_authority=modeling_authority)
end
function _determine_profile(profiles)
    keys = [
        :Equipment,
        :Topology,
        :StateVariables,
        :DiagramLayout,
        :SteadyStateHypothesis,
        :GeographicalLocation,
        :Dynamics,
    ]
    candidates = map(profiles) do profile
        keyidx = findall(k -> occursin(string(k), profile), keys)
        if !(length(keyidx) == 1)
            error("Profile $profile does not contain exactly one of the expected keys: $keys")
        end
        keys[only(keyidx)]
    end
    if !allequal(candidates)
        error("Profiles $profiles do not match (got $candidates), expected all to be the same.")
    end
    first(candidates)
end


# parser function
function CIMObject(el::Node, profile)
    name = plain_name(el, ["cim", "entsoe"])
    id = get(attributes(el), "rdf:ID", "")
    id == "" && @warn "Element $(tag(el)) has no rdf:ID attribute!"
    props = OrderedDict{String, Any}()
    for p in children(el)
        key = plain_name(p, ["cim", "entsoe"]; strip_ns=[name, "IdentifiedObject"])
        if is_simple(p)
            props[key] = simple_value(p)
        elseif is_reference(p)
            props[key] = CIMRef(p)
        else
            @warn "Skipping property $p, no parser defined yet."
        end
    end
    CIMObject(profile, id, name, props)
end

function CIMFile(filepath::String)
    filename = basename(filepath)
    doc = XML.read(filepath, Node)
    rdf = rdf_node(doc)

    objects = OrderedDict{String, CIMObject}()

    childs = copy(children(rdf))
    midx = findall(is_metadata, childs)
    if isnothing(midx)
        error("No md:FullModel metadata found in file: $filepath")
    elseif length(midx) > 1
        error("Found more than one md:FullModel metadata in file: $filepath")
    end
    metadata = parse_metadata(childs[only(midx)])
    deleteat!(childs, midx)

    for el in childs
        if is_object(el)
            obj = CIMObject(el, metadata.profile)
            objects[obj.id] = obj
        else
            @warn "Skipping $(tag(el)), no parser for this element type."
        end
    end

    # Create CIMFile with metadata
    cim_file = CIMFile(
        metadata.profile,
        metadata.uuid,
        metadata.created,
        metadata.scenario_time,
        metadata.dependencies,
        metadata.modeling_authority,
        objects,
        filename
    )

    return cim_file
end

include("show.jl")

end
