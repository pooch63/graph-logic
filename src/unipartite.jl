# =============================================================================
# unipartite.jl
#
# Undirected, edge-weighted graph over a single vertex set. Same two-phase
# design as graph.jl:
#   mutation  -> UnipartiteGraph{W}  : add/remove vertices & weighted edges
#   freeze()  -> FrozenUnipartite{W} : one-time O(V+E) conversion to CSR
#
# Each undirected edge {u, v} is stored in both adjacency lists with the same
# weight; a self-loop {u, u} is stored once. Degrees count distinct neighbors,
# so a self-loop contributes 1 to degree and its weight once to
# weighted_degree.
# =============================================================================

# --------------------------------------------------------------------------
# mutable graph, arbitrary Int vertex ids, Dict{Int,Dict{Int,W}} adjacency
# --------------------------------------------------------------------------

mutable struct UnipartiteGraph{W<:Real}
    adj::Dict{Int, Dict{Int, W}}   # v => (neighbor => weight)
    ne::Int                        # undirected edge count (self-loops count once)
end

UnipartiteGraph{W}() where {W<:Real} = UnipartiteGraph{W}(Dict{Int,Dict{Int,W}}(), 0)
UnipartiteGraph() = UnipartiteGraph{Float64}()

# --- vertices ---
function add_vertex!(g::UnipartiteGraph{W}, v::Int) where {W}
    get!(g.adj, v, Dict{Int,W}())
    return g
end

function rem_vertex!(g::UnipartiteGraph, v::Int)
    haskey(g.adj, v) || return false
    for u in keys(g.adj[v])
        u == v && continue
        delete!(g.adj[u], v)
    end
    g.ne -= length(g.adj[v])
    delete!(g.adj, v)
    return true
end

# --- edges ---
"""
    add_edge!(g::UnipartiteGraph, u, v, w=1)

Add undirected edge `{u, v}` with weight `w`, creating vertices as needed.
If the edge already exists its weight is replaced; use `add_weight!` to
accumulate instead.
"""
function add_edge!(g::UnipartiteGraph{W}, u::Int, v::Int, w::Real=one(W)) where {W}
    add_vertex!(g, u)
    add_vertex!(g, v)
    haskey(g.adj[u], v) || (g.ne += 1)
    g.adj[u][v] = w
    g.adj[v][u] = w
    return g
end

"""
    add_weight!(g::UnipartiteGraph, u, v, w)

Add `w` to the weight of `{u, v}`, creating the edge (with weight `w`) if
missing. Handy for collapsing duplicate edges into multiplicities.
"""
function add_weight!(g::UnipartiteGraph{W}, u::Int, v::Int, w::Real) where {W}
    current = has_edge(g, u, v) ? g.adj[u][v] : zero(W)
    return add_edge!(g, u, v, current + w)
end

function rem_edge!(g::UnipartiteGraph, u::Int, v::Int)
    has_edge(g, u, v) || return false
    delete!(g.adj[u], v)
    delete!(g.adj[v], u)
    g.ne -= 1
    return true
end

# --- queries ---
has_edge(g::UnipartiteGraph, u::Int, v::Int) = haskey(g.adj, u) && haskey(g.adj[u], v)
node_exists(g::UnipartiteGraph, v::Int) = haskey(g.adj, v)
num_vertices(g::UnipartiteGraph) = length(g.adj)
num_edges(g::UnipartiteGraph) = g.ne
neighbors(g::UnipartiteGraph, v::Int) = keys(g.adj[v])
degree(g::UnipartiteGraph, v::Int) = length(g.adj[v])
edge_weight(g::UnipartiteGraph, u::Int, v::Int) = g.adj[u][v]
weighted_degree(g::UnipartiteGraph{W}, v::Int) where {W} = sum(values(g.adj[v]); init=zero(W))

"""Sum of all edge weights (each undirected edge counted once)."""
function total_weight(g::UnipartiteGraph{W}) where {W}
    s = zero(W)
    for (u, nbrs) in g.adj, (v, w) in nbrs
        u <= v && (s += w)
    end
    return s
end


# --------------------------------------------------------------------------
# FREEZE: one-time O(V+E) conversion to a symmetric CSR.
#   offsets / adj / weights, neighbors sorted by dense index per vertex.
# --------------------------------------------------------------------------

struct FrozenUnipartite{W<:Real}
    ids::Vector{Int}           # dense index -> original id
    index::Dict{Int,Int}       # original id -> dense index
    offsets::Vector{Int}       # CSR offsets into adj / weights (length n+1)
    adj::Vector{Int}           # flattened neighbor dense indices, sorted per vertex
    weights::Vector{W}         # parallel to adj
    ne::Int                    # undirected edge count
