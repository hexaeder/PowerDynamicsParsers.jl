using PowerDynamics
using PowerDynamics.NetworkDynamics: str_significant
using PowerDynamics: DataFrame

const STATIC_EDGEMODEL_CACHE = Dict{Any, NetworkDynamics.EdgeModel}()
function wipe_model_caches!()
    empty!(STATIC_EDGEMODEL_CACHE)
end

abstract type AbstractEdgeSubgraph end
abstract type SingleBranchSubgraph <: AbstractEdgeSubgraph end
struct ACLineSegment <: SingleBranchSubgraph end
struct PowerTransformer <: SingleBranchSubgraph end
struct Breaker <: SingleBranchSubgraph end
struct MultiBranchSubgraph <: AbstractEdgeSubgraph end

function is_abstract_edge_subgraph(c::CIMCollection)
    length(c("TopologicalNode")) == 2
end

function is_single_branch_subgraph(c::AbstractCIMCollection)
    length(c(BRANCH_CLASSES)) == 1 && length(c("Terminal")) == 2
end

function is_multi_branch_subgraph(c::AbstractCIMCollection)
    haskey(c.metadata, :branches) || return false
    branches = c.metadata[:branches]
    all(is_single_branch_subgraph, branches) || return false
end

function get_tpn_nodes(c::AbstractCIMCollection)
    endnodes = c("TopologicalNode")
    @assert length(endnodes)==2 "Expected a edge subgraph (two Topolocial nodes)!"
    src_node = endnodes[findfirst(n -> getname(n) == c.metadata[:src_name], endnodes)]
    dst_node = endnodes[findfirst(n -> getname(n) == c.metadata[:dst_name], endnodes)]
    (; src_node, dst_node)
end

function get_branch_name(c)
    el = only(c(BRANCH_CLASSES))
    getname(el)
end

function get_edge_model(c)
    class = classify_branch_subgraph(c)
    isnothing(class) && throw(ArgumentError("Cannot parse this edge model of class $(only(c(BRANCH_CLASSES)).class_name)!"))

    model = get_edge_model(class, c)

    model.metadata[:cgmes_subgraph] = c
    model.metadata[:cgmes_class] = class

    set_graphelement!(model, symbolify(c.metadata[:src_name]) => symbolify(c.metadata[:dst_name]))

    return model
end

# Table 191 - Attributes of Wires::ACLineSegment

""""
| Attribute name                            | Attribute type | Description                                                                                                                                                                  |
|-------------------------------------------|----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| b0ch (ShortCircuit)                       | Susceptance    | Zero sequence shunt (charging) susceptance, uniformly distributed, of the entire line section.                                                                               |
| bch                                       | Susceptance    | Positive sequence shunt (charging) susceptance, uniformly distributed, of the entire line section. This value represents the full charging over the full length of the line. |
| g0ch (ShortCircuit)                       | Conductance    | Zero sequence shunt (charging) conductance, uniformly distributed, of the entire line section.                                                                               |
| gch                                       | Conductance    | Positive sequence shunt (charging) conductance, uniformly distributed, of the entire line section.                                                                           |
| r                                         | Resistance     | Positive sequence series resistance of the entire line section.                                                                                                              |
| r0 (ShortCircuit)                         | Resistance     | Zero sequence series resistance of the entire line section.                                                                                                                  |
| shortCircuitEndTemperature (ShortCircuit) | Temperature    | Maximum permitted temperature at the end of SC for the calculation of minimum short-circuit currents. Used for short circuit data exchange according to IEC 60909            |
| x                                         | Reactance      | Positive sequence series reactance of the entire line section.                                                                                                               |
| x0 (ShortCircuit)                         | Reactance      | Zero sequence series reactance of the entire line section.                                                                                                                   |
| length                                    | Length         | see Conductor                                                                                                                                                                |
| aggregate                                 | Boolean        | see Equipment                                                                                                                                                                |
| description                               | String         | see IdentifiedObject                                                                                                                                                         |
| energyIdentCodeEic (Entsoe)               | String         | see IdentifiedObject                                                                                                                                                         |
| mRID                                      | String         | see IdentifiedObject                                                                                                                                                         |
| name                                      | String         | see IdentifiedObject                                                                                                                                                         |
| shortName (Entsoe)                        | String         | see IdentifiedObject                                                                                                                                                         |
"""
function get_branch_model(class::ACLineSegment, c::AbstractCIMCollection; i=nothing)
    segment = only(c("ACLineSegment"))

    # Sbase is just 100 because Vbase is in kv!
    Vbase = CGMES.get_base_voltage(segment) # kV
    Zbase = Vbase^2 / SBASE
    Ybase = 1 / Zbase

    props = properties(segment)
    G_src = props["gch"] / 2 / Ybase
    G_dst = G_src
    B_src = props["bch"] / 2 / Ybase
    B_dst = B_src
    R = props["r"] / Zbase
    X = props["x"] / Zbase

    src_node, dst_node = get_tpn_nodes(c)
    r_src = CGMES.get_base_voltage(src_node) / Vbase
    r_dst = CGMES.get_base_voltage(dst_node) / Vbase

    name = isnothing(i) ? :ACLineSegment : Symbol("ACLineSegment_Branch$i")
    blueprint = (Library.PiLine, name)
    params = namespaced_params(name; G_src, G_dst, B_src, B_dst, R, X, r_src, r_dst)
    (; blueprint, params)
