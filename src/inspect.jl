using Graphs
using GraphMakie: GraphMakie, graphplot!
using GraphMakie.Makie: Figure, Axis, Legend, Label, scatter!, hidespines!, hidedecorations!


function inspect_dataset(dataset; filter_out=String[], size=(2000,1500), hl1=[], hl2=[])
    # Extract nodes from dataset
    nodes = objects(dataset)

    # Apply filtering
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodes)
    end

    # Create base plot
    fig = _plot_nodelist(nodes; size=size, hl1=hl1, hl2=hl2)

    # Add filter information at the bottom
    filter_text = if isempty(filter_out)
        "Filters: None applied"
    else
        "Filters: Excluded classes containing: " * join(filter_out, ", ")
    end

    # Add node count information
    total_nodes = length(objects(dataset))
    filtered_nodes = length(nodes)
    info_text = "Nodes: $filtered_nodes/$total_nodes shown"

    # Update the existing label with filter information
    if !isnothing(fig)
        Label(fig[2, 1:2], filter_text * "\n" * info_text,
              halign=:left, valign=:top, tellwidth=false, tellheight=true, justification=:left)
    end

    return fig
end

function inspect_node(node::CIMObject; stop_classes=String[], filter_out=String[], max_depth=100, size=(2000,1500))
    # Discover connected nodes recursively, filtering during discovery
    nodes, stop_nodes = discover_nodes(node, stop_classes; filter_out, max_depth)

    # Create visualization using the shared plotting function
    # Root node gets hl1, stop nodes get hl2
    return _plot_nodelist(nodes; size=size, hl1=[node], hl2=stop_nodes)
end

function _plot_nodelist(nodes::Vector{CIMObject}; size=(1000, 1000), hl1=[], hl2=[])
    if isempty(nodes)
        @warn "No nodes found to plot"
        return nothing
    end

    ids = [n.id for n in nodes]

    # Create short representation vector for visualization
    short_repr = [obj.class_name * (hasname(obj) ? "\n\"" * getname(obj) * "\"" : "") for obj in nodes]

    # Create profiles vector showing which profile each node belongs to
    profiles = [obj.profile for obj in nodes]

    # Create color mapping for profiles
    profile_color_map = Dict(
        :DiagramLayout => :red,
        :Dynamics => :blue,
        :GeographicalLocation => :green,
        :StateVariables => :orange,
        :Topology => :purple,
        :Equipment => :brown
    )

    # Create colors vector for visualization
    colors = [get(profile_color_map, p, :gray) for p in profiles]

    hl1_ids = [node.id for node in hl1]
    hl2_ids = [node.id for node in hl2]

    node_sizes = [
        if node.id in hl1_ids
            70
        elseif node.id in hl2_ids
            40
        else
            20
        end
        for node in nodes
    ]

    # Create edges vector representing references between objects
    edges = Vector{Pair{Int,Int}}()
    edge_names = Vector{String}()

    for (source_idx, node) in enumerate(nodes)
        props = properties(node)
        for (key, value) in props
            if value isa CIMRef && !startswith(value.id, "http")
                target_idx = findfirst(id -> id == value.id, ids)
                if !isnothing(target_idx)
                    e = source_idx => target_idx
                    existing_edge = findfirst(isequal(e), edges)
                    if isnothing(existing_edge)
                        push!(edges, source_idx => target_idx)
                        push!(edge_names, key)
                    else
                        edge_names[existing_edge] *= " + " * key
                    end
                end
            end
        end
    end

    # Sort edges by source first, then by destination
    perm = sortperm(edges, by = e -> (e.first, e.second))
    edges_sorted = edges[perm]
    edge_names_sorted = edge_names[perm]

    # Create graph
    g = SimpleDiGraph(length(nodes))
    for e in edges_sorted
        add_edge!(g, e.first, e.second)
    end

    # Create GraphMakie plot with legend
    fig = Figure(; size=size)
    ax = Axis(fig[1,1])
    graphplot!(
        ax,
        g;
        layout = GraphMakie.Stress(),
        nlabels = short_repr,
        elabels = edge_names_sorted,
        node_color = colors,
        node_size = node_sizes,
        arrow_shift = :end,
        arrow_size = 10,
        elabels_fontsize = 8,
        nlabels_distance = 5,
    )
    hidedecorations!(ax)

    # Add profile color legend
    unique_profiles_in_data = unique(profiles)
    legend_colors = [profile_color_map[profile] for profile in unique_profiles_in_data]
    legend_labels = [string(profile) for profile in unique_profiles_in_data]

    # Create legend with colored markers
    Legend(fig[1, 2],
           [scatter!(ax, Float64[], Float64[], color=color, markersize=15) for color in legend_colors],
           legend_labels,
           "CGMES Profiles",
           framevisible=true,
           tellwidth=true,
           margin=(10, 10, 10, 10))

    return fig
end

function discover_nodes(start_node::CIMObject, stop_classes::Vector{String}; filter_out::Vector{String}=String[], max_depth::Int=10)
    nodes = Vector{CIMObject}()
    stop_nodes = Vector{CIMObject}()

    function recursive_discover!(node::CIMObject, depth::Int)
        # Check if already processed (cycle detection)
        if any(n -> n.id == node.id, nodes)
            return
        end

        # Check if this node class should stop discovery (skip for root node at depth 1)
        is_stop_node = depth > 1 && any(stop_class -> contains(node.class_name, stop_class), stop_classes)
        is_filtered_node = depth > 1 && any(filter_class -> contains(node.class_name, filter_class), filter_out)

        if is_filtered_node
            # Don't add filtered nodes to the results and don't explore through them
            return
        end

        # Add current node (only if not filtered)
        push!(nodes, node)

        # Check if we've reached maximum depth
        if depth >= max_depth
            @warn "Maximum recursion depth ($max_depth) reached for node $(node.class_name) ($(node.id)). Stopping further exploration."
            return
        end

        # Explore forward references (properties) - always continue even for stop nodes
        props = properties(node)
        for (key, value) in props
            if value isa CIMRef && value.resolved && !startswith(value.id, "http")
                target_node = value.target
                if !isnothing(target_node) && target_node isa CIMObject
                    # Skip traversal if target node would be filtered out
                    target_is_filtered = any(filter_class -> contains(target_node.class_name, filter_class), filter_out)
                    if !target_is_filtered
                        recursive_discover!(target_node, depth + 1)
                    end
                end
            end
        end

        # Explore backward references - stop for stop nodes
        if is_stop_node
            push!(stop_nodes, node)
            # Stop backward exploration but keep the node - forward exploration already done above
            return
        end

        for backref in node.references
            source_obj = backref.source
            if source_obj isa CIMObject
                # Skip traversal if source node would be filtered out
                source_is_filtered = any(filter_class -> contains(source_obj.class_name, filter_class), filter_out)
                if !source_is_filtered
                    recursive_discover!(source_obj, depth + 1)
                end
            end
        end
    end

    recursive_discover!(start_node, 1)
    return nodes, stop_nodes
end
