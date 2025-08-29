# Helper function to count class occurrences
function _class_count(objects)
    counts = Dict{String, Int}()
    for obj in objects
        counts[obj.class_name] = get(counts, obj.class_name, 0) + 1
    end
    counts
end

# Helper function to format class count breakdown
function _format_class_breakdown(io::IO, class_counts::Dict{String, Int}, indent::String="    ")
    if !isempty(class_counts)
        for (class, count) in sort(collect(class_counts))
            println(io, indent, count, " ", class)
        end
    end
end

# Helper function to print content breakdown for AbstractCIMCollection types
function _print_content_breakdown(io::IO, collection)
    # Count and format class breakdowns
    object_counts = _class_count(values(objects(collection)))
    extension_counts = _class_count(extensions(collection))

    # Display objects with breakdown
    println(io, "  Objects: ", length(objects(collection)))
    _format_class_breakdown(io, object_counts)

    # Display extensions with breakdown
    println(io, "  Extensions: ", length(extensions(collection)))
    _format_class_breakdown(io, extension_counts)
end

# Helper function to show properties
function show_properties(io::IO, mime::MIME"text/plain", properties::AbstractDict)
    if !isempty(properties)
        for (key, value) in properties
            key == "name" && continue # shown in header
            print(io, "    ", key, " = ")
            if value isa AbstractCIMReference
                show(IOContext(io, :compact => true), mime, value)
            elseif value isa Vector{CIMRef}
                print(io, "[")
                for (i, ref) in enumerate(value)
                    i > 1 && print(io, ", ")
                    show(IOContext(io, :compact => true), mime, ref)
                end
                print(io, "]")
            else
                printstyled(io, value, color=:light_black)
            end
            println(io)
        end
    end
end

# Show methods for CIM types
function Base.show(io::IO, obj::CIMObject)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), obj)
end

function Base.show(io::IO, mime::MIME"text/plain", obj::CIMObject)
    compact = get(io, :compact, false)

    if compact
        # Compact mode: CIMObject:ClassName
        print(io, obj.profile, ":")
        printstyled(io, obj.class_name, color=:blue)
        if hasname(obj)
            print(io, " (", getname(obj), ")")
        end
    else
        # Non-compact mode: Multi-line display
        print(io, obj.profile, ":")
        printstyled(io, obj.class_name, color=:blue)
        println(io)
        hasname(obj) && println(io, "  Name: ", getname(obj))
        println(io, "  ID: ", obj.id)
        println(io, "  Profile: ", obj.profile)

        # Show base properties
        if !isempty(obj.properties)
            printstyled(io, "\n  Properties:\n",bold=true)
            show_properties(io, mime, obj.properties)
        end

        # Show extensions first (they provide additional arguments)
        if !isempty(obj.extension)
            for extref in obj.extension
                ext = extref.source
                printstyled(io, "  Extended by ", bold=true)
                show(IOContext(io, :compact => true), mime, ext)
                println(io)
                if !isempty(ext.properties)
                    show_properties(io, mime, ext.properties)
                end
            end
        end

        # Show references if any
        if !isempty(obj.references)
            printstyled(io, "\n  Referenced by:", bold=true)
            for ref in obj.references
                print(io, "\n    ")
                show(IOContext(io, :compact => true), mime, ref.source)
            end
        end
    end
end

function Base.show(io::IO, mime::MIME"text/plain", ref::CIMRef)
    if ref.resolved && ref.target !== nothing
        print(io, "@ref ")
        show(IOContext(io, :compact => true), mime, ref.target)
    else
        printstyled(io, "@ref ", ref.id, color=:light_black)
    end
end

function Base.show(io::IO, mime::MIME"text/plain", backref::CIMBackref)
    print(io, "@backref ")
    show(io, mime, backref.source)
end

function Base.show(io::IO, cim_file::CIMFile)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), cim_file)
end

# Show methods for CIMExtension
function Base.show(io::IO, ext::CIMExtension)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), ext)
end

function Base.show(io::IO, mime::MIME"text/plain", ext::CIMExtension)
    compact = get(io, :compact, false)

    if compact
        print(io, ext.profile, ":")
        printstyled(io, ext.class_name, color=:blue)
        print(io, "->Extension")
        if haskey(ext.properties, "name")
            print(io, " (", ext.properties["name"], ")")
        end
    else
        print(io, ext.profile, ":")
        printstyled(io, ext.class_name, color=:blue)
        print(io, "->Extension")
        println(io)
        if haskey(ext.properties, "name")
            println(io, "  Name: ", ext.properties["name"])
        end
        print(io, "  Base: ")
        show(IOContext(io, :compact => true), mime, ext.base)
        println(io)
        println(io, "  Profile: ", ext.profile)

        if !isempty(ext.properties)
            printstyled(io, "\n  Properties:\n", bold=true)
            show_properties(io, mime, ext.properties)
        end
    end
end

function Base.show(io::IO, mime::MIME"text/plain", collection::CIMCollection)
    compact = get(io, :compact, false)

    if compact
        print(io, "CIMCollection: ")
        printstyled(io, "$(length(collection.objects)) objects, $(length(collection.extensions)) extensions", color=:blue)
    else
        print(io, "CIMCollection: ")
        printstyled(io, "$(length(collection.objects)) objects, $(length(collection.extensions)) extensions", color=:blue)
        println(io)

        _print_content_breakdown(io, collection)
    end
end