end

function get_branch_model(class::PowerTransformer, c::AbstractCIMCollection; i=nothing)
    tends = c("PowerTransformerEnd")
    @assert length(tends) == 2 "Expected exactly two PowerTransformerEnd, got $(length(tends))!"

    tend_topo_names  = map(tends) do tend
        getname(tend["TransformerEnd.Terminal"]["TopologicalNode"])
    end
    src_end = tends[only(findall(x -> x == c.metadata[:src_name], tend_topo_names))]
    dst_end = tends[only(findall(x -> x == c.metadata[:dst_name], tend_topo_names))]

    Vbase_src = CGMES.get_base_voltage(src_end) # kV
    Zbase_src = Vbase_src^2 / SBASE
    Ybase_src = 1 / Zbase_src

    Vbase_dst = CGMES.get_base_voltage(dst_end) # kV
    Zbase_dst = Vbase_dst^2 / SBASE
    Ybase_dst = 1 / Zbase_dst

    G_src = src_end["g"] / Ybase_src
    B_src = src_end["b"] / Ybase_src
    R = src_end["r"] / Zbase_src + dst_end["r"] / Zbase_dst
    X = src_end["x"] / Zbase_src + dst_end["x"] / Zbase_dst
    G_dst = dst_end["g"] / Ybase_dst
    B_dst = dst_end["b"] / Ybase_dst

    # specific naming leads to non-egal models (generated function contains name)
    name = isnothing(i) ? :PowerTransformer : Symbol("PowerTransformer_Branch$i")
    blueprint = (Library.PiLine, name)
    params = namespaced_params(name; G_src, G_dst, B_src, B_dst, R, X)
    (; blueprint, params)
end

function get_branch_model(class::Breaker, c::AbstractCIMCollection; i=nothing)
    is_open = isopen(only(c("Breaker")))
    name = isnothing(i) ? :Breaker : Symbol("Breaker$i")
    # breaker = Library.Breaker(; closed = is_open ? 0 : 1, name)
    blueprint = (Library.Breaker, name)
    closed = is_open ? 0 : 1
    params = namespaced_params(name; closed)
    (; blueprint, params)
end

function get_edge_model(class::SingleBranchSubgraph, c::AbstractCIMCollection)
    blueprint, params = get_branch_model(class, c)
    em = get_cached_edge_model(blueprint)
    name = symbolify(get_branch_name(c))
    em = EdgeModel(em; name)
    for (k, v) in params
        set_default!(em, k, v)
    end
    em
end

function get_edge_model(class::MultiBranchSubgraph, c::AbstractCIMCollection)
    branches = c.metadata[:branches]
    branch_blueprints = Tuple[]
    branch_names = Symbol[]
    branch_params = Dict{Symbol, Float64}()
    for (i, bm) in enumerate(branches)
        bclass = CGMES.classify_branch_subgraph(bm)
        blueprint, params = get_branch_model(bclass, bm; i)
        push!(branch_blueprints, blueprint)
        bname = symbolify(get_branch_name(bm))
        push!(branch_names, bname)
        merge!(branch_params, params)
    end
    em = get_cached_edge_model(branch_blueprints)
    name = Symbol(join(branch_names, "__"))
    em = EdgeModel(em; name)
    for (k, v) in branch_params
        set_default!(em, k, v)
    end
    em
