module PSSE

using CSV
using DataFrames
using OrderedCollections

function parse_global(file)
    globpattern = r"^\s*(\d+),\s*([\d.]+),\s*(\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)"
    m = nothing
    for l in eachline(file)
        m = match(globpattern, l)
        isnothing(m) || break
    end
    ic = parse(Int, m[1])          # Case identification number
    sbase = parse(Float64, m[2])   # System base MVA
    rev = parse(Int, m[3])         # PSS/E revision/version number
    xfr_rat= parse(Int, m[4])      # Transformer rating flag
    nxfr_rat = parse(Int, m[5])    # Non-transformer rating flag
    basfrq = parse(Float64, m[6])  # Base frequency in Hz
    (; ic, sbase, rev, xfr_rat, nxfr_rat, basfrq)
end

function match_section_break(l)
    is_substation_subheading(x) = contains(x, r"^SUBSTATION\s+\w+")

    # Pattern for transitions: "0 /END OF X DATA, BEGIN Y DATA"
    transition_pattern = r"^\s*0\s*/\s*END OF\s*(.+?)\s*DATA,\s*BEGIN\s*(.+?)\s*DATA"

    m = match(transition_pattern, l)
    if !isnothing(m)
        is_substation_subheading(m[1]) && return nothing
        return (; end_of = m[1], begin_of = m[2])
    end

    # Pattern for endings: "0 /END OF X DATA"
    end_pattern = r"^\s*0\s*/\s*END OF\s*(.+?)\s*DATA\s*$"

    m = match(end_pattern, l)
    if !isnothing(m)
        any(is_substation_subheading, m) && return nothing
        return (; end_of = m[1], begin_of = missing)
    end

    if startswith(l, r"\s*0/")
        error("Found unexpected `0 /` pattern in line: $l")
    end

    return nothing
end

function find_raw_sections(file)
    sectionbreaks = []
    headerlines = 1
    for (i, l) in enumerate(eachline(file))
        if headerlines < 3
            startswith(l, r"\s*@!") && continue
            headerlines += 1
        elseif headerlines == 3
            push!(sectionbreaks, (; i, end_of=nothing, begin_of=missing))
            headerlines += 1
        else
            sectionbreak = match_section_break(l)
            if !isnothing(sectionbreak)
                push!(sectionbreaks, (; i, sectionbreak...))
            end
        end
    end
    # sometimes the "begin of" is missing, so we fill it based on the following section end
    for (i, sb) in enumerate(sectionbreaks)
        if ismissing(sb.begin_of) && i < length(sectionbreaks)
            # println("Fill missing begin for section break at line $(sb.i): $(sectionbreaks[i+1].end_of)")
            sectionbreaks[i] = (; i=sb.i, end_of=sb.end_of, begin_of=sectionbreaks[i+1].end_of)
        end
    end

    # Create an ordered dictionary to hold the section ranges
    sections = OrderedDict{String,UnitRange}()
    current_section = nothing
    for s in sectionbreaks
        if isnothing(current_section)
            current_section = (; name = s.begin_of, start = s.i+1)
        elseif s.end_of == current_section.name
            range = current_section.start:(s.i-1)
            sections[current_section.name] = range
            current_section = (; name = s.begin_of, start = s.i+1)
        else
            error("Unexpected section break: $s while in section $(current_section)")
        end
    end
    sections
end

end
