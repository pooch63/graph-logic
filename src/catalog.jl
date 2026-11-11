#=
=================================================================================
Dataset catalogs
=================================================================================
One loader for every built-in catalog. Each catalog is a JSON file in
`src/catalogs/<provider>.json`; the filename is the name passed to `catalog`.
Adding a catalog is adding a file. No provider-specific types.

Schema:
  provider, source, retrieved, note
  legend: [{key, symbol, name}, ...]
  entries: [{
    id, name, n, m, url, available,
    attributes: {string fields such as category, structure, edge_type},
    tags: [string, ...],
    metrics: {key: number, ...}
  }, ...]

`n` and `m` are the node and edge counts. Other numbers live in `metrics`.
A missing metrics key was not published for that entry. `catalog_dataset_key`
returns `"<provider>/<id>"` for `load_dataset`.
=#

"""
One dataset in a catalog.

`n` and `m` are the number of nodes and edges. `metrics` holds the other
numbers; values are `Int64` when the source printed an integer and `Float64`
otherwise. `attributes` holds the source's string fields (category, structure,
edge type, and whatever else that catalog records).
"""
struct CatalogEntry
    provider::String
    id::String
    name::String
    n::Int
    m::Int
    url::String
    available::Bool
    attributes::Dict{String,String}
    tags::Vector{String}
    metrics::Dict{String,Union{Int64,Float64}}
end

"""
Name of one statistic stored in `CatalogEntry.metrics`.
"""
struct CatalogMetric
    key::String
    symbol::String
    name::String
end

"""
A named collection of datasets loaded from `src/catalogs/<provider>.json`.
"""
struct Catalog
    provider::String
    source::String
    retrieved::String
    note::String
    legend::Vector{CatalogMetric}
    entries::Vector{CatalogEntry}
    by_id::Dict{String,CatalogEntry}
end

const _CATALOG_CACHE = Dict{String,Catalog}()

catalog_dir() = joinpath(@__DIR__, "catalogs")

"""
    catalog_names() -> Vector{String}

Providers that have a catalog file in `src/catalogs`, in sorted order.
"""
function catalog_names()
    names = String[]
    for file in readdir(catalog_dir())
        endswith(file, ".json") || continue
        push!(names, file[1:end-5])
    end
    return sort!(names)
end

function _metric_value(value)
    return value isa Integer ? Int64(value) : Float64(value)
end

function _load_catalog(path::AbstractString, provider::AbstractString)
    raw = JSON3.read(read(path, String))
    declared = String(raw.provider)
    declared == provider || error(
        "Catalog file '$(basename(path))' declares provider '$declared'")

    entries = Vector{CatalogEntry}(undef, length(raw.entries))
    index = Dict{String,CatalogEntry}()
    for (i, row) in enumerate(raw.entries)
        attributes = Dict{String,String}()
        for (key, value) in pairs(row.attributes)
            attributes[String(key)] = String(value)
        end
        metrics = Dict{String,Union{Int64,Float64}}()
        for (key, value) in pairs(row.metrics)
            metrics[String(key)] = _metric_value(value)
        end
        entry = CatalogEntry(
            provider,
            String(row.id),
            String(row.name),
            Int(row.n),
            Int(row.m),
            String(row.url),
            Bool(row.available),
            attributes,
            String[String(tag) for tag in row.tags],
            metrics,
        )
        haskey(index, entry.id) &&
            error("Duplicate id '$(entry.id)' in catalog '$provider'")
        entries[i] = entry
        index[entry.id] = entry
    end
    legend = CatalogMetric[
        CatalogMetric(String(item.key), String(item.symbol), String(item.name))
        for item in raw.legend
    ]
    return Catalog(
        provider,
        String(raw.source),
        String(raw.retrieved),
        String(raw.note),
        legend,
        entries,
        index,
    )
end

"""
    catalog(provider) -> Catalog

Load the catalog for `provider` (`"konect"`, `"amazon"`, …). The result is
cached for the rest of the session.
"""
function catalog(provider::AbstractString)
    name = String(provider)
    haskey(_CATALOG_CACHE, name) && return _CATALOG_CACHE[name]
    path = joinpath(catalog_dir(), name * ".json")
    isfile(path) || throw(ArgumentError(
        "Unknown catalog '$name'. Available: $(join(catalog_names(), ", "))"))
    loaded = _load_catalog(path, name)
    _CATALOG_CACHE[name] = loaded
    return loaded
end

"""
    catalog_entry(provider, id) -> CatalogEntry
    catalog_entry(catalog, id) -> CatalogEntry

Look up one dataset by its catalog id (the KONECT internal name, or the Amazon
category filename such as `"Subscription_Boxes"`).
"""
function catalog_entry(cat::Catalog, id::AbstractString)
    key = String(id)
    haskey(cat.by_id, key) ||
        throw(ArgumentError("Unknown $(cat.provider) entry '$key'"))
    return cat.by_id[key]
end

catalog_entry(provider::AbstractString, id::AbstractString) =
    catalog_entry(catalog(provider), id)

"""
    catalog_dataset_key(entry) -> String

Dataset key accepted by `load_dataset` and `ensure_dataset!`,
`"<provider>/<id>"`.
"""
catalog_dataset_key(entry::CatalogEntry) = "$(entry.provider)/$(entry.id)"
