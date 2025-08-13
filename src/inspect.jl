using Graphs
using GraphMakie: GraphMakie, graphplot!
using GraphMakie.Makie: Figure, Axis, Legend, Label, scatter!, hidespines!, hidedecorations!


function inspect_dataset(dataset; filter_out=String[], size=(2000,1500))
    # Extract nodes from dataset
    nodes = objects(dataset)

    # Apply filtering
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodes)
    end

    # Create base plot
    fig = _plot_nodelist(nodes; size=size)

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

function inspect_node(node::CIMObject; stop_classes::Vector{String}=String[], size=(2000,1500))
    # Discover connected nodes recursively
    nodes = discover_nodes(node, stop_classes)

    # Create visualization using the shared plotting function
    return _plot_nodelist(nodes; size=size, highlight=[node])
end

function _plot_nodelist(nodes::Vector{CIMObject}; size=(1000, 1000), highlight::Vector{CIMObject}=CIMObject[])
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

    # Create node sizes vector with highlights
    highlight_ids = [node.id for node in highlight]
    node_sizes = [node.id in highlight_ids ? 40 : 20 for node in nodes]

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

function discover_nodes(start_node::CIMObject, stop_classes::Vector{String})
    nodes = Vector{CIMObject}()

    function recursive_discover!(node::CIMObject)
        # Check if already processed (cycle detection)
        if any(n -> n.id == node.id, nodes)
            return
        end

        # Add current node
        push!(nodes, node)

        # Check if this node class should stop discovery
        if any(stop_class -> contains(node.class_name, stop_class), stop_classes)
            return  # Stop exploration but keep the node
        end

        # Explore forward references (properties)
        props = properties(node)
        for (key, value) in props
            if value isa CIMRef && value.resolved && !startswith(value.id, "http")
                target_node = value.target
                if !isnothing(target_node) && target_node isa CIMObject
                    recursive_discover!(target_node)
                end
            end
        end

        # Explore backward references
        for backref in node.references
            source_obj = backref.source
            if source_obj isa CIMObject
                recursive_discover!(source_obj)
            end
        end
    end

    recursive_discover!(start_node)
    return nodes
end
