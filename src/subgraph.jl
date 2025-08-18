export is_terminal, is_class, is_lineend, discover_subgraph

is_class(x, class::String) = (typeof(x) <: CIMObject) && (x.class_name == class)
is_class(x, class::Regex) = (typeof(x) <: CIMObject) && (contains(x.class_name, class))
is_class(x, classes) = any(class -> is_class(x, class), classes)
is_class(class_es) = Base.Fix2(is_class, class_es)

is_terminal(t) = is_class(t, "Terminal")

function is_injector(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
end

BRANCH_CLASSES = ["ACLineSegment"]
function is_lineend(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
    any(class -> is_class(eq, class), BRANCH_CLASSES)
end

STOP_BACKREF = ["BaseVoltage", "VoltageLevel", "OperationalLimitType", "Substation"]

"""
    discover_subgraph(root; kwargs)::CIMCollection

keyword arguments
- `nobackref = is_class(STOP_BACKREF)`: don't follow back references on those nodes
- `maxdepth = 100`: maximum depth to explore
- `filter_out = x -> false`: filter out nodes that match this predicate
"""
function discover_subgraph(
    root::CIMObject;
    nobackref = is_class(STOP_BACKREF),
    maxdepth = 100,
    filter_out = x -> false,
)
    objects = OrderedDict{String, CIMObject}()
    extensions = Vector{CIMExtension}()

    function recursive_discover!(node::CIMObject, depth::Int)
        # Check if already processed (cycle detection)
        haskey(objects, node.id) && return

        # Check if this node should be filtered out
        filter_out(node) && return

        # Copy and add current node
        objects[node.id] = copy(node)

        # Copy and add extensions for this node
        for ext_backref in node.extension
            @assert ext_backref.source isa CIMExtension
            push!(extensions, copy(ext_backref.source))
        end

        # Check if we've reached maximum depth
        if depth >= maxdepth
            @warn "Maximum recursion depth ($maxdepth) reached for node $(node.class_name) ($(node.id)). Stopping further exploration."
            return
        end

        # Explore forward references (properties)
        for (key, ref) in properties(node)
            ref isa CIMRef || continue
            is_external_ref(ref) && continue  # Skip external references
            @assert is_resolved(ref) "CIMRef $ref should be resolved before discovery."
            recursive_discover!(follow_ref(ref), depth + 1)
        end

        # Explore backward references - stop for nobackref nodes
        nobackref(node) && return

        for backref in node.references
            source = follow_ref(backref)
            if source isa CIMObject
                recursive_discover!(source, depth + 1)
            elseif source isa CIMExtension
                recursive_discover!(follow_ref(source.base), depth + 1)
            end
        end
    end

    recursive_discover!(root, 1)

    collection = CIMCollection(objects, extensions)
    resolve_references!(collection)
    return collection
end