function Base.show(io::IO, mime::MIME"text/plain", cim_file::CIMFile)
    compact = get(io, :compact, false)

    if compact
        print(io, "CIMFile:")
        printstyled(io, cim_file.profile, color=:blue)
    else
        print(io, "CIMFile:")
        printstyled(io, cim_file.profile, color=:blue)
        println(io)
        println(io, "  UUID: ", cim_file.uuid)
        println(io, "  File: ", cim_file.filename)
        println(io, "  Created: ", cim_file.created)
        println(io, "  Scenario Time: ", cim_file.scenario_time)
        println(io, "  Modeling Authority: ", cim_file.modeling_authority)

        if !isempty(cim_file.dependencies)
            print(io, "  Dependencies: ")
            for (i, dep) in enumerate(cim_file.dependencies)
                if i > 1
                    print(io, ", ")
                end
                show(IOContext(io, :compact => true), mime, dep)
            end
            println(io)
        end

        _print_content_breakdown(io, cim_file.collection)
    end
end

function Base.show(io::IO, dataset::CIMDataset)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), dataset)
end

function Base.show(io::IO, mime::MIME"text/plain", dataset::CIMDataset)
    compact = get(io, :compact, false)

    if compact
        print(io, "CIMDataset: ")
        printstyled(io, "$(length(dataset.files)) profiles", color=:blue)
    else
        print(io, "CIMDataset: ")
        printstyled(io, "$(length(dataset.files)) profiles", color=:blue)
        println(io)
        println(io, "  Directory: ", dataset.directory)

        if !isempty(dataset.files)
            println(io, "  Profiles:")
            for (profile, cim_file) in dataset.files
                print(io, "    ", profile, ": ")
                print(io, cim_file.filename, " (")
                print(io, "$(length(cim_file.collection.objects)) objects, ")
                print(io, "$(length(cim_file.collection.extensions)) extensions)")
                println(io)
            end
        end
    end
end

function dump_properties(collection::AbstractCIMCollection)
    io = stdout

    # Group objects by class name
    class_objects = Dict{String, Vector{CIMObject}}()
    for obj in values(objects(collection))
        if !haskey(class_objects, obj.class_name)
            class_objects[obj.class_name] = CIMObject[]
        end
        push!(class_objects[obj.class_name], obj)
    end

    # Calculate importance for each class (count of non-reference, non-name properties)
    class_importance = Dict{String, Int}()
    for (class_name, objects_of_class) in class_objects
        # Count unique non-reference, non-name properties across all objects of this class
        important_properties = Set{String}()
        for obj in objects_of_class
            obj_props = properties(obj)
            for (prop_name, prop_value) in obj_props
                if prop_name != "name" && !(prop_value isa Union{AbstractCIMReference,Vector{CIMRef}})
                    push!(important_properties, prop_name)
                end
            end
        end
        class_importance[class_name] = length(important_properties)
    end

    # Sort classes by importance (descending), then alphabetically as tiebreaker
    sorted_classes = sort(collect(keys(class_objects)), by = class_name -> (-class_importance[class_name], class_name))

    printstyled(io, "Property Analysis for Collection:\n", bold=true, color=:blue)
    println(io, "=" ^ 50)

    for class_name in sorted_classes
        objects_of_class = class_objects[class_name]
        count = length(objects_of_class)

        printstyled(io, "\n", class_name, " (", count, " objects):\n", bold=true, color=:green)

        # Collect all unique property names for this class
        all_property_names = Set{String}()
        for obj in objects_of_class
            union!(all_property_names, keys(properties(obj)))
        end

        # Sort property names for consistent output
        sorted_properties = sort(collect(all_property_names))

        if isempty(sorted_properties)
            println(io, "  (no properties)")
            continue
        end

        for prop_name in sorted_properties
            # Collect all values for this property across objects of this class
            values_found = Any[]
            missing_count = 0

            for obj in objects_of_class
                obj_props = properties(obj)
                if haskey(obj_props, prop_name)
                    push!(values_found, obj_props[prop_name])
                else
                    missing_count += 1
                end
            end

            # Analyze the values
            unique_values = unique(values_found)
            has_missing = missing_count > 0

            print(io, "  ", prop_name, " = ")

            # Helper function to format a value using compact display
            format_value = function(val)
                val_io = IOBuffer()
                show(IOContext(val_io, :compact => true), MIME"text/plain"(), val)
                String(take!(val_io))
            end

            if has_missing && length(unique_values) == 0
                # All objects are missing this property
                printstyled(io, "[nothing]", color=:light_black)
            elseif has_missing && length(unique_values) == 1
                # Some missing, some have same value
                formatted_val = format_value(unique_values[1])
                printstyled(io, "[nothing, ", formatted_val, "]", color=:light_black)
            elseif has_missing && length(unique_values) > 1
                # Some missing, some have different values
                formatted_values = [format_value(val) for val in unique_values]
                value_str = join(formatted_values, ", ")
                printstyled(io, "[nothing, ", value_str, "]", color=:light_black)
            elseif !has_missing && length(unique_values) == 1
                # All have same value
                formatted_val = format_value(unique_values[1])
                printstyled(io, formatted_val, color=:light_black)
            else
                # All have values, but different ones
                formatted_values = [format_value(val) for val in unique_values]
                value_str = join(formatted_values, ", ")
                printstyled(io, "[", value_str, "]", color=:light_black)
            end

            println(io)
        end
    end

    println(io, "\n", "=" ^ 50)
end
