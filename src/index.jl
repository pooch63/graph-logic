#=
=================================================================================
CSV ID indexer
=================================================================================
Takes a CSV with columns `u,v[,...]` and converts the endpoint IDs into a
continuous, 1-based integer index format.

It outputs:
  1. A processed CSV file with columns: u, v (integer indices).
  2. A folder containing 'user_mapping.csv' and 'item_mapping.csv'.
  3. A 'metadata.txt' file with unique-user / unique-item counts.
=#

"""
    index_dataset(input_csv, output_csv, mapping_dir) -> DataFrame

Remap `u` / `v` ids in `input_csv` to `1:n` and write the indexed graph plus
reverse mappings under `mapping_dir`.
"""
function index_dataset(input_path::AbstractString, output_csv_path::AbstractString, mapping_dir::AbstractString)
    if !isfile(input_path)
        error("Input file '$input_path' does not exist.")
    end

    println("Loading dataset...")
    df = CSV.read(input_path, DataFrame)

    required_cols = ["u", "v"]
    if !all(col -> col in names(df), required_cols)
        error("Input CSV must contain 'u' and 'v' columns.")
    end

    println("Processing user mappings...")
    unique_users = unique(df.u)
    user_to_idx = Dict(user => i for (i, user) in enumerate(unique_users))

    println("Processing item mappings...")
    unique_items = unique(df.v)
    item_to_idx = Dict(item => i for (i, item) in enumerate(unique_items))

    println("Transforming dataset...")
    transformed_df = DataFrame(
        u = [user_to_idx[u] for u in df.u],
        v = [item_to_idx[i] for i in df.v],
    )

    if !isdir(mapping_dir)
        mkpath(mapping_dir)
    end

    println("Saving processed dataset...")
    CSV.write(output_csv_path, transformed_df)

    println("Saving reverse mapping files...")
    user_mapping_df = DataFrame(index = 1:length(unique_users), user_id = unique_users)
    item_mapping_df = DataFrame(index = 1:length(unique_items), item_id = unique_items)

    CSV.write(joinpath(mapping_dir, "user_mapping.csv"), user_mapping_df)
    CSV.write(joinpath(mapping_dir, "item_mapping.csv"), item_mapping_df)

    println("Saving metadata...")
    open(joinpath(mapping_dir, "metadata.txt"), "w") do f
        write(f, "Dataset Transformation Metadata\n")
        write(f, "=================================\n")
        write(f, "Total Unique Users: $(length(unique_users))\n")
        write(f, "Total Unique Items: $(length(unique_items))\n")
    end

    println("\nSuccess! Transformation complete.")
    println("Indexed dataset written to: $output_csv_path")
    println("Mappings folder populated:  $mapping_dir")

    return transformed_df
end

