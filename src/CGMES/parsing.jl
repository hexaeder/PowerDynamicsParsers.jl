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
            stringvalue = simple_value(p)
            value = if !isnothing(tryparse(Int, stringvalue))
                tryparse(Int, stringvalue)
            elseif !isnothing(tryparse(Float64, stringvalue))
                tryparse(Float64, stringvalue)
            elseif !isnothing(tryparse(Bool, stringvalue))
                tryparse(Bool, stringvalue)
            else
                stringvalue
            end
            _add_property!(props, key, value)
        elseif is_reference(p)
            _add_property!(props, key, CIMRef(p))
        else
            @warn "Skipping property $p, no parser defined yet."
        end
    end
    props
end
function _add_property!(props, key, value)
    if haskey(props, key)
        newvec = vcat(props[key], value)
        if !(newvec isa Vector{CIMRef})
            @warn "Multiple values for property $key which are *not* CIMRef, this is not handled yet."
        end
        props[key] = newvec
    else
        props[key] = value
    end
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

    # Create CIMCollection and then CIMFile with metadata
    collection = CIMCollection(objects, extensions)
    cim_file = CIMFile(
        collection,
        metadata.profile,
        metadata.uuid,
        metadata.created,
        metadata.scenario_time,
        metadata.dependencies,
        metadata.modeling_authority,
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
    return dataset
end
