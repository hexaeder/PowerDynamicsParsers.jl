# Show methods for CIM types
function Base.show(io::IO, obj::CIMObject)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), obj)
end

function Base.show(io::IO, mime::MIME"text/plain", obj::CIMObject)
    compact = get(io, :compact, false)

    if compact
        # Compact mode: CIMObject:ClassName
        print(io, "CIMObject:")
        printstyled(io, obj.class_name, color=:blue)
    else
        # Non-compact mode: Multi-line display
        print(io, "CIMObject:")
        printstyled(io, obj.class_name, color=:blue)

        # Show properties
        if !isempty(obj.properties)
            println(io)
            for (key, value) in obj.properties
                print(io, "  ", key, ": ")
                if value isa AbstractCIMReference
                    show(IOContext(io, :compact => true), mime, value)
                else
                    printstyled(io, value, color=:light_black)
                end
                println(io)
            end
        end

        # Show references count if any
        if !isempty(obj.references)
            println(io, "  referenced by: $(length(obj.references))")
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
    show(io, mime, backref.target)
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
        print(io, "CIMExtension:")
        printstyled(io, ext.class_name, color=:blue)
    else
        print(io, "CIMExtension:")
        printstyled(io, ext.class_name, color=:blue)
        println(io)
        print(io, "  Base: ")
        show(IOContext(io, :compact => true), mime, ext.base)
        println(io)
        println(io, "  Profile: ", ext.profile)

        if !isempty(ext.properties)
            for (key, value) in ext.properties
                print(io, "  ", key, ": ")
                if value isa AbstractCIMReference
                    show(IOContext(io, :compact => true), mime, value)
                else
                    printstyled(io, value, color=:light_black)
                end
                println(io)
            end
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

        println(io, "  Objects: ", length(cim_file.objects))
    end
end