end

function freeze(g::UnipartiteGraph{W}) where {W}
    ids = sort!(collect(keys(g.adj)))
    index = Dict(v => i for (i, v) in enumerate(ids))
    n = length(ids)

    offsets = Vector{Int}(undef, n + 1)
    offsets[1] = 1
    for (i, v) in enumerate(ids)
        offsets[i + 1] = offsets[i] + length(g.adj[v])
    end

    adj = Vector{Int}(undef, offsets[end] - 1)
    weights = Vector{W}(undef, offsets[end] - 1)
    for (i, v) in enumerate(ids)
        k = offsets[i]
        # ids are sorted, so sorting by original id also sorts by dense index
        for u in sort!(collect(keys(g.adj[v])))
            adj[k] = index[u]
            weights[k] = g.adj[v][u]
            k += 1
        end
    end

    return FrozenUnipartite{W}(ids, index, offsets, adj, weights, g.ne)
end

# Range into adj/weights for the neighbors of dense index i
@inline neighbor_range(fg::FrozenUnipartite, i::Int) = fg.offsets[i]:(fg.offsets[i+1] - 1)

num_vertices(fg::FrozenUnipartite) = length(fg.ids)
num_edges(fg::FrozenUnipartite) = fg.ne
node_exists(fg::FrozenUnipartite, v::Int) = haskey(fg.index, v)

"""
    neighbors(fg::FrozenUnipartite, v) -> Vector{Int}

Neighbor ids of `v` (sorted). Empty if `v` isn't in `fg`.
"""
function neighbors(fg::FrozenUnipartite, v::Int)
    i = get(fg.index, v, nothing)
    i === nothing && return Int[]
    return [fg.ids[fg.adj[k]] for k in neighbor_range(fg, i)]
end

"""Number of distinct neighbors of `v`; 0 if `v` isn't in `fg`."""
function degree(fg::FrozenUnipartite, v::Int)
    i = get(fg.index, v, nothing)
    i === nothing && return 0
    return length(neighbor_range(fg, i))
end

"""Sum of incident edge weights of `v`; zero if `v` isn't in `fg`."""
function weighted_degree(fg::FrozenUnipartite{W}, v::Int) where {W}
    i = get(fg.index, v, nothing)
    i === nothing && return zero(W)
    s = zero(W)
    @inbounds for k in neighbor_range(fg, i)
        s += fg.weights[k]
    end
    return s
end

# Position of dense j in dense i's (sorted) neighbor list, or 0.
@inline function _edge_slot(fg::FrozenUnipartite, i::Int, j::Int)
    r = neighbor_range(fg, i)
    k = searchsortedfirst(view(fg.adj, r), j)
    return (k <= length(r) && fg.adj[r[k]] == j) ? r[k] : 0
end

function has_edge(fg::FrozenUnipartite, u::Int, v::Int)
    i = get(fg.index, u, nothing)
    j = get(fg.index, v, nothing)
    (i === nothing || j === nothing) && return false
    return _edge_slot(fg, i, j) != 0
end

"""
    edge_weight(fg::FrozenUnipartite, u, v; default=nothing)

Weight of `{u, v}` via binary search. Throws `KeyError` if the edge is
missing, unless `default` is given.
"""
function edge_weight(fg::FrozenUnipartite, u::Int, v::Int; default=nothing)
    i = get(fg.index, u, nothing)
    j = get(fg.index, v, nothing)
    k = (i === nothing || j === nothing) ? 0 : _edge_slot(fg, i, j)
    if k == 0
        default === nothing && throw(KeyError((u, v)))
        return default
    end
    return fg.weights[k]
end

function total_weight(fg::FrozenUnipartite{W}) where {W}
    s = zero(W)
    @inbounds for i in eachindex(fg.ids), k in neighbor_range(fg, i)
        i <= fg.adj[k] && (s += fg.weights[k])
    end
    return s
end

"""
    induced_weight(fg::FrozenUnipartite, vertices) -> W

Total weight of edges with both endpoints in `vertices` (original ids).
Unknown ids are ignored.
"""
function induced_weight(fg::FrozenUnipartite{W}, vertices) where {W}
    inside = falses(length(fg.ids))
    for v in vertices
        i = get(fg.index, v, nothing)
        i === nothing || (inside[i] = true)
    end
    s = zero(W)
    @inbounds for i in eachindex(fg.ids)
        inside[i] || continue
        for k in neighbor_range(fg, i)
            j = fg.adj[k]
            inside[j] && i <= j && (s += fg.weights[k])
        end
    end
    return s
end
