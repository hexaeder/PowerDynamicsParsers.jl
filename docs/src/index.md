```@meta
CurrentModule = PowerDynamicsCGMES
```

```@example wgl
using CairoMakie
using GraphMakie
using Graphs
using Markdown
using PowerDynamicsCGMES

g = smallgraph(:karate)
fig = Figure()
ax = Axis(fig[2,2]);
Label(fig[1,1], "fobarbarxo\nfobarlkj\nlkjasdf")
#Label(fig[2,1], "bar", tellwidth=false)
p = graphplot!(g)
hidespines!(ax)
hidedecorations!(ax)
fig
```
```@example wgl
PowerDynamicsCGMES.html_hover_map(fig, repr.(1:34)) # hide
```