end

# single edge
function get_cached_edge_model(blueprint::Tuple{Any,Symbol})
    get!(STATIC_EDGEMODEL_CACHE, blueprint) do
        # @info "cache new model for" blueprint
        model, name = blueprint
        branch = model(; name)
        compile_line(MTKLine(branch))
    end
end
function get_cached_edge_model(blueprint::Vector{Tuple})
    get!(STATIC_EDGEMODEL_CACHE, blueprint) do
        # @info "cache new model for" blueprint
        branch_models = Any[]
        for bp in blueprint
            model, name = bp
            branch = model(; name)
            push!(branch_models, branch)
        end
        compile_line(MTKLine(branch_models...))
    end
end

function namespaced_params(ns; kwargs...)
    d = Dict{Symbol,Float64}()
    for (k, v) in pairs(kwargs)
        d[Symbol(ns, "₊", k)] = v
    end
    d
end

function classify_branch_subgraph(c::AbstractCIMCollection)
    @assert is_abstract_edge_subgraph(c) "Expected a edge subgraph (two Topolocial nodes)!"

    if is_single_branch_subgraph(c)
        segment = only(c(BRANCH_CLASSES))
        is_class(segment, "ACLineSegment") && return ACLineSegment()
        is_class(segment, "PowerTransformer") && return PowerTransformer()
        is_class(segment, "Breaker") && return Breaker()
    end
    if is_multi_branch_subgraph(c)
        return MultiBranchSubgraph()
    end

    return nothing
end

abstract type Injector end
struct SlackType <: Injector
    V::Float64
    objs::Vector{CIMObject}
end
struct PVType <: Injector
    P::Float64
    V::Float64
    objs::Vector{CIMObject}
end
struct PQYType <: Injector
    P::Float64
    Q::Float64
    G::Float64  # Shunt conductance in pu
    B::Float64  # Shunt susceptance in pu
    objs::Vector{CIMObject}
end
# Backward compatibility constructor
PQType(P, Q, objs) = PQYType(P, Q, 0.0, 0.0, objs)
# S + S
combine(sA::SlackType, sB::SlackType) = SlackType(compatible_voltage(sA, sB), vcat(sA.objs, sB.objs))
# S + PV
combine(s::SlackType, pv::PVType) = SlackType(compatible_voltage(s, pv), vcat(s.objs, pv.objs))
combine(pv::PVType, s::SlackType) = combine(s, pv)
# S + PQY (Y component absorbed by fixed voltage)
combine(s::SlackType, pqy::PQYType) = SlackType(s.V, vcat(s.objs, pqy.objs))
combine(pqy::PQYType, s::SlackType) = combine(s, pqy)

# PV + PV
combine(pvA::PVType, pvB::PVType) = PVType(pvA.P + pvB.P, compatible_voltage(pvA, pvB), vcat(pvA.objs, pvB.objs))
# PV + PQY (Y component absorbed by fixed voltage)
combine(pv::PVType, pqy::PQYType) = PVType(pqy.P + pv.P, pv.V, vcat(pqy.objs, pv.objs))
combine(pqy::PQYType, pv::PVType) = combine(pv, pqy)

compatible_voltage(v1::Injector, v2::Injector) = compatible_voltage(v1.V, v2.V)
function compatible_voltage(v1, v2)
    isnan(v1) && !isnan(v2) && return v2
    !isnan(v1) && isnan(v2) && return v1
    isapprox(v1, v2; rtol=1e-5, atol=1e-8) && return v1
    error("Incompatible voltage setpoints: $(str_significant(v1)) vs $(str_significant(v2))!")
end

# PQY + PQY
combine(pqA::PQYType, pqB::PQYType) = PQYType(pqA.P + pqB.P, pqA.Q + pqB.Q, pqA.G + pqB.G, pqA.B + pqB.B, vcat(pqA.objs, pqB.objs))

