struct DynamicDevice
    busid::Int
    name::String
    parameters::Union{NamedTuple, Tuple}
end

function parse_dyr_file(dyr_file::String)
    devices_by_bus = Dict{Int, Vector{DynamicDevice}}()

    # Read all lines and parse multi-line devices
    lines = readlines(dyr_file)
    i = 1
    while i <= length(lines)
        line = strip(lines[i])

        # Skip empty lines and comments
        if isempty(line) || startswith(line, r"\s*@!")
            i += 1
            continue
        end

        # Parse dynamic device data (potentially multi-line)
        device, lines_consumed = parse_dyr_entry(lines, i)
        if device !== nothing
            # Add device to the appropriate bus
            if !haskey(devices_by_bus, device.busid)
                devices_by_bus[device.busid] = DynamicDevice[]
            end
            push!(devices_by_bus[device.busid], device)
        end

        i += lines_consumed
    end

    return devices_by_bus
end

function parse_dyr_entry(lines::Vector{String}, start_idx::Int)
    # Combine lines until we find the terminating '/'
    combined_line = ""
    lines_consumed = 0

    for i in start_idx:length(lines)
        line = String(strip(lines[i]))
        lines_consumed += 1

        # Skip empty lines and comments in the middle of entries
        if isempty(line) || startswith(line, r"\s*@!")
            continue
        end

        # Add line content (remove trailing '/' if present)
        if endswith(line, '/')
            # This is the end of the entry
            combined_line *= " " * line[1:end-1]
            break
        else
            combined_line *= " " * line
        end
    end

    # Parse the combined line
    device = parse_dyr_line(combined_line)
    return device, lines_consumed
end

function parse_dyr_line(line::String)
    # Remove trailing '/' and whitespace
    line = String(strip(line))
    if endswith(line, '/')
        line = String(strip(line[1:end-1]))
    end

    # Split by spaces and commas, handling quoted strings
    tokens = parse_tokens(line)

    if length(tokens) < 3
        @warn "Skipping malformed DYR line: $line"
        return nothing
    end

    try
        # First token: bus number
        bus_number = parse(Int, tokens[1])

        # Second token: device name (quoted string)
        device_name = strip(tokens[2], ['\'', '"'])

        # Third token and beyond: all parameters including generator ID
        all_parameters = parse_parameters(tokens[3:end])

        dynamic_device = DynamicDevice(bus_number, device_name, all_parameters)

        return dynamic_device

    catch e
        @warn "Error parsing DYR line '$line': $e"
        return nothing
    end
end

function parse_tokens(line::String)
    tokens = String[]
    current_token = ""
    in_quotes = false
    quote_char = nothing

    i = 1
    while i <= length(line)
        char = line[i]

        if char in ['\'', '"'] && !in_quotes
            # Start of quoted string
            in_quotes = true
            quote_char = char
            current_token *= char
        elseif char == quote_char && in_quotes
            # End of quoted string
            in_quotes = false
            current_token *= char
            quote_char = nothing
        elseif in_quotes
            # Inside quoted string
            current_token *= char
        elseif char in [' ', ',', '\t']
            # Delimiter outside quotes
            if !isempty(current_token)
                push!(tokens, current_token)
                current_token = ""
            end
        else
            # Regular character
            current_token *= char
        end

        i += 1
    end

    # Add final token
    if !isempty(current_token)
        push!(tokens, current_token)
    end

    return tokens
end

function parse_parameters(param_tokens::Vector{String})
    parameters = []

    for token in param_tokens
        # Try to parse as number, otherwise keep as string
        if occursin(r"^-?\d*\.?\d+([eE][+-]?\d+)?$", token)
            # Looks like a number
            if occursin('.', token) || occursin('e', lowercase(token))
                push!(parameters, parse(Float64, token))
            else
                # Check if it's too large for Int32, use Int64 if needed
                try
                    push!(parameters, parse(Int32, token))
                catch
                    push!(parameters, parse(Int64, token))
                end
            end
        else
            # Keep as string (remove quotes if present)
            push!(parameters, strip(token, ['\'', '"']))
        end
    end

    return tuple(parameters...)
end

