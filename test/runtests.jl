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

@testset "UnipartiteGraph" begin
    # triangle 1–2–3 plus pendant 3–4 and a self-loop on 4
    g = UnipartiteGraph()
    add_edge!(g, 1, 2, 0.5)
    add_edge!(g, 2, 3, 2.0)
    add_edge!(g, 3, 1)
    add_edge!(g, 3, 4, 1.5)
    add_edge!(g, 4, 4, 3.0)
    @test num_vertices(g) == 4
    @test num_edges(g) == 5
    @test has_edge(g, 2, 1) && edge_weight(g, 2, 1) == 0.5
    @test edge_weight(g, 1, 3) == 1.0
    @test degree(g, 4) == 2
    @test weighted_degree(g, 3) == 4.5
    @test total_weight(g) == 8.0

    add_edge!(g, 1, 2, 0.25)          # overwrite, no new edge
    @test num_edges(g) == 5 && edge_weight(g, 1, 2) == 0.25
    add_weight!(g, 2, 1, 1.0)
    @test edge_weight(g, 1, 2) == 1.25
    add_weight!(g, 5, 6, 2.0)
    @test num_edges(g) == 6
    @test rem_edge!(g, 6, 5) && !has_edge(g, 5, 6) && num_edges(g) == 5
    @test !rem_edge!(g, 1, 4)

    fg = freeze(g)
    @test num_vertices(fg) == 6 && num_edges(fg) == 5
    @test neighbors(fg, 3) == [1, 2, 4]
    @test neighbors(fg, 4) == [3, 4]
    @test degree(fg, 5) == 0 && degree(fg, 99) == 0
    @test weighted_degree(fg, 4) == 4.5
    @test edge_weight(fg, 2, 1) == 1.25
    @test edge_weight(fg, 1, 4; default=0.0) == 0.0
    @test_throws KeyError edge_weight(fg, 1, 4)
    @test has_edge(fg, 4, 4) && !has_edge(fg, 1, 99)
    @test total_weight(fg) == total_weight(g)
    @test induced_weight(fg, [1, 2, 3]) == 1.25 + 2.0 + 1.0
    @test induced_weight(fg, [3, 4, 42]) == 4.5

    @test rem_vertex!(g, 3)
    @test num_edges(g) == 2 && !has_edge(g, 1, 3) && degree(g, 4) == 1

    ig = UnipartiteGraph{Int}()
    add_edge!(ig, 1, 2)
    @test edge_weight(freeze(ig), 1, 2) === 1

    mktempdir() do root
        plain = joinpath(root, "plain.csv")
        write(plain, "u,v\n1,2\n2,1\n2,3\n")
        pg, rows = load_unipartite_graph(plain)
        @test rows == 3 && num_edges(pg) == 2
        @test edge_weight(pg, 1, 2) == 2.0     # duplicate merged with +

        weighted = joinpath(root, "weighted.csv")
        write(weighted, "u,v,w\n1,2,0.5\n2,1,4\n3,3,1\n")
        wg, _ = load_unipartite_graph(weighted; combine=max)
        @test edge_weight(wg, 1, 2) == 4.0 && has_edge(wg, 3, 3)
        lg, _ = load_unipartite_graph(weighted; weight_col=nothing, default_weight=7)
        @test edge_weight(lg, 1, 2) == 14.0
    end
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

@testset "catalogs" begin
    @test catalog_names() == ["amazon", "konect"]

    konect = catalog("konect")
    @test length(konect.entries) == 1326
    @test allunique(entry.id for entry in konect.entries)
    @test konect.entries[1].id == "brunson_south-africa"
    @test konect.entries[end].id == "dimacs10-uk-2007-05"

    za = catalog_entry("konect", "ucidata-zachary")
    @test za.name == "Zachary karate club"
    @test za.attributes["code"] == "ZA"
    @test za.attributes["category"] == "Human social network"
    @test za.attributes["structure"] == "Unipartite, undirected"
    @test za.n == 34 && za.m == 78
    @test za.available
    @test za.metrics["fill"] ≈ 0.139037
    @test za.metrics["density"] ≈ 0.139037
    @test za.metrics["average_degree"] ≈ 4.58824
    @test za.metrics["clustering_coefficient"] ≈ 0.255682
    @test za.metrics["degree_assortativity"] ≈ -0.475613
    @test za.metrics["degree_assortativity_p_value"] ≈ 3.50945e-10
    @test za.metrics["diameter"] == 5
    @test catalog_dataset_key(za) == "konect/ucidata-zachary"
    @test za.url == "http://konect.cc/networks/ucidata-zachary/"
    @test any(item.key == "fill" && item.name == "Fill (density)" for item in konect.legend)

    sa = catalog_entry(konect, "brunson_south-africa")
    @test sa.attributes["structure"] == "Bipartite, undirected"
    @test sa.n == 11 && sa.m == 13
    @test sa.metrics["n_left"] == 6
    @test sa.metrics["n_right"] == 5
    @test sa.metrics["fill"] ≈ 0.433333

    amazon = catalog("amazon")
    @test length(amazon.entries) == 34
    @test allunique(entry.id for entry in amazon.entries)
    beauty = catalog_entry("amazon", "All_Beauty")
    @test beauty.name == "All Beauty"
    @test beauty.attributes["structure"] == "Bipartite, undirected"
    @test beauty.metrics["n_users"] == 632_000
    @test beauty.metrics["n_items"] == 112_600
    @test beauty.n == 632_000 + 112_600
    @test beauty.m == 701_500
    @test beauty.metrics["density"] ≈ 701_500 / (632_000 * 112_600)
    @test occursin("All_Beauty.jsonl.gz", beauty.url)
    @test occursin("meta_All_Beauty.jsonl.gz", beauty.attributes["meta_url"])

    boxes = catalog_entry(amazon, "Subscription_Boxes")
    @test boxes.metrics["n_users"] == 15_200
    @test boxes.metrics["n_items"] == 641
    @test boxes.m == 16_200
    @test boxes.n == 15_200 + 641
    @test catalog_dataset_key(boxes) == "amazon/Subscription_Boxes"
    @test any(item.key == "density" for item in amazon.legend)

    @test_throws ArgumentError catalog("no-such-catalog")
    @test_throws ArgumentError catalog_entry("konect", "not-a-network")
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