function get_static_vertex_model(c::CIMCollection)
    injectors = []
    tpn = only(c("TopologicalNode"))
    is_angle_ref(tpn) && push!(injectors, SlackType(NaN, [tpn]))

    for t in c("Terminal")
        inj = t["ConductingEquipment"]
        in_service(inj) || continue
        type = injector_type(inj)
        push!(injectors, type)
    end
    mod = reduce(combine, injectors, init=PQYType(0.0, 0.0, 0.0, 0.0, CIMObject[]))
    name = symbolify(getname(tpn))
    vm = powerdynamics_model(mod, name)
    set_graphelement!(vm, c.metadata[:busidx])
    vm.metadata[:cgmes_subgraph] = c
    vm
end
function powerdynamics_model(pqy::PQYType, name)
    # If no shunt admittance, use simple PQ model
    if iszero(pqy.G) && iszero(pqy.B)
        return pfPQ(; P=pqy.P, Q=pqy.Q, name)
    end

    if iszero(pqy.P) && iszero(pqy.Q)
        @named shunt = Library.ConstantYLoad()
        bus = compile_bus(MTKBus(shunt))
        set_default!(bus, :shunt₊G, pqy.G)
        set_default!(bus, :shunt₊B, pqy.B)
        return bus
    end

    @named shunt = Library.ConstantYLoad()
    @named pq = Library.PQConstraint()
    bus = compile_bus(MTKBus([pq, shunt]; name))
    set_default!(bus, :pq₊P, pqy.P)
    set_default!(bus, :pq₊Q, pqy.Q)
    set_default!(bus, :shunt₊G, pqy.G)
    set_default!(bus, :shunt₊B, pqy.B)
    return bus
end
powerdynamics_model(pv::PVType, name) = pfPV(; P=pv.P, V=pv.V, name)
powerdynamics_model(s::SlackType, name) = pfSlack(; V=s.V, name)

function in_service(inj)
    eqp_service = if haskey(inj, "Equipment.inService")
        inj["Equipment.inService"]
    else
        nothing
    end
    svcand = ascendants(inj, byclass("SvStatus", via="ConductingEquipment"))
    sv_service = if !isempty(svcand)
        svc = only(svcand)
        svc["inService"]
    else
        nothing
    end
    # error if both are defined and different
    if !isnothing(eqp_service) && !isnothing(sv_service)
        eqp_service == sv_service || error("Inconsistent inService status for $(getname(inj))!")
    end
    if isnothing(eqp_service) && isnothing(sv_service)
        return true
    elseif isnothing(eqp_service)
        return sv_service
    else
        return eqp_service
    end
end

function PowerDynamics.Network(ds::AbstractCIMCollection; verbose=true, kwargs...)
    println("Split Topology...")
    @time vertices, edges = split_topologically(ds; warn=false)
    Network(vertices, edges; verbose=verbose, kwargs...)
end
function PowerDynamics.Network(vertices::Vector{CIMCollection}, edges::Vector{CIMCollection}; verbose=true, kwargs...)
    wipe_model_caches!()
    println("Parse Edges...")
    ems = map(enumerate(edges)) do (i, e)
        verbose && println("Processing edge $i")
        get_edge_model(e)
    end
    vms = map(enumerate(vertices)) do (i, v)
        verbose && println("Processing vertex $i")
        get_static_vertex_model(v)
    end
    # ems = get_edge_model.(edges)
    # vms = get_static_vertex_model.(vertices)
    PowerDynamics.Network(vms, ems; warn_order=false, kwargs...)
end

injector_type(o::CIMObject) = injector_type(Val(Symbol(o.class_name)), o)
function injector_type(::Val{:SynchronousMachine}, o::CIMObject)
    props = properties(o)

    # get p and q from SSH
    P = -props["RotatingMachine.p"]/SBASE
    Q = -props["RotatingMachine.q"]/SBASE

    if haskey(props, "RegulatingCondEq.RegulatingControl")
        baseV = get_base_voltage(get_connecting_terminal(o))
        controller = follow_ref(props["RegulatingCondEq.RegulatingControl"])
        is_class(controller, "RegulatingControl") || error("Expected RegulatingControl, got $(controller.class_name)")
        V = controller["targetValue"]/baseV
        return PVType(P, V, [o])
    else
        return PQType(P, Q, [o])
    end
end
function injector_type(::Val{:ConformLoad}, o::CIMObject)
    props = properties(o)
    P = -props["EnergyConsumer.p"]/SBASE
    Q = -props["EnergyConsumer.q"]/SBASE
    return PQType(P, Q, [o])
end

