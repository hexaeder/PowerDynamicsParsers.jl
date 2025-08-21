abstract type AbstractBranchSubgraph end
abstract type SingleBranchSubgraph <: AbstractBranchSubgraph end
struct ACLineSegment <: SingleBranchSubgraph end
struct PowerTransformer <: SingleBranchSubgraph end

function is_abstract_branch_subgraph(c::CIMCollection)
    length(c("TopologicalNode")) == 2
end

CONDUCTING_EQUIPMENT = [
    "ACLineSegment",
    "PowerTransformer",
]

function is_single_branch_subgraph(c::CIMCollection)
    nodes = collect(values(objects(c)))
    cond_idx = findall(is_class(CONDUCTING_EQUIPMENT), nodes)
    length(cond_idx) == 1
end

function get_components(::SingleBranchSubgraph, c::CIMCollection)
    nodes = collect(values(objects(c)))
    cond_idx = findall(is_class(CONDUCTING_EQUIPMENT), nodes)
    segment = nodes[only(cond_idx)]
    src_node, dst_node = c("TopologicalNode")

    segment_terminals = filter(is_terminal, base_object.(segment.references))
    src_terminals = filter(is_terminal, base_object.(src_node.references))
    dst_terminals = filter(is_terminal, base_object.(dst_node.references))

    src_terminal = only(src_terminals ∩ segment_terminals)
    dst_terminal = only(dst_terminals ∩ segment_terminals)

    (; src_node, src_terminal, dst_node, dst_terminal, segment)
end

function get_edge_model(c)
    class = classify_branch_subgraph(c)
    isnothing(class) && throw(ArgumentError("Cannot parse this edge model!"))

    model = get_edge_model(class, c)

    comp = get_components(class, c)
    model.metadata[:cgmes_subgraph] = c
    model.metadata[:cgmes_class] = class
    model.metadata[:cgmes_components] = comp
    set_graphelement!(model, Symbol(getname(comp.src_node)) => Symbol(getname(comp.dst_node)))

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
function get_edge_model(class::ACLineSegment, c::CIMCollection)
    comp = CGMES.get_components(class, c)

    if !allequal(CGMES.get_base_voltage, (comp.src_node, comp.dst_node, comp.segment))
        throw(ArgumentError("ACLineSegment must have the same base voltage on both ends!"))
    end

    # Sbase is just 100 because Vbase is in kv!
    Vbase = CGMES.get_base_voltage(comp.segment) # kV
    Zbase = Vbase^2 / SBASE
    Ybase = 1 / Zbase

    props = properties(comp.segment)
    G_src = props["gch"]/2 / Ybase
    G_dst = G_src
    B_src = props["bch"]/2 / Ybase
    B_dst = B_src
    R = props["r"] / Zbase
    X = props["x"] / Zbase
    piline = Library.PiLine(; G_src, G_dst, B_src, B_dst, R, X, name=:ACLineSegment)

    name = hasname(comp.segment) ? getname(comp.segment) : "ACLineSegment"

    Line(MTKLine(piline, name=Symbol(name)))
end

function get_edge_model(::PowerTransformer, c::CIMCollection)
    error("not implmeneted")
end

function classify_branch_subgraph(c::CIMCollection)
    @assert is_abstract_branch_subgraph(c) "Expected a edge subgraph (two Topolocial nodes)!"

    if is_single_branch_subgraph(c)
        segment = only(c(CONDUCTING_EQUIPMENT))
        is_class(segment, "ACLineSegment") && return ACLineSegment()
        is_class(segment, "PowerTransformer") && return PowerTransformer()
    end

    return nothing
end

get_base_voltage(ob::CIMObject) = follow_ref(ob[r"BaseVoltage$"])["nominalVoltage"]

function get_voltage_pu(o::CIMObject)
    sv = only(filter(is_class("SvVoltage"), CGMES.base_object.(o.references)))
    θ = deg2rad(sv["angle"])
    V = sv["v"] / get_base_voltage(o)
    return V * exp(im * θ)
end
"""
ATTENTION: we go from load to injector convention
"""
function get_injected_power_pu(o::CIMObject)
    sv = only(filter(is_class("SvPowerFlow"), CGMES.base_object.(o.references)))
    P = sv["p"] / SBASE
    Q = sv["q"] / SBASE
    return -P - im * Q
end


function test_powerflow(e::EdgeModel)
    comp = e.metadata[:cgmes_components]
    src_uc = CGMES.get_voltage_pu(comp.src_node)
    dst_uc = CGMES.get_voltage_pu(comp.dst_node)

    default_overrides = Dict{Symbol, Any}(
        :src₊u_r => real(src_uc),
        :src₊u_i => imag(src_uc),
        :dst₊u_r => real(dst_uc),
        :dst₊u_i => imag(dst_uc)
    )
    guess_overrides = Dict{Symbol, Any}(
        :src₊i_r => 1.0,
        :src₊i_i => 0.0,
        :dst₊i_r => 1.0,
        :dst₊i_i => 0.0
    )
    state = initialize_component(e; default_overrides, guess_overrides, verbose=false)
    P, Q = get_initial_state(e, state, [:src₊P, :src₊Q])
    Sref = CGMES.get_injected_power_pu(comp.src_terminal)
    Pref = real(Sref)
    Qref = imag(Sref)
    if !isapprox(P, Pref)
        println("Powerflow result P=$P does not match reference P=$Pref")
    else
        println("Powerflow result P=$P matches reference P=$Pref")
    end
    if !isapprox(Q, Qref)
        println("Powerflow result Q=$Q does not match reference Q=$Qref")
    else
        println("Powerflow result Q=$Q matches reference Q=$Qref")
    end
end
