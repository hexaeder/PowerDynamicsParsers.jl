module PSSE

using CSV
using DataFrames
using OrderedCollections

export parse_raw_file

function parse_raw_file(file; verbose=true)
    glob = PSSE.parse_global(file)
    rev = glob.rev
    raw_sections = PSSE.find_raw_sections(file)
    parsed_sections = OrderedDict{String,DataFrame}()
    for (name, lines) in raw_sections
        if  isempty(Iterators.filter(!iscomment, lines))
            verbose && printstyled("Skip empty $name section... \n", color=:blue)
        elseif PSSE.istable(lines)
            verbose && printstyled("Try parsing $name section... \n", color=:blue)
            df = PSSE.parse_table_section(rev, name, lines)
            parsed_sections[name] = df
        else
            printstyled("Skip section $name, no parser available.\n", color=:red)
        end
    end
    parsed_sections
end

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


    # read file
    lines = readlines(file)

    # Create an ordered dictionary to hold the section ranges
    sections = OrderedDict{String,Vector{String}}()
    current_section = nothing
    for s in sectionbreaks
        if isnothing(current_section)
            current_section = (; name = s.begin_of, start = s.i+1)
        elseif s.end_of == current_section.name
            range = current_section.start:(s.i-1)
            sections[current_section.name] = lines[range]
            current_section = (; name = s.begin_of, start = s.i+1)
        else
            error("Unexpected section break: $s while in section $(current_section)")
        end
    end
    sections
end

KNOWN_HEADERS = OrderedDict(
    30 => OrderedDict(
        "BUS" => ["i", "name", "basekv", "ide", "gl", "bl", "area", "zone", "vm", "va", "owner"],
        "BRANCH" => ["i", "j", "ckt", "r", "x", "b", "rate_a", "rate_b", "rate_c", "gi", "bi", "gj", "bj", "st", "len", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4"],
        "LOAD" => ["i", "id", "status", "area", "zone", "pl", "ql", "ip", "iq", "yp", "yq", "owner", "scale", "intrpt"],
        "GENERATOR" => ["i", "id", "pg", "qg", "qt", "qb", "vs", "ireg", "mbase", "zr", "zx", "rt", "xt", "gtap", "stat", "rmpct", "pt", "pb", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4", "wmod", "wpf"],
        "FIXED SHUNT" => ["i", "id", "status", "gl", "bl"],
        "AREA" => ["i", "isw", "pdes", "ptol", "arname"],
        "SWITCHED SHUNT" => ["i", "modsw", "vswhi", "vswlo", "swrem", "rmpct", "rmidnt", "binit", "n1", "b1", "n2", "b2", "n3", "b3", "n4", "b4", "n5", "b5", "n6", "b6", "n7", "b7", "n8", "b8"],
        "ZONE" => ["i", "zoname"],
        "OWNER" => ["i", "owname"]
    ),
    33 => OrderedDict(
        "BUS" => ["i", "name", "basekv", "ide", "area", "zone", "owner", "vm", "va", "nvhi", "nvlo", "evhi", "evlo"],
        "BRANCH" => ["i", "j", "ckt", "r", "x", "b", "rate_a", "rate_b", "rate_c", "gi", "bi", "gj", "bj", "st", "met", "len", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4"],
        "LOAD" => ["i", "id", "status", "area", "zone", "pl", "ql", "ip", "iq", "yp", "yq", "owner", "scale"],  # Note: some files may have 14th column "intrpt" (interruptible load flag)
        "GENERATOR" => ["i", "id", "pg", "qg", "qt", "qb", "vs", "ireg", "mbase", "zr", "zx", "rt", "xt", "gtap", "stat", "rmpct", "pt", "pb", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4", "wmod", "wpf"],
        "FIXED SHUNT" => ["i", "id", "status", "gl", "bl"],
        "AREA" => ["i", "isw", "pdes", "ptol", "arname"],
        "SWITCHED SHUNT" => ["i", "modsw", "adjm", "stat", "vswhi", "vswlo", "swrem", "rmpct", "rmidnt", "binit", "n1", "b1", "n2", "b2", "n3", "b3", "n4", "b4", "n5", "b5", "n6", "b6", "n7", "b7", "n8", "b8"],
        "ZONE" => ["i", "zoname"],
        "OWNER" => ["i", "owname"]
    )
)

iscomment(l) = startswith(l, r"\s*@!")

function istable(lines)
    allequal(Iterators.filter(!iscomment, lines)) do l
        count(",", l)
    end
end

function parse_table_section(rev, name, lines)
    # detuct the header
    _header = determine_header(rev, name, lines)
    header = isnothing(_header) ? 0 : _header

    io = IOBuffer()
    for l in lines
        println(io, l)
    end
    seekstart(io)

    CSV.read(io, DataFrame; header, normalizenames=true, quotechar=''', comment="@!", silencewarnings=true)
end

function determine_header(rev, name, lines)
    header = parse_header_commment(name, lines)
    !isnothing(header) && return header

    if haskey(KNOWN_HEADERS, rev) && haskey(KNOWN_HEADERS[rev], name)
        return KNOWN_HEADERS[rev][name]
    end
    @warn "Don't know the header, using default!"

end

function parse_header_commment(name, lines)
    commented = findall(iscomment, lines)
    if isempty(commented)
        return nothing
    else
        length(commented) == 1 || throw(ArgumentError("Expected exactly one comment line in section $name, found $(length(commented))"))
        headerline = lines[only(commented)]
        header = split(headerline, ",")
        header_normalized = map(header) do s
            s = replace(s, r"^\s*@!" => "") # remove comments
            s = replace(s, "'" => "") # remove single quotes
            s = replace(s, r"^\s*|\s*$" => "") # remove leading and trailing whitespace
            lowercase(s)
        end
        return header_normalized
    end
end

end