function injector_type(::Val{:PowerElectronicsConnection}, o::CIMObject)
    props = properties(o)

    # Get p and q from SSH (similar to SynchronousMachine but different property names)
    P = -props["p"]/SBASE
    Q = -props["q"]/SBASE

    if haskey(props, "RegulatingCondEq.RegulatingControl")
        baseV = get_base_voltage(get_connecting_terminal(o))
        controller = follow_ref(props["RegulatingCondEq.RegulatingControl"])
        is_class(controller, "RegulatingControl") || error("Expected RegulatingControl, got $(controller.class_name)")
        V = controller["targetValue"]/baseV
        return PVType(P, V, [o])
    else
        return PQType(P, Q, [o])
    end
end

function injector_type(::Val{:LinearShuntCompensator}, o::CIMObject)
    props = properties(o)

    # Get susceptance and conductance per section
    bPerSection = props["bPerSection"]  # in Siemens
    gPerSection = props["gPerSection"]  # in Siemens

    # Get actual sections from StateVariables (SvShuntCompensatorSections)
    sv = ascend(o, byclass("SvShuntCompensatorSections", via="ShuntCompensator"))
    sections = properties(sv)["sections"]

    # Get base voltage to convert to pu
    baseV = get_base_voltage(get_connecting_terminal(o))  # kV
    Ybase = SBASE / (baseV^2)

    # Total admittance in pu
    G = (gPerSection * sections) / Ybase
    B = (bPerSection * sections) / Ybase

    # Shunt compensators inject no fixed P or Q (voltage-dependent)
    return PQYType(0.0, 0.0, G, B, [o])
end

function is_angle_ref(o::CIMObject)
    @assert is_class(o, "TopologicalNode") "Expected TopologicalNode, got $(o.class_name)"

    refs = ascendants(o, byprop("AngleRefTopologicalNode"))

    if length(refs) == 0
        return false
    elseif length(refs) == 1
        return true
    else
        error("Multiple AngleRefTopologicalNode references found for TopologicalNode $(getname(o))!")
    end
end

function get_base_voltage(ob::CIMObject)
    if is_class(ob, ["TopologicalNode", "PowerTransformerEnd", "ACLineSegment"])
        return follow_ref(ob[r"BaseVoltage$"])["nominalVoltage"]
    elseif is_class(ob, "Terminal")
        return get_base_voltage(ob["TopologicalNode"])
    end
    error("Don't know how to get base voltage for object of class $(ob.class_name)!")
end

function get_connecting_terminal(injector::CIMObject)
    ascend(injector, byclass("Terminal", via="ConductingEquipment"))
end

function get_voltage_pu(o::CIMObject)
    sv = ascend(o, byclass("SvVoltage"))
    θ = deg2rad(sv["angle"])
    V = sv["v"] / get_base_voltage(o)
    return V * exp(im * θ)
end
"""
ATTENTION: we go from load to injector convention
"""
function get_injected_power_pu(o::CIMObject)
    sv = ascend(o, byclass("SvPowerFlow"))
    P = sv["p"] / SBASE
    Q = sv["q"] / SBASE
    return -P - im * Q
end

function get_src_voltage_pu(c::CIMCollection)
    src_node, dst_node = get_tpn_nodes(c)
    get_voltage_pu(src_node)
end
function get_dst_voltage_pu(c::CIMCollection)
    src_node, dst_node = get_tpn_nodes(c)
    get_voltage_pu(dst_node)
end
function get_src_power_pu(c::CIMCollection)
    src_node, dst_node = get_tpn_nodes(c)
    terminals = ascendants(src_node, byclass("Terminal", via="TopologicalNode"))
    Sref = sum(CGMES.get_injected_power_pu.(terminals))
end
function get_dst_power_pu(c::CIMCollection)
    src_node, dst_node = get_tpn_nodes(c)
    terminals = ascendants(src_node, byclass("Terminal", via="TopologicalNode"))
    Sref = sum(CGMES.get_injected_power_pu.(terminals))
end


