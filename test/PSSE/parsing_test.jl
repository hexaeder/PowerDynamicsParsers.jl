using PowerDynamicsParsers
using PowerDynamicsParsers.PSSE
using PowerDynamicsParsers.PSSE: PSSESection

f1 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "IEEE 39 bus.RAW")
f2 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Hawaii40_20231026.RAW")
f3 = joinpath(pkgdir(PowerDynamicsParsers), "test", "PSSE", "data", "Texas2k_series24_case1_2016summerPeak.RAW")

PSSE.parse_raw(file)


# match

PSSE.parse_global(file)



file = f1
file = f2
file = f3

sb1 = PSSE.find_raw_sections(f1)
sb2 = PSSE.find_raw_sections(f2)
sb3 = PSSE.find_raw_sections(f3)

