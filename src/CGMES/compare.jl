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
