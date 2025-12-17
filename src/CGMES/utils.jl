export filter_loopback_breakers
function filter_loopback_breakers(_data::CIMCollection)
    data = copy(_data)

    unretained_brs = CIMObject[]
    retained_brs = CIMObject[]
    for br in data(["Switch", "Breaker"])
        terms = ascendants(br, byclass("Terminal", via="ConductingEquipment"))
        tns = [t["TopologicalNode"] for t in terms]
        if tns[1].id == tns[2].id
            S1 = get_injected_power_pu(terms[1])
            S2 = get_injected_power_pu(terms[2])
            if !isapprox(S1, -S2)
                @warn "Found loopback breaker/switch $(getname(br)) with different power injections on its terminals: $(S1) vs $(S2)! This may invalidate the power flow state stored in the cgmes data."
            end
            if is_class(br, "Breaker") && br["Switch.retained"] || is_class(br, "Switch") && br["retained"]
                push!(retained_brs, br)
            else
                push!(unretained_brs, br)
            end

            delete_object!(data, br)
            delete_object!(data, terms[1])
            delete_object!(data, terms[2])
        end
    end
    if !isempty(unretained_brs)
        printstyled("- INFO: Removed $(length(unretained_brs)) loopback Breakers/Switches, which had property retain=false anyway.\n", color=:green)
    end
    if !isempty(retained_brs)
        printstyled("- WARN: Removed $(length(retained_brs)) loopback Breakers/Switches, which had property retain=true. Please check if this is intended!\n", color=:yellow)
    end
    resolve_references!(data; warn=false)
    data
end

export reattach_regulating_control
function reattach_regulating_control(_data::CIMCollection)
    data = copy(_data)
    controls = data("RegulatingControl")
    c = controls[1]
    reattached = 0
    for c in controls
        injector = ascend(c, byprop("RegulatingCondEq.RegulatingControl"))
        injterm = CGMES.get_connecting_terminal(injector)
        cterm = c["Terminal"]
        cterm.id == injterm.id && continue
        @assert cterm["TopologicalNode"].id == injterm["TopologicalNode"].id
        c.properties["Terminal"] = CIMRef(injterm.id)
        reattached += 1
    end
    if reattached > 0
        printstyled("- Reattached $(reattached) RegulatingControls to the correct Terminal.\n")
    else
        printstyled("- All RegulatingControls are already attached to the correct Terminal.\n", color=:green)
    end
    resolve_references!(data; warn=false)
    data
end

export rename_dangling_tpn
function rename_dangling_tpn(_data::CIMCollection)
    data = copy(_data)
    resolve_references!(data; warn=false)

    topnodes = data("TopologicalNode")
    names = [getname(t) for t in topnodes]
    unique_names = unique(names)
    duplicated_idxs = Int[]
    for name in unique_names
        appearances = findall(n -> n == name, names)
        if !isnothing(appearances) && length(appearances) > 1
            append!(duplicated_idxs, appearances)
        end
    end
    problematic_names = unique(names[duplicated_idxs])
    problematic_topnodes = topnodes[duplicated_idxs]

    if isempty(problematic_names)
        printstyled("- No problematic TopologicalNodes with duplicated names found.\n", color=:green)
        return data
    end

    if !isempty(problematic_topnodes)
        println("- Found $(length(problematic_topnodes)) problematic TopologicalNodes with duplicated names.")
    end
    renamed = 0
    for tpn in topnodes
        neighbors = topological_neighbors(tpn)
        if length(neighbors) == 1
            parent = only(neighbors)
            old_name = getname(tpn)
            if old_name in problematic_names
                new_name = "$(getname(parent))_$(old_name)"
                tpn.properties["name"] = new_name
                renamed += 1
            end
        end
    end
    if renamed > 0
        printstyled("- Renamed $(renamed) dangling TopologicalNodes to unique names.\n")
    end
    if renamed == length(problematic_topnodes)
        printstyled("  All problematic TopologicalNodes with duplicated names have been renamed.\n", color=:green)
    else
        printstyled("  Some problematic TopologicalNodes with duplicated names remain. Please check manually!\n", color=:yellow)
    end
    data
end


