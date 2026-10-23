#=
=================================================================================
Command-line entry points
=================================================================================
`process_main(ARGS)` and `fetch_main(ARGS)` back `bin/process.jl` and
`bin/fetch_datasets.jl`. Any project can expose the same CLIs with a 2-line
script:

  using GraphLogic
  fetch_main(ARGS)

Output layout (nested names supported):
  <data_root>/<provider>/<dataset>/
    raw/                      # downloaded archives / extracted files
    interactions.csv          # u,v[,...] (source IDs)
    indexed_interactions.csv  # integer-indexed u,v graph
    mappings/                 # reverse maps + metadata
=#

function _flag_value(arg::AbstractString, flag::AbstractString)
    value = strip(split(arg, "=", limit=2)[2])
    isempty(value) && throw(ArgumentError("$flag requires a value"))
    return String(value)
end

# ------------------------------------------------------------------------------
# process: one provider/dataset
# ------------------------------------------------------------------------------

function parse_process_args(args)
    download = false
    source = nothing
    data_root = "data"
    positionals = String[]

    for arg in args
        if arg == "--download"
            download = true
        elseif startswith(arg, "--source=")
            source = split(arg, "=", limit=2)[2]
        elseif startswith(arg, "--data-root=")
            data_root = _flag_value(arg, "--data-root")
        elseif arg == "--help" || arg == "-h"
            return nothing
        elseif startswith(arg, "--")
            throw(ArgumentError("Unknown flag: $arg"))
        else
            push!(positionals, arg)
        end
    end

    provider = nothing
    dataset = nothing

    if length(positionals) == 1
        parts = split(replace(positionals[1], '\\' => '/'), '/'; keepempty=false)
        if length(parts) < 2
            throw(ArgumentError(
                "Pass a nested key 'provider/dataset' or two args: <provider> <dataset>"))
        end
        provider, dataset = split_provider_dataset(positionals[1])
    elseif length(positionals) == 2
        provider, dataset = positionals[1], positionals[2]
    else
        throw(ArgumentError("Expected <provider>/<dataset> or <provider> <dataset>"))
    end

    if !download && source === nothing
        throw(ArgumentError("Provide --download or --source=<path>"))
    end

    return (; provider, dataset, download, source, data_root)
end

function print_process_usage()
    println(stderr, "Usage:")
    println(stderr, "  julia bin/process.jl <provider>/<dataset> --download")
    println(stderr, "  julia bin/process.jl <provider>/<dataset> --source=/path/to/raw")
    println(stderr, "  julia bin/process.jl <provider> <dataset> --download")
    println(stderr, "")
    println(stderr, "Options:")
    println(stderr, "  --data-root=PATH      data root (default: data)")
    println(stderr, "")
    println(stderr, "Registered providers: $(join(list_providers(), ", "))")
    println(stderr, "")
    println(stderr, "Examples:")
    println(stderr, "  julia bin/process.jl amazon/Appliances --download")
    println(stderr, "  julia bin/process.jl amazon boxes --source=data/subscription-boxes.jsonl")
    println(stderr, "  julia bin/process.jl konect/bitcoin --download")
end

"""
    process_main(args=ARGS)

CLI: download (or take `--source=`) one `provider/dataset`, convert, and index it.
"""
function process_main(args=ARGS)
    try
        parsed = parse_process_args(args)
        if parsed === nothing
            print_process_usage()
            exit(0)
        end
        process_with_provider(parsed.provider, parsed.dataset;
            download=parsed.download, source=parsed.source, data_root=parsed.data_root)
    catch e
        if e isa ArgumentError
            println(stderr, "Error: ", e.msg)
            print_process_usage()
            exit(1)
        else
            rethrow()
        end
    end
end

# ------------------------------------------------------------------------------
# fetch: every key in a manifest file
# ------------------------------------------------------------------------------

function parse_fetch_args(args)
    manifest = nothing
    skip_existing = false
    dry_run = false
    prefix = nothing
    data_root = "data"

    for arg in args
        if arg == "--skip-existing"
            skip_existing = true
        elseif arg == "--dry-run"
            dry_run = true
        elseif startswith(arg, "--prefix=")
            prefix = _flag_value(arg, "--prefix")
        elseif startswith(arg, "--data-root=")
            data_root = _flag_value(arg, "--data-root")
        elseif arg == "--help" || arg == "-h"
            return nothing
        elseif startswith(arg, "--")
            throw(ArgumentError("Unknown flag: $arg"))
        else
            manifest = arg
        end
    end

    manifest === nothing && (manifest = joinpath(data_root, "datasets.txt"))
    return (; manifest, skip_existing, dry_run, prefix, data_root)
end

function print_fetch_usage()
    println(stderr, "Usage:")
    println(stderr, "  julia bin/fetch_datasets.jl [manifest.txt] [options]")
    println(stderr, "")
    println(stderr, "Options:")
    println(stderr, "  --skip-existing       skip when indexed_interactions.csv exists")
    println(stderr, "  --prefix=NAME         only keys under NAME/ (slash-bounded)")
    println(stderr, "  --dry-run             list actions without downloading")
    println(stderr, "  --data-root=PATH      data root (default: data; manifest defaults to PATH/datasets.txt)")
    println(stderr, "")
    println(stderr, "Registered providers: $(join(list_providers(), ", "))")
end

"""
    fetch_main(args=ARGS)

CLI: run the provider pipeline with `--download` for every key in a manifest
(default `<data_root>/datasets.txt`). Exits 1 if any dataset fails.
"""
function fetch_main(args=ARGS)
    try
        parsed = parse_fetch_args(args)
        if parsed === nothing
            print_fetch_usage()
            exit(0)
        end

        keys = read_dataset_manifest(parsed.manifest)
        if parsed.prefix !== nothing
            filter!(k -> dataset_key_matches_prefix(k, parsed.prefix), keys)
        end

        if isempty(keys)
            println("No datasets to fetch (manifest=$(parsed.manifest)).")
            exit(0)
        end

        println("Manifest: $(parsed.manifest)  ($(length(keys)) dataset(s))")
        parsed.dry_run && println("Dry run — no downloads.")

        failed = String[]
        skipped = 0
        ran = 0

        for (i, key) in enumerate(keys)
            provider, dataset = split_provider_dataset(key)
            out_csv = joinpath(dataset_dir(key; data_root=parsed.data_root), "indexed_interactions.csv")

            println()
            println("[$(i)/$(length(keys))] $key")

            if parsed.skip_existing && isfile(out_csv)
                println("  Skipping (exists): $out_csv")
                skipped += 1
                continue
            end

            if parsed.dry_run
                println("  Would run: process_with_provider($(provider), $(dataset); download=true)")
                ran += 1
                continue
            end

            try
                process_with_provider(provider, dataset;
                    download=true, data_root=parsed.data_root)
                ran += 1
            catch err
                println(stderr, "  FAILED: $key")
                showerror(stderr, err, catch_backtrace())
                println(stderr)
                push!(failed, key)
            end
        end

        println()
        println("Done. Processed=$ran  Skipped=$skipped  Failed=$(length(failed))")
        if !isempty(failed)
            println(stderr, "Failed datasets:")
            for k in failed
                println(stderr, "  - $k")
            end
            exit(1)
        end
    catch e
        if e isa ArgumentError
            println(stderr, "Error: ", e.msg)
            print_fetch_usage()
            exit(1)
        else
            rethrow()
        end
    end
end
