#=
Fetch every dataset listed in a manifest (default data/datasets.txt).

  julia --project=. bin/fetch_datasets.jl --skip-existing
  julia --project=. bin/fetch_datasets.jl my_datasets.txt --prefix=konect-small
  julia --project=. bin/fetch_datasets.jl --help
=#
using GraphLogic
fetch_main(ARGS)
