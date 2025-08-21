function parse_raw_file(file; verbose=true)
    glob = parse_global(file)
    rev = glob.rev
    raw_sections = find_raw_sections(file)
    parsed_sections = OrderedDict{String,DataFrame}()
    for (name, lines) in raw_sections
        if  isempty(Iterators.filter(!iscomment, lines))
            verbose && printstyled("Skip empty $name section... \n", color=:blue)
        elseif name == "TRANSFORMER"
            verbose && printstyled("Try parsing $name section... \n", color=:blue)
            try
                df = parse_transformer_section(rev, lines)
                parsed_sections[name] = df
            catch e
                printstyled("Error parsing TRANSFORMER section: $e\n", color=:red)
            end
        elseif istable(lines)
            verbose && printstyled("Try parsing $name section... \n", color=:blue)
            df = parse_table_section(rev, name, lines)
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

# Headers for each line of transformer data by version (single source of truth)
TRANSFORMER_LINE_HEADERS = OrderedDict(
    33 => [
        # Line 1: General transformer data (21 columns for v33)
        ["i", "j", "k", "ckt", "cw", "cz", "cm", "mag1", "mag2", "nmetr", "name", "stat", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4", "vecgrp"],
        # Line 2: Impedance data (3 columns)
        ["r1_2", "x1_2", "sbase1_2"],
        # Line 3: Winding 1 data (17 columns for v33)
        ["windv1", "nomv1", "ang1", "rata1", "ratb1", "ratc1", "cod1", "cont1", "rma1", "rmi1", "vma1", "vmi1", "ntp1", "tab1", "cr1", "cx1", "cnxa1"],
        # Line 4: Winding 2 data (2 columns)
        ["windv2", "nomv2"]
    ],
    34 => [
        # Line 1: General transformer data (21 columns for v34)
        ["i", "j", "k", "ckt", "cw", "cz", "cm", "mag1", "mag2", "nmetr", "name", "stat", "o1", "f1", "o2", "f2", "o3", "f3", "o4", "f4", "vecgrp"],
        # Line 2: Impedance data (3 columns)
        ["r1_2", "x1_2", "sbase1_2"],
        # Line 3: Winding 1 data (27 columns for v34 - 12 rating fields vs 3 in v33)
        ["windv1", "nomv1", "ang1", "rate1_1", "rate1_2", "rate1_3", "rate1_4", "rate1_5", "rate1_6", "rate1_7", "rate1_8", "rate1_9", "rate1_10", "rate1_11", "rate1_12", "cod1", "cont1", "rma1", "rmi1", "vma1", "vmi1", "ntp1", "tab1", "cr1", "cx1", "cnxa1"],
        # Line 4: Winding 2 data (2 columns)
        ["windv2", "nomv2"]
    ]
)

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

function parse_transformer_section(rev, lines)
    # Filter out comments and empty lines
    data_lines = filter(line -> !iscomment(line) && !isempty(strip(line)), lines)

    if length(data_lines) % 4 != 0
        @warn "Transformer section has $(length(data_lines)) lines, not divisible by 4. Some transformers may be incomplete."
    end

    # Get expected column structure for this version from single source of truth
    if !haskey(TRANSFORMER_LINE_HEADERS, rev)
        error("Unsupported PSSE version $rev for transformer parsing")
    end

    line_headers = TRANSFORMER_LINE_HEADERS[rev]
    # Derive expected column counts from headers
    expected_cols_per_line = [length(line_header) for line_header in line_headers]
    # Derive combined header by flattening all line headers
    combined_header = vcat(line_headers...)

    # Group lines into transformer records (4 lines each)
    num_complete_transformers = div(length(data_lines), 4)
    concatenated_transformers = String[]

    for i in 1:num_complete_transformers
        base_idx = (i-1) * 4
        transformer_lines = data_lines[base_idx+1:base_idx+4]

        # Check if it's a 2-winding transformer (K field = 0 in first line)
        first_line_fields = split(transformer_lines[1], ',')
        if length(first_line_fields) >= 3
            k_field = tryparse(Int, strip(first_line_fields[3]))
            if k_field !== nothing && k_field != 0
                error("3-winding transformers not supported yet. Found K=$k_field in transformer $i")
            end
        end

        # Pad each line to expected column count and concatenate
        padded_lines = String[]
        for (line_idx, line) in enumerate(transformer_lines)
            expected_cols = expected_cols_per_line[line_idx]
            padded_line = _pad_line_to_expected_columns(line, expected_cols)
            push!(padded_lines, padded_line)
        end

        # Concatenate all 4 lines
        concatenated_line = join(padded_lines, ",")
        push!(concatenated_transformers, concatenated_line)
    end

    # Parse concatenated lines with combined header
    io = IOBuffer()
    for line in concatenated_transformers
        println(io, line)
    end
    seekstart(io)

    return CSV.read(io, DataFrame; header=combined_header, normalizenames=true, quotechar=''', comment="@!", silencewarnings=true)
end

function _pad_line_to_expected_columns(line, expected_cols)
    actual_cols = count(',', line) + 1
    if actual_cols < expected_cols
        missing_cols = expected_cols - actual_cols
        return line * "," * repeat("missing,", missing_cols-1) * "missing"
    end
    return line
end