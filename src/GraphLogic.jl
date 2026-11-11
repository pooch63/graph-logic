"""
    GraphLogic

Bipartite and weighted unipartite graph data structures plus dataset download / indexing pipeline.

  - `graph.jl`      BipartiteGraph → freeze → FrozenBipartite, SubGraph queries,
                    and the `Subgraph` submodule of set-style helpers
  - `unipartite.jl` UnipartiteGraph → freeze → FrozenUnipartite (undirected,
                    weighted edges)
  - `io.jl`         `load_bipartite_graph` / `load_unipartite_graph` CSV loaders
  - `paths.jl`      `data/<provider>/<dataset>/` layout, discovery, `.dataignore`
  - `index.jl`      `index_dataset` (remap raw ids → 1:n)
  - `providers/`    download + convert adapters (amazon, konect*, catster, roadmap)
  - `catalog.jl`    built-in dataset catalogs in `catalogs/<provider>.json`
  - `cli.jl`        `process_main` / `fetch_main` behind the `bin/` scripts
"""
module GraphLogic

using CSV
using DataFrames
using Downloads
using JSON3

include("graph.jl")
include("unipartite.jl")
include("io.jl")
include("paths.jl")
include("index.jl")
include("providers/common.jl")
include("providers/amazon.jl")
include("providers/konect.jl")
include("providers/roadmap.jl")
include("catalog.jl")
include("cli.jl")

# --- graph.jl ---
export BipartiteGraph, FrozenBipartite, SubGraph, GraphRemapping, Subgraph
export add_u!, add_v!, add_edge!, rem_u!, rem_v!, rem_node!, rem_edge!
export rem_edge_structural!, rem_u_structural!, rem_v_structural!, rem_node_structural!
export has_edge, node_exists, get_neighbors, get_degree, edge_data
export freeze, build_frozen, compact_frozen, remap_subgraph, induce_frozen
export neighbor_range, neighbor_range_u, neighbor_range_v
export subgraph_length, bind_membership!, ensure_membership!, invalidate_membership!
export degrees_into_subgraph_u!, degrees_into_subgraph_v!
export split_fg, subgraph_edge_counts, accumulate_edges!
export is_neighbor, neighbors_u, neighbors_v, degree_u, degree_v
export neighbors_u_in_subgraph, neighbors_v_in_subgraph
export degree_in_subgraph, degree_in_subgraph_u, degree_in_subgraph_v
export nondegree_in_subgraph, nondegree_in_subgraph_u, nondegree_in_subgraph_v

# --- unipartite.jl ---
export UnipartiteGraph, FrozenUnipartite
export add_vertex!, rem_vertex!, add_weight!
export num_vertices, num_edges, neighbors, degree, edge_weight, weighted_degree
export total_weight, induced_weight

# --- io.jl / paths.jl / index.jl ---
export load_bipartite_graph, load_unipartite_graph
export normalize_dataset_name, dataset_dir, resolve_graph_path, split_provider_dataset
export count_indexed_edges, load_data_ignore_patterns, dataset_key_ignored
export discover_indexed_graphs, dataset_key_matches_prefix, order_graphs_by_edges
export index_dataset

# --- providers ---
export ProviderAdapter, PROVIDER_REGISTRY, register_provider!, get_provider, list_providers
export PROVIDER_ALIASES, load_provider_aliases!, resolve_alias, gunzip_file!
export process_with_provider, read_dataset_manifest, ensure_dataset!, load_dataset
export convert_jsonl_to_csv, amazon_category_name, amazon_download_raw!, amazon_convert!
export konect_dataset_stem, konect_remote_name, konect_find_out_file, konect_extract_archive!
export konect_download_tsv_archive!, konect_download_opsahl_txt!, konect_download_raw!
export konect_convert_edgelist!
export roadmap_dataset_stem, roadmap_download_raw!, roadmap_convert!

# --- catalog.jl ---
export Catalog, CatalogEntry, CatalogMetric
export catalog_names, catalog, catalog_entry, catalog_dataset_key

# --- cli.jl ---
export process_main, fetch_main

end # module GraphLogic
