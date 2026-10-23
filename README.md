# GraphLogic.jl

Shared bipartite-graph toolkit, extracted from `aco-mkdb`:

- **Graph structures** (`src/graph.jl`): mutable `BipartiteGraph` → `freeze` → CSR-backed
  `FrozenBipartite`, `SubGraph` point/batch queries, and the `Subgraph` submodule
  (`add_node!`, `edge_count`, `missing_edges`, …).
- **I/O** (`src/io.jl`): `load_bipartite_graph` for indexed `u,v` CSVs.
- **Dataset layout** (`src/paths.jl`): `data/<provider>/<dataset>/`, discovery,
  `.dataignore`, ordering by edge count.
- **Download pipeline** (`src/providers/`, `src/index.jl`): provider adapters for
  KONECT (`konect`, `konect-small`, `catster`), Amazon Reviews 2023 (`amazon`), and
  SNAP road networks (`roadmap`), plus id indexing.

## Install

Local checkout (what `aco-mkdb` and `epsilon-core` use):

```bash
julia -e 'using Pkg; Pkg.develop(path="/path/to/graph-logic")'
```

From GitHub, once pushed:

```bash
julia -e 'using Pkg; Pkg.add(url="https://github.com/<you>/GraphLogic.jl")'
```

## Quick start

```julia
using GraphLogic

# Downloads + indexes into data/konect-small/euroroad/ on first use.
fg = load_dataset("konect-small/euroroad")

degree_u(fg, 1)
sg = SubGraph(Set([1, 2]), Set(neighbors_u(fg, 1)))
Subgraph.edge_count(fg, sg)
```

Lower-level pieces:

```julia
path = ensure_dataset!("amazon/boxes")             # fetch if missing → indexed CSV path
g, nE = load_bipartite_graph(path)                 # mutable graph
fg = freeze(g)                                     # read-only CSR graph
order_graphs_by_edges(; prefix="konect-small")     # discover local datasets
process_with_provider("konect", "bitcoin"; download=true)
```

## CLIs

```bash
julia --project=. bin/process.jl konect/bitcoin --download
julia --project=. bin/process.jl amazon/boxes --source=Subscription_Boxes.jsonl
julia --project=. bin/fetch_datasets.jl data/datasets.txt --skip-existing --prefix=konect-small
julia --project=. bin/index_dataset.jl interactions.csv indexed.csv mappings/
```

Any project can expose the same commands with a two-line script:

```julia
using GraphLogic
fetch_main(ARGS)    # or process_main(ARGS)
```

All commands accept `--data-root=PATH` (default `data`).

## Data layout

```
<data_root>/
  datasets.txt                 # manifest: one provider/dataset key per line
  aliases.txt                  # optional provider/local=Remote_Name overrides
  .dataignore                  # optional gitignore-style skip list for discovery
  <provider>/<dataset>/
    raw/                       # downloaded archives / extracted files
    interactions.csv           # u,v (source ids)
    indexed_interactions.csv   # u,v remapped to 1..n
    mappings/                  # user_mapping.csv, item_mapping.csv, metadata.txt
```

## Adding a provider

```julia
using GraphLogic

function my_download_raw!(dataset_name, dest_dir)
    # Downloads.download(url, path); maybe gunzip_file!(...)
    return path_to_raw_file
end

function my_convert!(raw_path, interactions_csv)
    # write a u,v CSV to interactions_csv
    return nothing
end

register_provider!(ProviderAdapter("myprovider", my_download_raw!, my_convert!))
# Download unsupported? pass `nothing` instead of my_download_raw!.
```

Register at runtime from your project, or add a file under `src/providers/` and
`include` it from `src/GraphLogic.jl` to make it built-in.

## Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```