export merge_tpn_on_breakers
function merge_tpn_on_breakers(_data::CIMCollection)
    data = copy(_data)
    resolve_references!(data; warn=false)
    # find topological nodes with duplicated names
    topnodes = data("TopologicalNode")
    names = [getname(t) for t in topnodes]
    unique_names = unique(names)
    duplicated_idxs = Int[]
    for name in unique_names
        appearances = findall(n -> n == name, names)
        if !isnothing(appearances) && length(appearances) > 1
            append!(duplicated_idxs, appearances)
        end
    end
    problematic_topnodes = topnodes[duplicated_idxs]
    if !isempty(problematic_topnodes)
        println("- Found multiple problematic TopologicalNodes with duplicated names.")
    end

    open_and_different = CIMObject[]
    closed_but_different = CIMObject[]
    for br in data(["Switch", "Breaker"])
        terms = ascendants(br, byclass("Terminal", via="ConductingEquipment"))
        @assert length(terms) == 2

        tns = [t["TopologicalNode"] for t in terms]
        if tns[1].id == tns[2].id
            error("Found breaker/switch $(getname(br)) connecting the same TopologicalNode on both terminals. This should have been removed already. (see filter_loopback_breakers)")
        end

        if isopen(br)
            push!(open_and_different, br)
        else
            push!(closed_but_different, br)
            if tns[1] ∈ problematic_topnodes
                remove = tns[1]
                keep = tns[2]
            elseif tns[2] ∈ problematic_topnodes
                remove = tns[2]
                keep = tns[1]
            else
                error("Cannot decide which TopologicalNode to remove for Breaker $(getname(br)). Both TopologicalNodes are not in the list of problematic TopologicalNodes with duplicated names.")
            end

            if !(get_voltage_pu(remove) ≈ get_voltage_pu(keep))
                @warn "Merging TopologicalNodes $(getname(remove)) and $(getname(keep)) with different voltages: $(get_voltage_pu(remove)) vs $(get_voltage_pu(keep))."
            end

            # reassign all terminals connected to 'remove' to 'keep'
            reassign_backrefs!(remove, keep)
            reassign_extensions!(remove, keep)
            delete_object!(data, remove)
            # delete SvVoltage for removed
            svs_remove = ascend(remove, byclass("SvVoltage"))
            delete_object!(data, svs_remove)
        end
        # delete breaker
        delete_object!(data, br)
        delete_object!(data, terms[1])
        delete_object!(data, terms[2])
    end
    if !isempty(open_and_different)
        printstyled("- INFO: Removed $(length(open_and_different)) open Breakers/Switches connecting different TopologicalNodes.\n", color=:green)
    end
    if !isempty(closed_but_different)
        printstyled("- INFO: Removed $(length(closed_but_different)) closed Breakers/Switches connecting different TopologicalNodes with duplicated names.\n", color=:yellow)
    end

    # reresolve all references
    resolve_references!(data; warn=false)
    data
end

function isopen(br)
    if is_class(br, "Breaker")
        return br["Switch.open"]
    elseif is_class(br, "Switch")
        return br["open"]
    else
        error("Object $(getname(br)) is neither Breaker nor Switch.")
    end
end

function reassign_backrefs!(remove, keep)
    for backref in remove.backrefs
        # follow_ref not base_object to stop at extension
        source = CGMES.follow_ref(backref)

        prop = source.properties[backref.prop]
        if prop isa AbstractVector
            subidx = only(findall(x -> x.id == remove.id, prop))
            fwref = prop[subidx]
        elseif prop isa CIMRef
            fwref = prop
        else
            error()
        end
        #modify fwref to point to keep
        fwref.id = keep.id
        fwref.target = keep
    end
end
function reassign_extensions!(remove, keep)
    if !isempty(remove.extension)
        error("Reassigning of extensions from $remove to $keep not implemented yet.")
    end
end

function delete_object!(data::CIMCollection, obj::CIMObject)
    # delete references to this object
    for backref in obj.backrefs
        # use follow_ref to get ext/obj with reference
        source = CGMES.follow_ref(backref)
        val = source.properties[backref.prop]
        if val isa CIMRef
            # on topo node merge
            # the ref might have been updated to point to something else
            if val.id == obj.id
                source.properties[backref.prop] = "deleted from graph"
            end
        elseif val isa AbstractVector
            filter!(x -> !(x isa CIMRef) || x.id != obj.id, val)
        else
            error("Unexpected property type $(typeof(val)) for backreference deletion.")
        end
    end

    # delete object
    delete!(objects(data), obj.id)
    # delete extensions for this object
    ext = follow_ref.(obj.extension)
    todel = Int[]
    for ex in ext
        i = findfirst(x -> x === ex, data.extensions)
        push!(todel, i)
    end
    deleteat!(data.extensions, todel)
    nothing
end
