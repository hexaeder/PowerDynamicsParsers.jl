using Graphs
using GraphMakie: graphplot
using GraphMakie.Makie: Figure, Axis, Legend, Label, scatter!, hidespines!, hidedecorations!


"""
    inspect_dataset(dataset; filter_out=String[], figure_size=(1500,1500))

Create a graph visualization of a CIMDataset showing the relationships between CGMES objects.

# Arguments
- `dataset`: CIMDataset to visualize
- `filter_out`: Vector of strings - filter out nodes whose class_name contains any of these strings
- `figure_size`: Tuple specifying the figure dimensions

# Returns
- `Figure`: GraphMakie figure object

# Example
```julia
# Visualize all objects
fig = inspect_dataset(dataset)

# Filter out limits and points
fig = inspect_dataset(dataset; filter_out=["Limit", "Point"])
```
"""
function inspect_dataset(dataset; filter_out=String[], figure_size=(2000,1500))

    # Extract nodes from dataset
    nodes = objects(dataset)

    # Apply filtering
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodes)
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
    colors = [profile_color_map[p] for p in profiles]

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

    # Create GraphMakie plot with legend and filter info
    fig = Figure(; size=figure_size)
    ax = Axis(fig[1,1])
    graphplot!(
        ax,
        g;
        layout = GraphMakie.Stress(),
        nlabels = short_repr,
        elabels = edge_names_sorted,
        node_color = colors,
        node_size = 20,
        arrow_shift = :end,
        arrow_size = 10,
        elabels_fontsize = 8,
        nlabels_distance = 5,
    )
    # hidespines!(ax)
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

    # Add filter and node information using Label
    Label(fig[2, 1:2], filter_text * "\n" * info_text,
          halign=:left, valign=:top, tellwidth=false, tellheight=true, justification=:left)

    return fig
end
