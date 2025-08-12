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

# Helper function to show properties
function show_properties(io::IO, mime::MIME"text/plain", properties::AbstractDict)
    if !isempty(properties)
        for (key, value) in properties
            key == "name" && continue # shown in header
            print(io, "    ", key, " = ")
            if value isa AbstractCIMReference
                show(IOContext(io, :compact => true), mime, value)
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

        # Count and format class breakdowns
        object_counts = _class_count(values(cim_file.objects))
        extension_counts = _class_count(cim_file.extensions)

        # Display objects with breakdown
        println(io, "  Objects: ", length(cim_file.objects))
        _format_class_breakdown(io, object_counts)

        # Display extensions with breakdown
        println(io, "  Extensions: ", length(cim_file.extensions))
        _format_class_breakdown(io, extension_counts)
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
                print(io, "$(length(cim_file.objects)) objects, ")
                print(io, "$(length(cim_file.extensions)) extensions)")
                println(io)
            end
        end
    end
end
