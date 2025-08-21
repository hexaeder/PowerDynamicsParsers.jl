using PowerDynamicsParsers
using PowerDynamicsParsers.PSSE
using PowerDynamicsParsers.PSSE: PSSESection

f1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.RAW")
f2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.RAW")
f3 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Texas2k_series24_case1_2016summerPeak.RAW")
f4 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "RTS-GMLC.RAW")

PSSE.parse_raw(file)


# match

PSSE.parse_global(file)



file = f1
file = f2
file = f3

sb2 = PSSE.find_raw_sections(f2)
sb3 = PSSE.find_raw_sections(f3)

sections = PSSE.find_raw_sections(f1)

name = "BUS"
lines = sb3["BUS"]


file = f1


parse_raw_file(f1)
parse_raw_file(f2)
parse_raw_file(f3)
parse_raw_file(f4)

PSSE.KNOWN_HEADERS[30]["SWITCHED SHUNT"]
PSSE.KNOWN_HEADERS[33]["SWITCHED SHUNT"]
