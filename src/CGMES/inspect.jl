using Graphs
using GraphMakie: GraphMakie, graphplot!
using GraphMakie.Makie: Figure, Axis, Legend, Label, scatter!, hidespines!, hidedecorations!, Makie, DataInspector
using Base.Docs: HTML


function inspect_collection(collection::AbstractCIMCollection; filter_out=String[], size=(2000,1500), hl1=[], hl2=[], seed=1, edge_labels=true, node_labels=:long)
    # Extract nodes from collection
    nodes = collect(values(objects(collection)))

    # Apply filtering
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodes)
    end

    # Create base plot
    fig = _plot_nodelist(nodes; size=size, hl1=hl1, hl2=hl2, seed, edge_labels, node_labels)

    # Add filter information at the bottom
    filter_text = if isempty(filter_out)
        "Filters: None applied"
    else
        "Filters: Excluded classes containing: " * join(filter_out, ", ")
    end

    # Add node count information
    total_nodes = length(objects(collection))
    filtered_nodes = length(nodes)
    info_text = "Nodes: $filtered_nodes/$total_nodes shown"

    # Update the existing label with filter information
    # if !isnothing(fig)
    #     Label(fig[3, 1], filter_text * "\n" * info_text,
    #           halign=:left, valign=:top, tellwidth=false, tellheight=true, justification=:left)
    # end

    return fig
end

function inspect_node(node::CIMObject; stop_classes=String[], filter_out=String[], max_depth=100, size=(2000,1500), seed=1, edge_labels=true, node_labels=:long)
    # Discover connected nodes recursively, filtering during discovery
    nodes, stop_nodes = discover_nodes(node, stop_classes; filter_out, max_depth)

    # Create visualization using the shared plotting function
    # Root node gets hl1, stop nodes get hl2
    return _plot_nodelist(nodes; size=size, hl1=[node], hl2=stop_nodes, seed, edge_labels, node_labels)
end

function generate_graphplot_args(nodes::Vector{CIMObject}; hl1=[], hl2=[], seed, edge_labels=true, node_labels=:long)
    if isempty(nodes)
        @warn "No nodes found to plot"
        return nothing
    end

    ids = [n.id for n in nodes]

    # Create node labels based on node_labels parameter
    node_label_data = if node_labels == :long
        object_text.(nodes)
    elseif node_labels == :short
        [n.class_name for n in nodes]
    elseif node_labels == :none
        String[]
    else
        error("node_labels must be :long, :short, or :none")
    end

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
    edge_profiles = Vector{Symbol}()

    for (source_idx, node) in enumerate(nodes)
        # First check base object properties
        for (key, value) in node.properties
            if value isa CIMRef && !startswith(value.id, "http")
                target_idx = findfirst(id -> id == value.id, ids)
                if !isnothing(target_idx)
                    e = source_idx => target_idx
                    existing_edge = findfirst(isequal(e), edges)
                    if isnothing(existing_edge)
                        push!(edges, source_idx => target_idx)
                        push!(edge_names, key)
                        push!(edge_profiles, node.profile)  # Base object profile
                    else
                        edge_names[existing_edge] *= " + " * key
                    end
                end
            end
        end

        # Then check extension properties
        for ext in node.extension
            for (key, value) in ext.source.properties
                if value isa CIMRef && !startswith(value.id, "http")
                    target_idx = findfirst(id -> id == value.id, ids)
                    if !isnothing(target_idx)
                        e = source_idx => target_idx
                        existing_edge = findfirst(isequal(e), edges)
                        if isnothing(existing_edge)
                            push!(edges, source_idx => target_idx)
                            push!(edge_names, key)
                            push!(edge_profiles, ext.source.profile)  # Extension profile
                        else
                            edge_names[existing_edge] *= " + " * key
                        end
                    end
                end
            end
        end
    end

    # Sort edges by source first, then by destination
    perm = sortperm(edges, by = e -> (e.first, e.second))
    edges_sorted = edges[perm]
    edge_names_sorted = edge_names[perm]
    edge_profiles_sorted = edge_profiles[perm]

    # Create edge colors based on property source profiles
    edge_colors = [get(profile_color_map, p, :gray) for p in edge_profiles_sorted]

    # Handle edge labels based on edge_labels parameter
    edge_label_data = edge_labels ? edge_names_sorted : nothing

    # Create graph
    g = SimpleDiGraph(length(nodes))
    for e in edges_sorted
        add_edge!(g, e.first, e.second)
    end

    # Generate tooltip labels for native data inspector
    tooltip_labels = generate_node_tooltips(nodes)

    # Create graphplot arguments
    args = (
        layout = GraphMakie.Stress(; seed),
        nlabels = node_label_data,
        elabels = edge_label_data,
        node_color = colors,
        node_size = node_sizes,
        edge_color = edge_colors,
        edge_width = 2,
        arrow_shift = :end,
        arrow_size = 15,
        elabels_fontsize = 8,
        nlabels_distance = 5,
        node_attr = (; inspector_label = (self, i, pos) -> tooltip_labels[i]),
        edge_attr = (; inspectable = false),
        arrow_attr = (; inspectable = false),
    )

    # Return graph and arguments
    return g, args
