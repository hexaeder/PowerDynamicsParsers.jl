module PowerDynamicsCGMES

using XML: XML, Node, nodetype, attributes, children, tag,
           is_simple, simple_value
using OrderedCollections: OrderedDict

export rdf_node, CIMObject, CIMRef, CIMBackref, CIMFile, CIMDataset
export plain_name, is_reference, is_object, is_extension, parse_metadata
export get_by_id, resolve_references!

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
    nodetype(el) == XML.Element && contains(tag(el), r"^cim:") && haskey(attributes(el), "rdf:ID")
end

function is_extension(el::Node)
    nodetype(el) == XML.Element && contains(tag(el), r"^cim:") && haskey(attributes(el), "rdf:about")
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
    props = _parseprops(el, name)
    CIMObject(profile, id, name, props)
end

function CIMExtension(el::Node, profile)
    name = plain_name(el, ["cim", "entsoe"])
    about = get(attributes(el), "rdf:about", "")
    base = CIMRef(about)
    props = _parseprops(el, name)
    CIMExtension(profile, base, name, props)
end

function _parseprops(el::Node, name::AbstractString)
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
    props
end

function CIMFile(filepath::String)
    filename = basename(filepath)
    doc = XML.read(filepath, Node)
    rdf = rdf_node(doc)

    childs = copy(children(rdf))
    midx = findall(is_metadata, childs)
    if isnothing(midx)
        error("No md:FullModel metadata found in file: $filepath")
    elseif length(midx) > 1
        error("Found more than one md:FullModel metadata in file: $filepath")
    end
    metadata = parse_metadata(childs[only(midx)])
    deleteat!(childs, midx)

    objects = OrderedDict{String, CIMObject}()
    extensions = Vector{CIMExtension}()

    for el in childs
        if is_object(el)
            obj = CIMObject(el, metadata.profile)
            objects[obj.id] = obj
        elseif is_extension(el)
            ext = CIMExtension(el, metadata.profile)
            push!(extensions, ext)
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
        extensions,
        filename
    )

    return cim_file
end

function CIMDataset(directory::String)
    files = OrderedDict{Symbol, CIMFile}()

    # Check if directory exists
    if !isdir(directory)
        error("Directory not found: $directory")
    end

    # Find all XML files in directory
    xml_files = filter(f -> endswith(lowercase(f), ".xml"), readdir(directory))

    if isempty(xml_files)
        @warn "No XML files found in directory: $directory"
    end

    # Parse each XML file
    for filename in xml_files
        filepath = joinpath(directory, filename)
        try
            cim_file = CIMFile(filepath)
            profile = cim_file.profile

            # Check for profile conflicts
            if haskey(files, profile)
                @warn "Multiple files found for profile $profile. Overwriting $(files[profile].filename) with $filename"
            end

            files[profile] = cim_file
        catch e
            @warn "Failed to parse file $filename: $e"
        end
    end

    dataset = CIMDataset(files, directory)
    resolve_references!(dataset)
end

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

hasname(obj::Union{CIMObject, CIMExtension}) = haskey(obj.properties, "name")
getname(obj::Union{CIMObject, CIMExtension}) = obj.properties["name"]


include("show.jl")

end
