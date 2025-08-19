using Graphs
using GraphMakie: GraphMakie, graphplot!
using GraphMakie.Makie: Figure, Axis, Legend, Label, scatter!, hidespines!, hidedecorations!, Makie
using Base.Docs: HTML


function inspect_collection(collection::AbstractCIMCollection; filter_out=String[], size=(2000,1500), hl1=[], hl2=[], seed=1)
    # Extract nodes from collection
    nodes = collect(values(objects(collection)))

    # Apply filtering
    if !isempty(filter_out)
        filter!(n -> !any(s -> contains(n.class_name, s), filter_out), nodes)
    end

    # Create base plot
    fig = _plot_nodelist(nodes; size=size, hl1=hl1, hl2=hl2, seed)

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
    if !isnothing(fig)
        Label(fig[2, 1:2], filter_text * "\n" * info_text,
              halign=:left, valign=:top, tellwidth=false, tellheight=true, justification=:left)
    end

    return fig
end

function inspect_node(node::CIMObject; stop_classes=String[], filter_out=String[], max_depth=100, size=(2000,1500), seed=1)
    # Discover connected nodes recursively, filtering during discovery
    nodes, stop_nodes = discover_nodes(node, stop_classes; filter_out, max_depth)

    # Create visualization using the shared plotting function
    # Root node gets hl1, stop nodes get hl2
    return _plot_nodelist(nodes; size=size, hl1=[node], hl2=stop_nodes, seed)
end

function _plot_nodelist(nodes::Vector{CIMObject}; size=(1000, 1000), hl1=[], hl2=[], seed)
    if isempty(nodes)
        @warn "No nodes found to plot"
        return nothing
    end

    ids = [n.id for n in nodes]

    # Create short representation vector for visualization
    short_repr = object_text.(nodes)

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
        layout = GraphMakie.Stress(; seed),
        nlabels = short_repr,
        elabels = edge_names_sorted,
        node_color = colors,
        node_size = node_sizes,
        edge_color = edge_colors,
        edge_width = 2,
        arrow_shift = :end,
        arrow_size = 15,
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

function html_hover_map(fig, labels)
    sc = fig.scene;
    ax = only(filter(c -> c isa Axis, fig.content))
    gp = only(ax.scene.plots) # graphplot
    positions = gp[:node_pos][]
    markersize = gp[:nodeplot_markersize][]

    # Use the same approach as scratch.jl - much simpler!
    rel_px_pos = Makie.project.(Ref(ax.scene), positions)
    px_pos = Ref(ax.scene.viewport[].origin) .+ rel_px_pos

    # Get figure dimensions
    width, height = sc.viewport[].widths

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
                                font-size: 12px;
                                white-space: pre-line;
                                pointer-events: none;
                                z-index: 20;
                                display: none;
                                max-width: 200px;
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
                                 border: 2px solid red;
                                 background: rgba(255, 0, 0, 0.2);`;
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
