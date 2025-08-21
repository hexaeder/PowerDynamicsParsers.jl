# Helper function to count class occurrences in dynamic devices
function _device_count(devices::Dict{Int, Vector{DynamicDevice}})
    counts = Dict{String, Int}()
    for bus_devices in values(devices)
        for device in bus_devices
            counts[device.name] = get(counts, device.name, 0) + 1
        end
    end
    counts
end

# Helper function to format device count breakdown
function _format_device_breakdown(io::IO, device_counts::Dict{String, Int}, indent::String="    ")
    if !isempty(device_counts)
        for (device_name, count) in sort(collect(device_counts))
            println(io, indent, count, " ", device_name)
        end
    end
end

# Helper function to format section breakdown
function _format_section_breakdown(io::IO, sections::OrderedDict{String, DataFrame}, indent::String="    ")
    if !isempty(sections)
        for (section_name, df) in sections
            println(io, indent, section_name, ": ", nrow(df), " rows × ", ncol(df), " columns")
        end
    end
end

# Show methods for DynamicDevice
function Base.show(io::IO, device::DynamicDevice)
    c = IOContext(io, :compact => true)
    show(c, MIME"text/plain"(), device)
end

function Base.show(io::IO, mime::MIME"text/plain", device::DynamicDevice)
    compact = get(io, :compact, false)

    if compact
        # Compact mode: Bus:DeviceName(param_count params)
        print(io, "Bus ", device.busid, ":")
        printstyled(io, device.name, color=:blue)
        print(io, "(", length(device.parameters), " params)")
    else
        # Non-compact mode: Multi-line display
        printstyled(io, device.name, " Dynamic Device", color=:blue)
        println(io)
        println(io, "  Bus ID: ", device.busid)
        println(io, "  Device Type: ", device.name)
        println(io, "  Parameters: ", length(device.parameters), " values")

        # Show first few parameters
        if length(device.parameters) > 0
            println(io, "  Parameter values:")
            max_show = min(10, length(device.parameters))
            for i in 1:max_show
                param = device.parameters[i]
                println(io, "    [", i, "]: ", param, " (", typeof(param), ")")
            end
            if length(device.parameters) > max_show
                println(io, "    ... and ", length(device.parameters) - max_show, " more")
            end
        end
    end
end

function Base.show(io::IO, mime::MIME"text/plain", data::PSSEData)
    compact = get(io, :compact, false)

    total_devices = sum(length(devices) for devices in values(data.dynamic_devices))

    if compact
        print(io, "PSSEData: ")
        printstyled(io, data.filename, color=:blue)
        print(io, " (", length(data.sections), " sections, ", total_devices, " devices)")
    else
        print(io, "PSSEData: ")
        printstyled(io, data.filename, color=:blue)
        println(io)
        println(io, "  Filename: ", data.filename)
        println(io, "  PSSE Revision: ", data.revision)

        # RAW file sections
        println(io, "  RAW Sections: ", length(data.sections))
        _format_section_breakdown(io, data.sections)

        # Dynamic devices
        println(io, "  Dynamic Devices: ", total_devices, " on ", length(data.dynamic_devices), " buses")
        device_counts = _device_count(data.dynamic_devices)
        _format_device_breakdown(io, device_counts)

        # Show bus distribution
        if !isempty(data.dynamic_devices)
            bus_device_counts = [length(devices) for devices in values(data.dynamic_devices)]
            min_devices = minimum(bus_device_counts)
            max_devices = maximum(bus_device_counts)
            avg_devices = round(sum(bus_device_counts) / length(bus_device_counts), digits=1)

            println(io, "  Bus Distribution:")
            println(io, "    Devices per bus: ", min_devices, " to ", max_devices, " (avg: ", avg_devices, ")")

            # Show first few buses as examples
            example_buses = collect(keys(data.dynamic_devices))[1:min(3, length(data.dynamic_devices))]
            for bus_id in example_buses
                devices = data.dynamic_devices[bus_id]
                device_names = [d.name for d in devices]
                println(io, "    Bus ", bus_id, ": ", join(device_names, ", "))
            end
            if length(data.dynamic_devices) > 3
                println(io, "    ... and ", length(data.dynamic_devices) - 3, " more buses")
            end
        end
    end
end

# Helper function to show PSSE data summary
function show_summary(data::PSSEData)
    io = stdout

    printstyled(io, "PSSE Data Summary for ", data.filename, "\n", bold=true, color=:blue)
    println(io, "=" ^ 60)

    # Basic info
    println(io, "PSSE Revision: ", data.revision)
    println(io, "Total RAW Sections: ", length(data.sections))
    println(io, "Total Dynamic Devices: ", sum(length(devices) for devices in values(data.dynamic_devices)))
    println(io, "Buses with Dynamic Devices: ", length(data.dynamic_devices))

    # RAW sections detail
    println(io, "\nRAW File Sections:")
    println(io, "-" ^ 40)
    total_rows = 0
    for (section_name, df) in data.sections
        rows = nrow(df)
        cols = ncol(df)
        total_rows += rows
        println(io, "  ", rpad(section_name, 20), " ", lpad(string(rows), 6), " rows × ", lpad(string(cols), 2), " cols")
    end
    println(io, "  ", rpad("TOTAL", 20), " ", lpad(string(total_rows), 6), " rows")

    # Dynamic devices detail
    println(io, "\nDynamic Devices:")
    println(io, "-" ^ 40)
    device_counts = _device_count(data.dynamic_devices)
    total_devices = sum(values(device_counts))
    for (device_type, count) in sort(collect(device_counts), by=x->x[2], rev=true)
        percentage = round(100 * count / total_devices, digits=1)
        println(io, "  ", rpad(device_type, 20), " ", lpad(string(count), 6), " (", rpad(string(percentage), 4), "%)")
    end

    # Bus analysis
    if !isempty(data.dynamic_devices)
        println(io, "\nBus Analysis:")
        println(io, "-" ^ 40)
        bus_ids = sort(collect(keys(data.dynamic_devices)))
        bus_device_counts = [length(data.dynamic_devices[bus]) for bus in bus_ids]

        println(io, "  Bus ID Range: ", minimum(bus_ids), " to ", maximum(bus_ids))
        println(io, "  Devices per Bus: ", minimum(bus_device_counts), " to ", maximum(bus_device_counts))
        println(io, "  Average Devices per Bus: ", round(sum(bus_device_counts) / length(bus_device_counts), digits=1))

        # Show buses with most devices
        bus_device_pairs = [(bus, length(devices)) for (bus, devices) in data.dynamic_devices]
        sort!(bus_device_pairs, by=x->x[2], rev=true)
        println(io, "  Top 5 Buses by Device Count:")
        for i in 1:min(5, length(bus_device_pairs))
            bus_id, device_count = bus_device_pairs[i]
            device_names = [d.name for d in data.dynamic_devices[bus_id]]
            println(io, "    Bus ", lpad(string(bus_id), 4), ": ", device_count, " devices (", join(unique(device_names), ", "), ")")
        end
    end

    println(io, "\n", "=" ^ 60)
end
