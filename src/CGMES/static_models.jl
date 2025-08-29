using PowerDynamics.NetworkDynamics: str_significant

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

function is_single_branch_subgraph(c::AbstractCIMCollection)
    nodes = collect(values(objects(c)))
    cond_idx = findall(is_class(CONDUCTING_EQUIPMENT), nodes)
    length(cond_idx) == 1
end

function get_components(::SingleBranchSubgraph, c::AbstractCIMCollection)
    nodes = collect(values(objects(c)))
    cond_idx = findall(is_class(CONDUCTING_EQUIPMENT), nodes)
    segment = nodes[only(cond_idx)]

    endnodes = c("TopologicalNode")
    src_node = endnodes[findfirst(n -> getname(n) == c.metadata[:src_name], endnodes)]
    dst_node = endnodes[findfirst(n -> getname(n) == c.metadata[:dst_name], endnodes)]
    src_idx = c.metadata[:src_idx]
    dst_idx = c.metadata[:dst_idx]

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
function get_edge_model(class::ACLineSegment, c::AbstractCIMCollection)
    comp = CGMES.get_components(class, c)

    if !allequal(CGMES.get_base_voltage, (comp.src_node, comp.dst_node, comp.segment))
        throw(ArgumentError("ACLineSegment must have the same base voltage on both ends!"))
    end

    # Sbase is just 100 because Vbase is in kv!
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

    piline = Library.PiLine(; G_src, G_dst, B_src, B_dst, R, X, name=:ACLineSegment)

    name = hasname(comp.segment) ? getname(comp.segment) : "ACLineSegment"

    Line(MTKLine(piline, name=Symbol(name)))
end

function get_edge_model(::PowerTransformer, c::AbstractCIMCollection)
    error("not implmeneted")
end

function classify_branch_subgraph(c::AbstractCIMCollection)
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
    Sref = CGMES.get_injected_power_pu(comp.src_terminal)
    Pref = real(Sref)
    Qref = imag(Sref)

    validate_power_component(P, Pref, "Active Power (P)")
    validate_power_component(Q, Qref, "Reactive Power (Q)")
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
    edgemodel = Line(MTKLine(branch))
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
