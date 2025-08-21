export is_terminal, is_class, is_lineend, discover_subgraph, is_injector, is_busbar_section_terminal, reduce_complexity
export delete_unconnected, split_topologically

is_class(x, class::String) = (typeof(x) <: CIMObject) && (x.class_name == class)
is_class(x, class::Regex) = (typeof(x) <: CIMObject) && (contains(x.class_name, class))
is_class(x, classes) = any(class -> is_class(x, class), classes)
is_class(class_es) = Base.Fix2(is_class, class_es)

is_terminal(t) = is_class(t, "Terminal")

function is_injector(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
end

BRANCH_CLASSES = ["ACLineSegment", "PowerTransformer"]
function is_lineend(t)
    is_terminal(t) || return false
    eq = t["ConductingEquipment"]
    any(class -> is_class(eq, class), BRANCH_CLASSES)
end

function is_busbar_section_terminal(t)
    is_terminal(t) || return false
    is_class(t["ConductingEquipment"], "BusbarSection")
end

STOP_BACKREF = ["BaseVoltage", "VoltageLevel", "OperationalLimitType", "Substation", "LoadAggregate", "ConformLoadGroup", "LoadResponseCharacteristic"]

"""
    discover_subgraph(root; kwargs)::CIMCollection

keyword arguments
- `nobackref = is_class(STOP_BACKREF)`: don't follow back references on those nodes
   unless the backref is from a :StateVariables profile
- `maxdepth = 100`: maximum depth to explore
- `filter_out = x -> false`: filter out nodes that match this predicate
"""
function discover_subgraph(
    root::CIMObject;
    nobackref = is_class(STOP_BACKREF),
    maxdepth = 100,
    filter_out = x -> false,
    warn=true
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
        # unless it is a state variable profile! that we allways follow

        for backref in node.references
            source = base_object(backref)
            if !nobackref(node) || source.profile == :StateVariables
                recursive_discover!(source, depth + 1)
            end
        end
    end

    recursive_discover!(root, 1)

    collection = CIMCollection(objects, extensions)
    resolve_references!(collection; warn)
end

function Base.filter(f, collection::AbstractCIMCollection; warn=true)
    _objects = OrderedDict{String, CIMObject}()
    _extensions = Vector{CIMExtension}()

    for (id, obj) in objects(collection)
        if f(obj)
            _objects[id] = copy(obj)
            for ext_backref in obj.extension
                @assert ext_backref.source isa CIMExtension
                push!(_extensions, copy(ext_backref.source))
            end
        end
    end
    collection = CIMCollection(_objects, _extensions)
    resolve_references!(collection; warn)
end

function split_topologically(collection::CIMCollection; warn=true)
    # collection = CIMDataset(DATA)
    topnodes = collection("TopologicalNode")
    node_subgraphs = _discover_tpn_subgraph.(topnodes; warn)

    undiscovered_lineends = filter(is_lineend, collection("Terminal"))
    edge_subgraphs = CIMCollection[]
    while !isempty(undiscovered_lineends)
        lineend = popfirst!(undiscovered_lineends)
        subgraph = _discover_linened_subgraph(lineend; warn)
        push!(edge_subgraphs, subgraph)

        discovered_ids = [n.id for n in filter(is_lineend, subgraph("Terminal"))]
        foundidx = findall(n -> n.id ∈ discovered_ids, undiscovered_lineends)
        !isnothing(foundidx) && deleteat!(undiscovered_lineends, foundidx)
    end
    # sanity checks
    for subgraph in edge_subgraphs
        @assert length(subgraph("TopologicalNode")) == 2
    end
    for subgraph in node_subgraphs
        @assert length(subgraph("TopologicalNode")) == 1
    end

    (; node_subgraphs, edge_subgraphs)
end
function _discover_tpn_subgraph(t; warn)
    @assert is_class(t, "TopologicalNode") "Expected TopologicalNode, got $(t.class_name)"
    filter_out = n -> is_lineend(n) || is_busbar_section_terminal(n) || is_class(n, ["VoltageLevel", "Substation"])
    discover_subgraph(t; filter_out, warn)
end
function _discover_linened_subgraph(t; warn)
    @assert is_lineend(t) "Expected LineEnd, got $(t.class_name)"

    nobackref = is_class(vcat(STOP_BACKREF, "TopologicalNode", "OperationalLimitSet"))
    filter_out = is_class([r"Diagram", "Substation"])
    discover_subgraph(t; nobackref, filter_out, warn)
end


function reduce_complexity(collection)
    new_collection = filter(
        !is_class([
            "OperationalLimitType",
            "OperationalLimitSet",
            "VoltageLimit",
            "CurrentLimit",
            r"Diagram",
            "CoordinateSystem",
            r"Geographical",
            "Substation",
            "BaseVoltage",
            "PositionPoint",
            "Location"
        ]),
        collection; warn=false
    )
    delete_unconnected(new_collection; warn=false)
end

function delete_unconnected(collection::CIMCollection, keep=collection("TopologicalNode"); warn=true)
    nodes, g = to_digraph(collection)
    components = connected_components(g)

    new_nodes = CIMObject[]
    for c in components
        component_nodes = nodes[c]
        if any(n -> n in keep, component_nodes)
            append!(new_nodes, component_nodes)
        end
    end

    new_objects = OrderedDict{String, CIMObject}()
    for n in new_nodes
        new_objects[n.id] = copy(n)
    end
    new_extensions = Vector{CIMExtension}()
    for obj in new_nodes
        for ext_backref in obj.extension
            @assert ext_backref.source isa CIMExtension
            push!(new_extensions, copy(ext_backref.source))
        end
    end
    new_collection = CIMCollection(new_objects, new_extensions)
    resolve_references!(new_collection; warn)
end

function to_digraph(collection::CIMCollection)
    nodes = collect(values(objects(collection)))
    g = SimpleDiGraph(length(nodes))
    for (source_idx, node) in enumerate(nodes)
        for (k, v) in properties(node)
            if v isa CIMRef && v.resolved
                target = follow_ref(v)
                target_idx = findfirst(n -> n.id == target.id, nodes)
                !isnothing(target_idx) && add_edge!(g, source_idx, target_idx)
            end
        end
    end
    nodes, g
end
