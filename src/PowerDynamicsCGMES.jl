module PowerDynamicsCGMES

using XML
using OrderedCollections: OrderedDict

export rdf_node, CIMObject, CIMRef, CIMBackref
export plain_name, is_reference, is_object

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

abstract type AbstractCIMReference end
struct CIMObject
    id::String
    class_name::String
    properties::OrderedDict{String, Any}
    backrefs::Vector{AbstractCIMReference}
    CIMObject(id, n, p) = new(id, n, p, AbstractCIMReference[])
end
struct CIMRef <: AbstractCIMReference
    id::String
    resolved::Bool
    target::Union{CIMObject, Nothing}

    CIMRef(id::String) = new(id, false, nothing)
end
struct CIMBackref <: AbstractCIMReference
    id::String
    target::CIMObject
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

CIMRef(el::Node) = CIMRef(attributes(el)["rdf:resource"])

# parser function
function CIMObject(el::Node)
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
    CIMObject(id, name, props)
end

include("show.jl")

end
