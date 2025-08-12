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
        
        # Show backrefs count if any
        if !isempty(obj.backrefs)
            println(io, "  backrefs: $(length(obj.backrefs))")
        end
    end
end

function Base.show(io::IO, mime, ::MIME"text/plain", ref::CIMRef)
    if ref.resolved && ref.target !== nothing
        print(io, "@ref ")
        show(io, mime, ref.target)
    else
        printstyled(io, "@ref undefined", color=:light_black)
    end
end

function Base.show(io::IO, mime::MIME"text/plain", backref::CIMBackref)
    print(io, "@backref ")
    show(io, mime, backref.target)
end