function test_powerflow(e::EdgeModel)
    subgraph = e.metadata[:cgmes_subgraph]
    if CGMES.classify_branch_subgraph(subgraph) isa Breaker
        return 0.0
    end

    src_uc = CGMES.get_src_voltage_pu(subgraph)
    dst_uc = CGMES.get_dst_voltage_pu(subgraph)

    default_overrides = Dict{Symbol, Any}(
        :src₊u_r => real(src_uc),
        :src₊u_i => imag(src_uc),
        :dst₊u_r => real(dst_uc),
        :dst₊u_i => imag(dst_uc),
    )
    guess_overrides = Dict{Symbol, Any}(
        :src₊i_r => 1.0,
        :src₊i_i => 0.0,
        :dst₊i_r => 1.0,
        :dst₊i_i => 0.0
    )
    state = initialize_component(e; default_overrides, guess_overrides, verbose=false)
    P, Q = get_initial_state(e, state, [:src₊P, :src₊Q])
    Sref = CGMES.get_src_power_pu(subgraph)
    Pref = real(Sref)
    Qref = imag(Sref)

    validate_power_component(P, Pref, "Active Power (P)")
    validate_power_component(Q, Qref, "Reactive Power (Q)")
    return max(abs(P - Pref), abs(Q - Qref))j
end

function validate_power_component(computed::Float64, reference::Float64, component_name::String)
    if iszero(reference)
        # Handle zero reference case
        error_abs = abs(computed)
        if error_abs ≤ 1e-6
            printstyled("✓ $component_name: computed=$(str_significant(computed; sigdigits=4)) matches zero reference (abs_error=$(str_significant(error_abs; sigdigits=3)))\n", color=:green)
        elseif error_abs ≤ 1e-4
            printstyled("✓ $component_name: computed=$(str_significant(computed; sigdigits=4)) vs reference=$(str_significant(reference; sigdigits=4)) (abs_error=$(str_significant(error_abs; sigdigits=3)))\n", color=:yellow)
        else
            printstyled("✗ $component_name: computed=$(str_significant(computed; sigdigits=4)) vs reference=$(str_significant(reference; sigdigits=4)) (abs_error=$(str_significant(error_abs; sigdigits=3)))\n", color=:red)
        end
    else
        # Calculate percentage error
        error_pct = abs((computed - reference) / reference) * 100

        if error_pct ≤ 0.01
            printstyled("✓ $component_name: computed=$(str_significant(computed; sigdigits=4)) matches reference=$(str_significant(reference; sigdigits=4)) (error=$(str_significant(error_pct; sigdigits=3))%)\n", color=:green)
        elseif error_pct ≤ 1.0
            printstyled("✓ $component_name: computed=$(str_significant(computed; sigdigits=4)) vs reference=$(str_significant(reference; sigdigits=4)) (error=$(str_significant(error_pct; sigdigits=3))%)\n", color=:yellow)
        else
            printstyled("✗ $component_name: computed=$(str_significant(computed; sigdigits=4)) vs reference=$(str_significant(reference; sigdigits=4)) (error=$(str_significant(error_pct; sigdigits=3))%)\n", color=:red)
        end
    end
end


using Markdown
using PowerDynamics
using PowerDynamics.ModelingToolkit
using PowerDynamics.ModelingToolkit: t_nounits as t, D_nounits as Dt
@mtkmodel PiLineFreeP begin
    @parameters begin
        R, [description="Resistance of branch in pu", guess=0]
        X, [description="Reactance of branch in pu", guess=0.1]
        G, [description="Conductance of src shunt", guess=0]
        B, [description="Susceptance of src shunt", guess=0]
        r_src=1, [description="src end transformation ratio"]
        r_dst=1, [description="dst end transformation ratio"]
        active=1, [description="Line active or at fault"]
    end
    @components begin
        src = Terminal()
        dst = Terminal()
    end
    begin
        Z = R + im*X
        Ysrc = G + im*B
        Ydst = G + im*B
        Vsrc = src.u_r + im*src.u_i
        Vdst = dst.u_r + im*dst.u_i
        V₁ = r_src * Vsrc
        V₂ = r_dst * Vdst
        i₁ = Ysrc * V₁
        i₂ = Ydst * V₂
        iₘ = 1/Z * (V₁ - V₂)
        isrc = (-iₘ - i₁)*r_src
        idst = ( iₘ - i₂)*r_dst
    end
    @equations begin
        src.i_r ~ active * simplify(real(isrc))
        src.i_i ~ active * simplify(imag(isrc))
        dst.i_r ~ active * simplify(real(idst))
        dst.i_i ~ active * simplify(imag(idst))
    end
