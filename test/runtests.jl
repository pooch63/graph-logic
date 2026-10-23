using Test
using GraphLogic
using GraphLogic.Subgraph

# 3×3 bipartite graph: u1–{v1,v2,v3}, u2–{v1,v2}, u3–{v3}
function small_graph()
    g = BipartiteGraph{Nothing}()
    for (u, v) in [(1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (3, 3)]
        add_edge!(g, u, v, nothing)
    end
    return g
end

@testset "BipartiteGraph mutation" begin
    g = small_graph()
    @test has_edge(g, 1, 2)
    @test !has_edge(g, 3, 1)
    @test degree_u(g, 1) == 3
    @test degree_v(g, 3) == 2
    @test rem_edge!(g, 1, 2)
    @test !has_edge(g, 1, 2)
    @test rem_u!(g, 3)
    @test !node_exists(g, true, 3)
    @test !(3 in neighbors_v(g, 3))

    wg = BipartiteGraph{Float64}()
    add_edge!(wg, 1, 1, 0.5)
    @test edge_data(wg, 1, 1) == 0.5
end

@testset "FrozenBipartite queries" begin
    fg = freeze(small_graph())
    @test sort(neighbors_u(fg, 1)) == [1, 2, 3]
    @test sort(neighbors_v(fg, 1)) == [1, 2]
    @test degree_u(fg, 2) == 2
    @test degree_v(fg, 3) == 2
    @test degree_u(fg, 99) == 0
    @test is_neighbor(fg, true, 3, 3)
    @test !is_neighbor(fg, false, 3, 2)
    @test length(fg.v_adj) == 6

    fb = build_frozen([(1, 1), (2, 2)], 3, 2)
    @test length(fb.u_ids) == 3
    @test degree_u(fb, 3) == 0
end

@testset "SubGraph queries" begin
    fg = freeze(small_graph())
    sg = SubGraph(Set([1, 2]), Set([1, 2, 3]))
    @test Subgraph.edge_count(fg, sg) == 5
    @test missing_edges(fg, sg) == 1
    @test degree_in_subgraph_u(fg, 2, sg) == 2
    @test nondegree_in_subgraph_u(fg, 2, sg) == 1
    @test nonneighbors_in_subgraph(fg, true, 2, sg) == Set([3])

    bind_membership!(sg, fg)
    @test degree_in_subgraph_u(fg, 2, sg) == 2
    Subgraph.add_node!(sg, fg, true, 3)
    @test Subgraph.edge_count(fg, sg) == 6
    Subgraph.remove_node!(sg, fg, true, 3)
    @test Subgraph.edge_count(fg, sg) == 5

    hits = zeros(Int, length(fg.u_ids))
    degrees_into_subgraph_u!(hits, fg, sg)
    @test hits[fg.u_index[1]] == 3

    subs = [SubGraph(Set([1]), Set([1, 2])), SubGraph(Set([3]), Set([3]))]
    @test subgraph_edge_counts(fg, subs) == [2, 1]
    @test sort(split_fg(fg, subs)[2]) == [(3, 3)]

    c = clone(sg)
    Subgraph.add_node!(c, false, 9)
    @test !(9 in sg.V)
end

@testset "compact / induce" begin
    fg = freeze(small_graph())
    cfg, remap = compact_frozen(fg)
    @test cfg.u_ids == collect(1:3)
    back = remap_subgraph(remap, SubGraph(Set(1:3), Set(1:3)))
    @test back.U == Set(1:3)

    keep_u = [fg.u_index[1], fg.u_index[2]]
    keep_v = [fg.v_index[1], fg.v_index[2]]
    ind = induce_frozen(fg, keep_u, keep_v)
    @test length(ind.v_adj) == 4
end

@testset "dataset paths" begin
    @test split_provider_dataset("amazon/boxes") == ("amazon", "boxes")
    @test split_provider_dataset("twitter") == ("twitter", "twitter")
    @test dataset_key_matches_prefix("konect/bitcoin", "konect")
    @test !dataset_key_matches_prefix("konect-small/foo", "konect")
    @test dataset_key_matches_prefix("amazon/boxes", "konect,amazon")
    @test dataset_key_ignored("foo/example", ["example"])
    @test dataset_key_ignored("raw/x", ["raw/"])
    @test !dataset_key_ignored("amazon/boxes", ["amazon/music"])
    @test resolve_graph_path("konect/x"; data_root="d") == joinpath("d", "konect", "x", "indexed_interactions.csv")
end

@testset "provider pipeline (offline)" begin
    @test "konect" in list_providers()
    @test "amazon" in list_providers()
    @test konect_dataset_stem("download.tsv.foo.tar.bz2") == "foo"

    mktempdir() do root
        write(joinpath(root, "aliases.txt"), "konect/bitcoin=custom-remote\namazon/tiny=Tiny_Cat\n")
        load_provider_aliases!(root; force=true)
        @test konect_remote_name("bitcoin") == "custom-remote"
        @test konect_remote_name("euroroad") == "subelj_euroroad"
        @test amazon_category_name("amazon/TINY") == "Tiny_Cat"

        raw = joinpath(root, "edges.txt")
        write(raw, "% comment\n10 20\n10 30 1.0\n# skip\n40 20\n")
        out = process_with_provider("konect", "toy"; source=raw, data_root=root)
        @test isfile(out.indexed_csv)
        @test count_indexed_edges(out.indexed_csv) == 3

        entries = discover_indexed_graphs(; data_root=root)
        @test [e.key for e in entries] == ["konect/toy"]

        fg = load_dataset("konect/toy"; data_root=root, download=false)
        @test length(fg.u_ids) == 2 && length(fg.v_ids) == 2
        @test_throws ErrorException load_dataset("konect/missing"; data_root=root, download=false)

        jsonl = joinpath(root, "reviews.jsonl")
        write(jsonl, """{"user_id": "a", "asin": "x"}\n{"user_id": "b", "asin": "x"}\n{"bad": 1}\n""")
        out = process_with_provider("amazon", "tiny"; source=jsonl, data_root=root)
        g, n = load_bipartite_graph(out.indexed_csv)
        @test n == 2

        write(joinpath(root, "datasets.txt"), "# c\nkonect/toy\n\namazon/tiny\n")
        @test read_dataset_manifest(joinpath(root, "datasets.txt")) == ["konect/toy", "amazon/tiny"]
    end
end