end

function _plot_nodelist(nodes::Vector{CIMObject}; size=(1000, 1000), hl1=[], hl2=[], seed, edge_labels=true, node_labels=:long)
    result = generate_graphplot_args(nodes; hl1, hl2, seed, edge_labels, node_labels)
    if result === nothing
        return nothing
    end

    g, args = result

    # Create GraphMakie plot with legend
    fig = Figure(; size=size)
    ax = Axis(fig[2,1])

    # Enable data inspector for interactive backends
    if occursin("GL", string(Makie.current_backend()))
        DataInspector(ax)
    end

    graphplot!(ax, g; args...)
    hidedecorations!(ax)
    hidespines!(ax)

    # Recreate legend data locally
    profiles = [obj.profile for obj in nodes]
    profile_color_map = Dict(
        :DiagramLayout => :red,
        :Dynamics => :blue,
        :GeographicalLocation => :green,
        :StateVariables => :orange,
        :Topology => :purple,
        :Equipment => :brown
    )

    # Add profile color legend below the axis
    unique_profiles_in_data = unique(profiles)
    legend_colors = [profile_color_map[profile] for profile in unique_profiles_in_data]
    legend_labels = [string(profile) for profile in unique_profiles_in_data]

    # Create legend with colored markers in horizontal orientation
    Legend(fig[1, 1],
        [scatter!(ax, Float64[], Float64[], color=color, markersize=15) for color in legend_colors],
        legend_labels,
        "CGMES Profiles",
        orientation = :horizontal,
        framevisible=false,
        tellheight=true,
        tellwidth=false,
        )

    return fig
end

