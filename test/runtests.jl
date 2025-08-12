using PowerDynamicsCGMES
using Test
using OrderedCollections
using XML

@testset "PowerDynamicsCGMES.jl" begin
    # Write your tests here.
end

DATA = joinpath(pkgdir(PowerDynamicsCGMES), "data")
DL = joinpath(DATA, "20151231T2300Z_XX_YYY_DL_.xml")
DY = joinpath(DATA, "20151231T2300Z_XX_YYY_DY_.xml")
GL = joinpath(DATA, "20151231T2300Z_XX_YYY_GL_.xml")
SSH = joinpath(DATA, "20151231T2300Z_XX_YYY_SSH_.xml")
SV = joinpath(DATA, "20151231T2300Z_XX_YYY_SV_.xml")
TP = joinpath(DATA, "20151231T2300Z_XX_YYY_TP_.xml")
EQ = joinpath(DATA, "20151231T2300Z_YYY_EQ_.xml")

# nodetype(node)      →   XML.NodeType (an enum type)
# tag(node)           →   String or Nothing
# attributes(node)    →   OrderedDict{String, String} or Nothing
# value(node)         →   String or Nothing
# children(node)      →   Vector{typeof(node)}
# is_simple(node)     →   Bool (whether node is simple .e.g. <tag>item</tag>)
# simple_value(node)   →   e.g. "item" from <tag>item</tag>)

eq_raw = XML.read(EQ, Node)
dl_raw = XML.read(DL, Node)
dy_raw = XML.read(DY, Node)
gl_raw = XML.read(GL, Node)
sh_raw = XML.read(SSH, Node)
sv_raw = XML.read(SV, Node)
tp_raw = XML.read(TP, Node)

eq_rdf = rdf_node(eq_raw)
dl_rdf = rdf_node(dl_raw)
dy_rdf = rdf_node(dy_raw)
gl_rdf = rdf_node(gl_raw)
sh_rdf = rdf_node(sh_raw)
sv_rdf = rdf_node(sv_raw)
tp_rdf = rdf_node(tp_raw)

# next we look at the contents

rdf = eq_rdf

objects = OrderedDict{String, CIMObject}()

for el in children(rdf)
    if is_object(el)
        obj = CIMObject(el)
        objects[obj.id] = obj
    else
        @warn "Skipping $(tag(el)), no parser for this element type."
    end
end

collect(values(objects))[1]
