#=
=================================================================================
Amazon Reviews 2023 provider
=================================================================================
Downloads category review JSONL from McAuley Lab and converts the JSONL (user_id→u, asin→v)
to the shared interactions CSV.

URL template:
  https://mcauleylab.ucsd.edu/public_datasets/data/amazon_2023/raw/review_categories/{NAME}.jsonl.gz

Short local keys (amazon/boxes, amazon/gift-cards, …) map to McAuley category
filenames via builtins below and optional overrides in `data/aliases.txt`
(`amazon/local=Category_Name`).

Examples:
  julia bin/process.jl amazon/boxes --download
  julia bin/process.jl amazon/gift-cards --download
  julia bin/process.jl amazon/Appliances --download
=#

const AMAZON_REVIEW_URL =
    "https://mcauleylab.ucsd.edu/public_datasets/data/amazon_2023/raw/review_categories"

"""
Short local keys → Amazon Reviews 2023 category filenames.

File overrides: `amazon/<key>=<Category>` in `data/aliases.txt`.
"""
const AMAZON_CATEGORY_ALIASES = Dict{String,String}(
    "boxes" => "Subscription_Boxes",
    "appliances" => "Appliances",
    "music" => "Digital_Music",
    "grocery" => "Grocery_and_Gourmet_Food",
    "gift-cards" => "Gift_Cards",
    "health" => "Health_and_Personal_Care",
    "software" => "Software",
    "movies" => "Movies_and_TV",
)

function amazon_category_name(dataset_name::AbstractString)
    name = String(dataset_name)
    leaf = split(replace(name, '\\' => '/'), '/')[end]
    return resolve_alias("amazon", leaf;
        builtins=AMAZON_CATEGORY_ALIASES,
        normalize=lowercase,
        fallback=leaf)
end

"""
Download `{NAME}.jsonl.gz`, unzip to `{NAME}.jsonl` under `dest_dir`, return the jsonl path.
"""
function amazon_download_raw!(dataset_name::AbstractString, dest_dir::AbstractString)
    category = amazon_category_name(dataset_name)
    leaf = split(replace(String(dataset_name), '\\' => '/'), '/')[end]
    lowercase(leaf) != lowercase(category) && println("  Amazon category: $category")

    url = "$(AMAZON_REVIEW_URL)/$(category).jsonl.gz"
    gz_path = joinpath(dest_dir, "$(category).jsonl.gz")
    jsonl_path = joinpath(dest_dir, "$(category).jsonl")

    println("  URL: $url")
    println("  Saving archive to: $gz_path")
    Downloads.download(url, gz_path)

    println("  Unzipping…")
    gunzip_file!(gz_path; dest=jsonl_path)
    println("  Raw JSONL: $jsonl_path")
    return jsonl_path
end

"""
    convert_jsonl_to_csv(input_jsonl, output_csv) -> DataFrame

Read Amazon review JSONL and write a `u,v` CSV (`user_id` → u, `asin` → v).
Rows missing either field are skipped with a warning.
"""
function convert_jsonl_to_csv(input_path::AbstractString, output_path::AbstractString)
    if !isfile(input_path)
        error("Input file '$input_path' does not exist.")
    end

    mkpath(dirname(output_path))

    println("Starting conversion...")
    println("Input source:  $input_path")
    println("Output target: $output_path")

    us = String[]
    vs = String[]

    try
        open(input_path, "r") do file
            line_count = 0
            for line in eachline(file)
                line_count += 1
                cleaned_line = strip(line)
                if !isempty(cleaned_line)
                    row = JSON3.read(cleaned_line)

                    if haskey(row, :user_id) && haskey(row, :asin)
                        push!(us, string(row[:user_id]))
                        push!(vs, string(row[:asin]))
                    else
                        println(stderr, "Warning: Skipping malformed row at line $line_count")
                    end
                end
            end
        end
    catch e
        error("An error occurred while reading the file: $e")
    end

    println("Assembling dataset...")
    df = DataFrame(u = us, v = vs)

    try
        CSV.write(output_path, df)
        println("Success! Successfully processed $(nrow(df)) entries.")
    catch e
        error("An error occurred while writing the CSV file: $e")
    end

    return df
end


function amazon_convert!(raw_path::AbstractString, interactions_csv::AbstractString)
    convert_jsonl_to_csv(String(raw_path), String(interactions_csv))
    return nothing
end

register_provider!(ProviderAdapter(
    "amazon",
    amazon_download_raw!,
    amazon_convert!,
))
