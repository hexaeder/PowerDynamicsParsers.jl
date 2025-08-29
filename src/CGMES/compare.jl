struct CIMCollectionComparison
    A::CIMCollection
    B::CIMCollection
    matches_a_to_b::Dict{String, String}  # ID in A -> ID in B
    matches_b_to_a::Dict{String, String}  # ID in B -> ID in A
end

function CIMCollectionComparison(A::CIMCollection, B::CIMCollection)
    matches_a_to_b = matched_ids(A, B)
    matches_b_to_a = Dict(v => k for (k, v) in matches_a_to_b)
    return CIMCollectionComparison(A, B, matches_a_to_b, matches_b_to_a)
end

function equalobjects(a::CIMObject, b::CIMObject)
    a.profile == b.profile &&
    a.class_name == b.class_name &&
    equalproperties(a, b)
end

function equalproperties(a::CIMObject, b::CIMObject)
    pa = properties(a)
    pb = properties(b)
    for (k, v) in pa
        haskey(pb, k) || return false
        equal_property(v, pb[k]) || return false
    end
    for (k, v) in pb
        haskey(pb, k) || return false
        equal_property(v, pb[k]) || return false
    end
    return true
end

equal_property(a, b) = a == b
equal_property(a::Vector, b::Vector) = length(a) == length(b) && all(equal_property.(a, b))
function equal_property(a::CIMRef, b::CIMRef)
    !a.resolved && !b.resolved && return true # ingore unresolved references
    # true if point to same name
    a.resolved && b.resolved && getname(follow_ref(a)) == getname(follow_ref(b)) && return true
    return false
end

function matched_backrefs(a::CIMObject, b::CIMObject)
    namesA = Set(getname(r.source) for r in a.references if hasname(r.source))
    namesB = Set(getname(r.source) for r in b.references if hasname(r.source))
    length(namesA ∩ namesB)
end

function matched_ids(A::CIMCollection, B::CIMCollection)
    objA = collect(values(objects(A)))
    objB = collect(values(objects(B)))

    matches = Dict{String, String}()  # idA => idB

    for a in objA
        _matches = CIMObject[]
        for b in objB
            equalobjects(a, b) && push!(_matches, b)
        end
        if length(_matches) == 1
            matches[a.id] = only(_matches).id
        elseif length(_matches) > 1
            nr_matched_backrefs = matched_backrefs.(Ref(a), _matches)
            i = argmax(nr_matched_backrefs)
            matches[a.id] = _matches[i].id
            if length(findall(isequal(nr_matched_backrefs[i]), nr_matched_backrefs)) > 1
                @warn "Multiple matches for object $(a.id) in collection A: $_matches"
            end
        end
    end

    return matches
end

function compare_objects(obj1::CIMObject, obj2::CIMObject; io::IO=stdout)
    printstyled(io, "Object Comparison\n", bold=true, color=:blue)
    println(io, "=" ^ 50)

    # Header information
    print(io, "Object 1: ")
    printstyled(io, obj1.profile, ":", obj1.class_name, color=:blue)
    if hasname(obj1)
        print(io, " (", getname(obj1), ")")
    end
    println(io, " [ID: ", obj1.id, "]")

    print(io, "Object 2: ")
    printstyled(io, obj2.profile, ":", obj2.class_name, color=:blue)
    if hasname(obj2)
        print(io, " (", getname(obj2), ")")
    end
    println(io, " [ID: ", obj2.id, "]")
    println(io)

    # Get merged properties for both objects
    props1 = properties(obj1)
    props2 = properties(obj2)

    # Categorize properties
    all_keys = union(keys(props1), keys(props2))
    equal_props = String[]
    different_props = String[]
    only_in_obj1 = String[]
    only_in_obj2 = String[]

    for key in all_keys
        has1 = haskey(props1, key)
        has2 = haskey(props2, key)

        if has1 && has2
            if equal_property(props1[key], props2[key])
                push!(equal_props, key)
            else
                push!(different_props, key)
            end
        elseif has1 && !has2
            push!(only_in_obj1, key)
        else  # !has1 && has2
            push!(only_in_obj2, key)
        end
    end

    # Helper function to format property values compactly
    format_value = function(val)
        val_io = IOBuffer()
        if val isa AbstractCIMReference
            show(IOContext(val_io, :compact => true), MIME"text/plain"(), val)
        else
            print(val_io, val)
        end
        String(take!(val_io))
    end

    # Display summary statistics
    printstyled(io, "Summary:\n", bold=true)
    println(io, "  Total properties: ", length(all_keys))
    println(io, "  Equal: ", length(equal_props))
    println(io, "  Different: ", length(different_props))
    println(io, "  Only in Object 1: ", length(only_in_obj1))
    println(io, "  Only in Object 2: ", length(only_in_obj2))
    println(io)

    # Show equal properties as a summary line
    if !isempty(equal_props)
        print(io, "Equal: ")
        printstyled(io, join(sort(equal_props), ", "), color=:green)
        println(io)
        println(io)
    end

    # Show different properties in detail
    if !isempty(different_props)
        printstyled(io, "Different Properties:\n", bold=true, color=:yellow)
        for prop in sort(different_props)
            val1 = format_value(props1[prop])
            val2 = format_value(props2[prop])

            printstyled(io, "  ", prop, ":\n", color=:blue)
            print(io, "    Object 1: ")
            printstyled(io, val1, color=:light_black)
            println(io)
            print(io, "    Object 2: ")
            printstyled(io, val2, color=:light_black)
            println(io)
        end
        println(io)
    end

    # Show properties only in object 1
    if !isempty(only_in_obj1)
        printstyled(io, "Only in Object 1:\n", bold=true, color=:red)
        for prop in sort(only_in_obj1)
            val1 = format_value(props1[prop])
            printstyled(io, "  ", prop, color=:blue)
            print(io, " = ")
            printstyled(io, val1, color=:light_black)
            println(io)
        end
        println(io)
    end

    # Show properties only in object 2
    if !isempty(only_in_obj2)
        printstyled(io, "Only in Object 2:\n", bold=true, color=:red)
        for prop in sort(only_in_obj2)
            val2 = format_value(props2[prop])
            printstyled(io, "  ", prop, color=:blue)
            print(io, " = ")
            printstyled(io, val2, color=:light_black)
            println(io)
        end
    end

    println(io, "=" ^ 50)
end