function inspect_comparison(comparison::CIMCollectionComparison; size=(2000, 1000), seed=1, edge_labels=true, node_labels=:long, filter_out=String[])
    # Extract nodes from both collections
    nodesA = collect(values(objects(comparison.A)))
    nodesB = collect(values(objects(comparison.B)))

    # Apply filtering to both collections
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodesA)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodesB)
    end

    # Generate graphplot arguments for both collections
    resultA = generate_graphplot_args(nodesA; seed, edge_labels, node_labels)
    resultB = generate_graphplot_args(nodesB; seed, edge_labels, node_labels)

    if resultA === nothing || resultB === nothing
        @warn "No nodes found to plot in one or both collections"
        return nothing
    end

    gA, argsA = resultA
    gB, argsB = resultB

    # Calculate positions for collection A
    positionsA = argsA.layout(gA)

    # Create node ID to index mapping for both graphs
    idsA = [n.id for n in nodesA]
    idsB = [n.id for n in nodesB]

    # Identify matched nodes using concise findall approach
    matched_indices_A = findall(n -> n.id ∈ keys(comparison.matches_a_to_b), nodesA)
    matched_indices_B = findall(n -> n.id ∈ keys(comparison.matches_b_to_a), nodesB)

    # Build pin dictionary for collection B
    pin_dict = Dict{Int, Tuple{Float64, Float64}}()
    for (idA, idB) in comparison.matches_a_to_b
        idxA = findfirst(==(idA), idsA)
        idxB = findfirst(==(idB), idsB)

        if !isnothing(idxA) && !isnothing(idxB) && idxA <= length(positionsA)
            pin_dict[idxB] = (positionsA[idxA][1], positionsA[idxA][2])
        end
    end

    # Override colors for matched nodes (gray them out)
    argsA.node_color[matched_indices_A] .= :lightgray
    argsB.node_color[matched_indices_B] .= :lightgray

    for (i, e) in enumerate(edges(gA))
        if e.src ∈ matched_indices_A && e.dst ∈ matched_indices_A
            argsA.edge_color[i] = :lightgray
        end
    end
    for (i, e) in enumerate(edges(gB))
        if e.src ∈ matched_indices_B && e.dst ∈ matched_indices_B
            argsB.edge_color[i] = :lightgray
        end
    end


    # Create updated layout for collection B with pinned positions
    layoutB = GraphMakie.Stress(; seed, pin=pin_dict)
    argsB = merge(argsB, (; layout = layoutB))

    # Create side-by-side figure
    fig = Figure(; size=size)

    # Left axis for collection A
    axA = Axis(fig[2,1], title="Collection A")
    # Right axis for collection B
    axB = Axis(fig[2,2], title="Collection B")

    # Enable data inspector for interactive backends
    if occursin("GL", string(Makie.current_backend()))
        DataInspector(axA)
        DataInspector(axB)
    end

    # Plot both graphs
    graphplot!(axA, gA; argsA...)
    graphplot!(axB, gB; argsB...)

    hidedecorations!.([axA, axB])
    hidespines!.([axA, axB])

    # Recreate legend data locally
    profilesA = [obj.profile for obj in nodesA]
    profilesB = [obj.profile for obj in nodesB]
    profile_color_map = Dict(
        :DiagramLayout => :red,
        :Dynamics => :blue,
        :GeographicalLocation => :green,
        :StateVariables => :orange,
        :Topology => :purple,
        :Equipment => :brown
    )

    # Add combined profile legend
    all_profiles = unique([profilesA; profilesB])
    legend_colors = [profile_color_map[profile] for profile in all_profiles]
    legend_labels = [string(profile) for profile in all_profiles]

    Legend(fig[1, 1:2],
        [scatter!(axA, Float64[], Float64[], color=color, markersize=15) for color in legend_colors],
        legend_labels,
        "CGMES Profiles",
        orientation = :horizontal,
        framevisible=false,
        tellheight=true,
        tellwidth=false,
        )

    # Add comparison info
    match_count = length(comparison.matches_a_to_b)
    total_a = length(nodesA)
    total_b = length(nodesB)
    info_text = "Matched: $match_count | A: $total_a nodes | B: $total_b nodes"

    Label(fig[3, 1:2], info_text, fontsize=12)

    return fig
end

function discover_nodes(start_node::CIMObject, stop_classes; filter_out=String[], max_depth=10)
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
                recursive_discover!(value.target, depth + 1)
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
                recursive_discover!(source_obj, depth + 1)
            elseif source_obj isa CIMExtension
                recursive_discover!(source_obj.base.target, depth + 1)
            end
        end
    end

    recursive_discover!(start_node, 1)
    return nodes, stop_nodes
end

function object_text(obj::CIMObject)
    if is_class(obj, "SvPowerFlow")
        props = properties(obj)
        """
        SvPowerFlow
        P=$(props["p"])
        Q=$(props["q"])
        """
    elseif is_class(obj, "SvVoltage")
        props = properties(obj)
        """
        SvVoltage
        V=$(props["v"])
        δ=$(props["angle"])
        """
    elseif is_class(obj, "SvTapStep")
        props = properties(obj)
        """
        SvTapStep
        pos=$(props["position"])
        """
    elseif is_class(obj, "ConformLoad")
        props = properties(obj)
        """
        ConformLoad
        $(getname(obj))
        P=$(props["EnergyConsumer.p"])
        Q=$(props["EnergyConsumer.q"])
        """
    elseif is_class(obj, "SynchronousMachine")
        props = properties(obj)
        """
        SynchronousMachine
        $(getname(obj))
        P=$(props["RotatingMachine.p"])
        Q=$(props["RotatingMachine.q"])
        """
    elseif is_class(obj, "RegulatingControl")
        props = properties(obj)
        """
        RegulatingControl
        $(getname(obj))
        Vref=$(props["targetValue"])
        """
    else
        obj.class_name * (hasname(obj) ? "\n\"" * getname(obj) * "\"" : "")
    end