end
function determine_branch_parameters(c)
    @assert CGMES.is_single_branch_subgraph(c) "Expected a single branch subgraph (one Topological node)!"
    comp = CGMES.get_components(CGMES.ACLineSegment(), c)

    src_uc = CGMES.get_voltage_pu(comp.src_node)
    dst_uc = CGMES.get_voltage_pu(comp.dst_node)
    src_S = CGMES.get_injected_power_pu(comp.src_terminal)
    dst_S = CGMES.get_injected_power_pu(comp.dst_terminal)
    src_ic = conj(src_S / src_uc)
    dst_ic = conj(dst_S / dst_uc)

    default_overrides = Dict{Symbol, Any}(
        :src₊u_r => real(src_uc),
        :src₊u_i => imag(src_uc),
        :dst₊u_r => real(dst_uc),
        :dst₊u_i => imag(dst_uc),
        :src₊i_r => real(src_ic),
        :src₊i_i => imag(src_ic),
        :dst₊i_r => real(dst_ic),
        :dst₊i_i => imag(dst_ic)
    )

    @named branch = PiLineFreeP()
    edgemodel = compile_line(MTKLine(branch))
    state = initialize_component(edgemodel; default_overrides, verbose=false)

    _R = state[:branch₊R]
    _G = state[:branch₊G]
    _B = state[:branch₊B]
    _X = state[:branch₊X]

    # compare to values from data
    Vbase = CGMES.get_base_voltage(comp.segment) # kV
    Zbase = Vbase^2 / SBASE
    Ybase = 1 / Zbase
    props = properties(comp.segment)
    G_src = props["gch"] / 2 / Ybase
    G_dst = G_src
    B_src = props["bch"] / 2 / Ybase
    B_dst = B_src
    R = props["r"] / Zbase
    X = props["x"] / Zbase

    out = md"""
    ## Branch Parameter Calculation from CGMES Data

    **Base Values:**
    - Vbase = $(Vbase) kV (from BaseVoltage.nominalVoltage)
    - Zbase = Vbase² / SBASE = $(Zbase) Ω
    - Ybase = 1 / Zbase = $(Ybase) S
    - SBASE = $(SBASE) MVA

    **CGMES Properties (ACLineSegment):**
    - r = $(props["r"]) Ω (positive sequence series resistance)
    - x = $(props["x"]) Ω (positive sequence series reactance)
    - gch = $(props["gch"]) S (positive sequence shunt charging conductance)
    - bch = $(props["bch"]) S (positive sequence shunt charging susceptance)

    **Parameter Conversion to Per-Unit:**

    |Parameter | CGMES Value | Calculation | Per-Unit Value | Calculated |
    |----------|-------------|-------------|----------------|------------|
    | R        | $(props["r"]) Ω | r / Zbase | $R  | $_R |
    | X        | $(props["x"]) Ω | x / Zbase | $X  | $_X |
    | G        | $(props["gch"]) S | gch / 2 / Ybase | $G_src  | $_G |
    | B        | $(props["bch"]) S | bch / 2 / Ybase | $B_src  | $_B |

    *Note: G and B are divided by 2 because they represent total shunt values split equally between source and destination ends.*
    """
    show(stdout, MIME"text/plain"(), out)
    nothing
end

function PowerDynamics.show_powerflow(ds::AbstractCIMCollection)
    vertices, edges = split_topologically(ds; warn=false)

    dict = OrderedDict()
    dict["N"] = Int[]
    dict["Bus Names"] = String[]
    dict["vm [pu]"] = Float64[]
    dict["varg [deg]"] = Float64[]
    dict["P [pu]"] = Float64[]
    dict["Q [pu]"] = Float64[]

    df = DataFrame
    for (i, v) in enumerate(vertices)
        # i = 1
        # v = first(vertices)
        tpn = only(v("TopologicalNode"))
        V = CGMES.get_voltage_pu(tpn)

        terminals = v("Terminal")
        S = isempty(terminals) ? 0 : sum(CGMES.get_injected_power_pu.(terminals))

        push!(dict["N"], i)
        push!(dict["Bus Names"], getname(tpn))
        push!(dict["vm [pu]"], abs(V))
        push!(dict["varg [deg]"], rad2deg(angle(V)))
        push!(dict["P [pu]"], real(S))
        push!(dict["Q [pu]"], imag(S))
    end

    DataFrame(dict)
end
