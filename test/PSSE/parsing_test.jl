using PowerDynamicsParsers
using PowerDynamicsParsers.PSSE
using PowerDynamicsParsers.PSSE: PSSESection
using OrderedCollections, DataFrames

@testset "raw daata parsing" begin
    f1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.RAW")
    f2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.RAW")
    f3 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Texas2k_series24_case1_2016summerPeak.RAW")
    f4 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "RTS-GMLC.RAW")

    parse_raw_file(f1)
    parse_raw_file(f2)
    parse_raw_file(f3)
    parse_raw_file(f4)
end

@testset "dyr data parsing" begin
    # Test DYR parsing with simplified DynamicDevice structure
    dyr1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.dyr")
    dyr2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.dyr")
    dyr3 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Texas2k_series24_case1_2016summerPeak.dyr")

    # Test parsing DYR files
    devices1 = parse_dyr_file(dyr1)
    @test devices1 isa Dict{Int, Vector{DynamicDevice}}
    @test !isempty(devices1)

    # Test that we have devices for each test file
    devices2 = parse_dyr_file(dyr2)
    @test !isempty(devices2)

    devices3 = parse_dyr_file(dyr3)
    @test !isempty(devices3)

    # Test specific device parsing for IEEE 39 bus case
    # Should have devices on buses with generators (30, 31, 32, 33, 34, 35, 36, 37, 38, 39)
    @test length(devices1) == 10  # 10 generator buses
    @test all(busid -> busid in 30:39, keys(devices1))  # Bus IDs 30-39

    # Each bus should have 2 devices (GENROU and IEEEST)
    for (busid, bus_devices) in devices1
        @test length(bus_devices) == 2
        device_names = [dev.name for dev in bus_devices]
        @test "GENROU" in device_names
        @test "IEEEST" in device_names

        # Test that all devices have the correct bus ID
        @test all(dev -> dev.busid == busid, bus_devices)

        # Test that parameters are tuples with generator ID as first parameter
        for dev in bus_devices
            @test dev.parameters isa Tuple
            @test length(dev.parameters) > 0
            @test dev.parameters[1] == 1  # Generator ID should be 1 for IEEE 39 bus case
        end
    end

    # Test that parameters are correctly parsed as numbers
    sample_device = first(devices1)[2][1]  # First device on first bus
    @test all(param -> isa(param, Union{Float64, Int32, Int64, String}), sample_device.parameters)

    # Test Hawaii case with multiple generator IDs
    # Bus 2 should have multiple generator units with different IDs
    @test haskey(devices2, 2)
    bus2_devices = devices2[2]
    gen_ids = [dev.parameters[1] for dev in bus2_devices if dev.name == "GENROU"]
    @test length(unique(gen_ids)) > 1  # Should have multiple different generator IDs

    # Test Texas case structure
    @test length(devices3) > 400  # Large number of buses
    sample_texas_device = first(devices3)[2][1]
    @test sample_texas_device.busid > 1000  # Texas buses have 4-digit numbers
end

@testset "unified psse parsing" begin
    # Test the new unified parse_psse function
    raw1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.RAW")
    dyr1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.dyr")

    raw2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.RAW")
    dyr2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.dyr")

    # Test unified parsing
    psse_data1 = parse_psse(raw1, dyr1)
    parse_psse(raw1) # auto detection of dyr file
    @test psse_data1 isa PSSEData

    # Test structure
    @test psse_data1.filename == "IEEE 39 bus.RAW"
    @test psse_data1.revision == 33
    @test psse_data1.sections isa OrderedDict{String, DataFrame}
    @test psse_data1.dynamic_devices isa Dict{Int, Vector{DynamicDevice}}

    # Test content
    @test !isempty(psse_data1.sections)
    @test !isempty(psse_data1.dynamic_devices)
    @test haskey(psse_data1.sections, "BUS")
    @test length(psse_data1.dynamic_devices) == 10  # 10 generator buses

    # Test Hawaii case
    psse_data2 = parse_psse(raw2, dyr2)
    @test psse_data2.filename == "Hawaii40_20231026.RAW"
    @test psse_data2.revision isa Int
    @test length(psse_data2.dynamic_devices) == 10

    # Test that all data is preserved correctly
    @test nrow(psse_data1.sections["BUS"]) == 39  # 39 buses
    @test all(busid -> busid in 30:39, keys(psse_data1.dynamic_devices))  # Generator buses 30-39
end
