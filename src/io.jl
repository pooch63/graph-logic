#=
=================================================================================
Graph CSV I/O
=================================================================================
=#

"""
    load_bipartite_graph(filepath; max_lines=nothing) -> (BipartiteGraph{Nothing}, edge_count)

Reads a `u,v[,...]` CSV (with header) and builds a mutable bipartite graph
where U = u and V = v. Extra columns beyond `u` and `v` are ignored.

Uses `CSV.File`, which memory-maps local files (`buffer_in_memory=false`) and
applies multithreaded chunked parsing when the input is large enough.
"""
function load_bipartite_graph(filepath::String; max_lines::Union{Int,Nothing}=nothing)
    g = BipartiteGraph{Nothing}()

    rows = CSV.File(
        filepath;
        header = 1,
        select = [:u, :v],
        types = Dict(:u => Int, :v => Int),
        buffer_in_memory = false,
        limit = max_lines,
    )

    for row in rows
        add_edge!(g, row.u, row.v, nothing)
    end

    edge_count = length(rows)
    println("Graph edges: $(edge_count)")
    return g, edge_count
end

"""
    load_unipartite_graph(filepath; weight_col=:w, weight_type=Float64,
                          default_weight=1, combine=+, max_lines=nothing)
        -> (UnipartiteGraph{weight_type}, row_count)

Reads a `u,v[,w]` CSV (with header) into an undirected weighted graph where
`u` and `v` share one id space. If `weight_col` is missing from the file (or
`nothing`), every edge gets `default_weight`. Repeated `{u, v}` rows (in
either orientation) are merged with `combine(old, new)` — the default `+`
turns an unweighted multigraph into multiplicity weights; pass
`(_, new) -> new` to keep the last.

Note: point this at `interactions.csv`, not `indexed_interactions.csv` —
`index_dataset` remaps `u` and `v` independently (bipartite), so the same
vertex gets different ids on each side.
"""
function load_unipartite_graph(filepath::String;
    weight_col::Union{Symbol,Nothing}=:w,
    weight_type::Type{W}=Float64,
    default_weight::Real=1,
    combine=+,
    max_lines::Union{Int,Nothing}=nothing,
) where {W<:Real}
    header = Symbol.(propertynames(CSV.File(filepath; header=1, limit=0)))
    use_w = weight_col !== nothing && weight_col in header

    rows = CSV.File(
        filepath;
        header = 1,
        select = use_w ? [:u, :v, weight_col] : [:u, :v],
        types = use_w ? Dict(:u => Int, :v => Int, weight_col => W) : Dict(:u => Int, :v => Int),
        buffer_in_memory = false,
        limit = max_lines,
    )

    g = UnipartiteGraph{W}()
    dw = W(default_weight)
    for row in rows
        w = use_w ? W(getproperty(row, weight_col)) : dw
        if has_edge(g, row.u, row.v)
            add_edge!(g, row.u, row.v, combine(edge_weight(g, row.u, row.v), w))
        else
            add_edge!(g, row.u, row.v, w)
        end
    end

    row_count = length(rows)
    println("Graph rows: $(row_count)  vertices: $(num_vertices(g))  edges: $(num_edges(g))")
    return g, row_count
end