end

function get_graphplot(fig)
    sc = fig.scene;

    # Find all axes and filter for those with graphplots
    axes_with_graphplots = filter(fig.content) do c
        c isa Axis && any(plot -> isa(plot, GraphMakie.GraphPlot), c.scene.plots)
    end

    if length(axes_with_graphplots) != 1
        error("Expected exactly one axis with a graphplot, found $(length(axes_with_graphplots))")
    end

    ax = axes_with_graphplots[1]
    gp = only(filter(plot -> isa(plot, GraphMakie.GraphPlot), ax.scene.plots))
    ax, gp
end

function html_hover_map(fig=Makie.current_figure())
    ax, gp = get_graphplot(fig)
    positions = gp[:node_pos][]
    markersize = gp[:nodeplot_markersize][]

    # get the labels from the graphplot inspector function
    labelf = gp[:node_attr][][:inspector_label][]
    labels = [labelf(nothing, i, nothing) for i in eachindex(positions)]

    # Use the same approach as scratch.jl - much simpler!
    rel_px_pos = Makie.project.(Ref(ax.scene), positions)
    px_pos = Ref(ax.scene.viewport[].origin) .+ rel_px_pos

    # Get figure dimensions
    width, height = fig.scene.viewport[].widths

    # Calculate relative positions as fractions (0-1) then convert to percentages
    hover_zones = []
    # Handle case where markersize might be a single value or vector
    sizes = markersize isa AbstractVector ? markersize : fill(markersize, length(px_pos))

    for (i, (px, size, label)) in enumerate(zip(px_pos, sizes, labels))
        # Convert to relative position (0-1)
        rel_pos = px ./ [width, height]

        # Convert to percentage and flip Y coordinate for HTML
        x_pct = rel_pos[1] * 100
        y_pct = (1 - rel_pos[2]) * 100  # Flip Y for HTML coordinate system

        # Calculate zone dimensions directly as percentages of figure dimensions
        zone_width_pct = (size / width) * 100
        zone_height_pct = (size / height) * 100

        push!(hover_zones, (x_pct, y_pct, zone_width_pct, zone_height_pct, label, i))
    end

    # Generate HTML with CSS and JavaScript
    html_string = """
    <script>
    // Find the previous image element and wrap it with hover functionality
    (function() {
        var script = document.currentScript;
        var img = script.previousElementSibling;

        // Find the preceding img element
        while (img && img.tagName !== 'IMG') {
            img = img.previousElementSibling;
        }

        if (!img) return; // No image found

        function setupHoverZones() {
            // Create wrapper div
            var wrapper = document.createElement('div');
            wrapper.className = 'graph-hover-container';
            wrapper.style.cssText = 'position: relative; display: inline-block;';

            // Insert wrapper before img and move img into wrapper
            img.parentNode.insertBefore(wrapper, img);
            wrapper.appendChild(img);

            // Ensure wrapper is exactly the same size as the image
            wrapper.style.width = img.offsetWidth + 'px';
            wrapper.style.height = img.offsetHeight + 'px';

        // Create hover zones container
        var hoverZones = document.createElement('div');
        hoverZones.className = 'hover-zones';
        hoverZones.style.cssText = 'position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none;';
        wrapper.appendChild(hoverZones);

        // Create tooltip
        var tooltip = document.createElement('div');
        tooltip.id = 'tooltip-' + Math.random().toString(36).substr(2, 9);
        tooltip.style.cssText = `position: absolute;
                                background: rgba(0,0,0,0.8);
                                color: white;
                                padding: 5px 10px;
                                border-radius: 4px;
                                font-size: 10px;
                                font-family: monospace;
                                white-space: pre-line;
                                pointer-events: none;
                                z-index: 20;
                                display: none;
                                max-width: 400px;
                                word-wrap: break-word;`;
        wrapper.appendChild(tooltip);

        // Create hover zone data
        var hoverZoneData = ["""

    for (i, (x_pct, y_pct, zone_width_pct, zone_height_pct, label, idx)) in enumerate(hover_zones)
        escaped_label = replace(replace(replace(string(label), "\\" => "\\\\"), "\"" => "\\\""), "\n" => "\\n")
        if i > 1
            html_string *= ",\n            "
        end
        html_string *= """
            {x: $(x_pct), y: $(y_pct), width: $(zone_width_pct), height: $(zone_height_pct), label: "$(escaped_label)", node: $(idx)}"""
    end

    html_string *= """
        ];

        // Create hover zones with proper aspect ratio
        hoverZoneData.forEach(function(zoneData, i) {
            var zone = document.createElement('div');
            zone.className = 'hover-zone';

            // Use the width and height percentages calculated directly in Julia
            var zoneWidth = zoneData.width;
            var zoneHeight = zoneData.height;

            zone.style.cssText = `position: absolute;
                                 left: \${zoneData.x - zoneWidth/2}%;
                                 top: \${zoneData.y - zoneHeight/2}%;
                                 width: \${zoneWidth}%;
                                 height: \${zoneHeight}%;
                                 pointer-events: all;
                                 cursor: pointer;
                                 z-index: 10;
                                 border: none;
                                 background: transparent;`;
            zone.setAttribute('data-label', zoneData.label);
            zone.setAttribute('data-node', zoneData.node);
            hoverZones.appendChild(zone);
        });


        // Add event listeners to hover zones
        var zones = hoverZones.querySelectorAll('.hover-zone');
        zones.forEach(function(zone) {
            zone.addEventListener('mouseenter', function(e) {
                var label = this.getAttribute('data-label');
                tooltip.innerHTML = label;
                tooltip.style.display = 'block';

                // Position tooltip
                var rect = wrapper.getBoundingClientRect();
                var zoneRect = this.getBoundingClientRect();
                tooltip.style.left = (zoneRect.left - rect.left + zoneRect.width/2) + 'px';
                tooltip.style.top = (zoneRect.top - rect.top - tooltip.offsetHeight - 5) + 'px';

                // Adjust if tooltip goes outside container
                var tooltipRect = tooltip.getBoundingClientRect();
                if (tooltipRect.right > rect.right) {
                    tooltip.style.left = (rect.right - rect.left - tooltipRect.width - 5) + 'px';
                }
                if (tooltipRect.left < rect.left) {
                    tooltip.style.left = '5px';
                }
                if (tooltipRect.top < rect.top) {
                    tooltip.style.top = (zoneRect.bottom - rect.top + 5) + 'px';
                }
            });

            zone.addEventListener('mouseleave', function(e) {
                tooltip.style.display = 'none';
            });
        });
        }

        // Wait for image to load before setting up hover zones
        if (img.complete && img.offsetWidth > 0) {
            // Image already loaded
            setupHoverZones();
        } else {
            // Wait for image to load
            img.addEventListener('load', setupHoverZones);
        }
    })();
    </script>
    """

    return HTML(html_string)
end

function generate_node_tooltips(nodes::Vector{CIMObject})
    tooltip_labels = String[]
    for node in nodes
        label_parts = []

        # Add classname
        push!(label_parts, node.class_name)

        # Add name if available
        if hasname(node)
            push!(label_parts, "\"$(getname(node))\"")
        end

        # Get all properties (including extensions)
        props = properties(node)

        # Filter out resolved references within dataset and name properties
        # Keep unresolved references (external or filtered out objects)
        filtered_props = []
        for (key, value) in props
            # Include if it's not a name property and either:
            # - Not a CIMRef at all, or
            # - A CIMRef that's not resolved (external reference or filtered out object)
            if !contains(lowercase(key), "name") &&
               (!(value isa CIMRef) || !value.resolved)
                # Display unresolved references as "unresolved ref" instead of printing the object
                display_value = (value isa CIMRef && !value.resolved) ? "unresolved ref" : value
                push!(filtered_props, "$key = $display_value")
            end
        end

        # Add filtered properties to label parts
        if !isempty(filtered_props)
            append!(label_parts, filtered_props)
        else
            push!(label_parts, "no properties")
        end

        push!(tooltip_labels, join(label_parts, "\n"))
    end

    return tooltip_labels
end
