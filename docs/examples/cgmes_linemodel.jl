#=
# Linemodel calculateion

The goal of this example is, to create line models for relativly simple lines
(single ACLineSegment branch) and check if their results match the powerflow.
=#
dataset1 = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "1-EHVHV-mixed-all-2-sw-Ausschnitt"))
nodes, edges = split_topologically(dataset1; warn=false)
edges[1]
#=
In this seconde dataset, the first line is an ACLineSegment with two terminals.
We go ahead and try to build a power dynamics line model for it:
=#
em = CGMES.get_edge_model(edges[1])

#=
I wrote a small function, which takes the voltage steady state from the surronding voltage nodes,
calculates the power at both ends of the line model and compares it to the powerflow result
stored in the CGMES dataset (i.e. the power through the terminals at both ends)
=#
CGMES.test_powerflow(em)
#=
However, the results do not match!
For debugging, i implemented another function: given the voltages and powers at both ends,
this function tries to calculate the correct R, X, G, B parameters for a pi-line model
=#
CGMES.determine_branch_parameters(edges[1])
#=
We see, that the R and X values are different from the calculated ones. If we use the calculated
variables instead, the powerflow result matches the values from the dataset:
=#
set_default!(em, :ACLineSegment₊R, 0.00669677741911068)
set_default!(em, :ACLineSegment₊X, 0.005344772670911904)
CGMES.test_powerflow(em)

#=
At first, i thought this is due to some base calculation or some other parameter mismatch.
However, lets take the dataset i got first
=#
dataset2 = CIMDataset(joinpath(pkgdir(PowerDynamicsParsers), "test", "CGMES", "data", "testdata1"))
nodes, edges = split_topologically(dataset2; warn=false)
nothing # hide

#=
Here, we have 3 powerlines and each of them is just a pi-line. So we can check again:

**Powerline 1:**
=#
em = CGMES.get_edge_model(edges[1])
#-
CGMES.test_powerflow(em)
#=
**Powerline 2:**
=#
em = CGMES.get_edge_model(edges[2])
CGMES.test_powerflow(em)
#=
**Powerline 3:**
=#
em = CGMES.get_edge_model(edges[3])
CGMES.test_powerflow(em)

#=
For this model, the backward caculation of R, X, G and B can be validated too
=#
CGMES.determine_branch_parameters(edges[1])
#=
Which confirms that the

!!! error "Error in the CGMES Data?"
    In conclusion, it looks like the CGMES data is not consistent in the newer dataset! Either
    the branch parameters are wrong, or the powerflow results are wrong.
=#
