#=
Download (or take --source=) one provider/dataset, convert, and index it.

  julia --project=. bin/process.jl konect/bitcoin --download
  julia --project=. bin/process.jl amazon/boxes --source=path/to/Subscription_Boxes.jsonl
  julia --project=. bin/process.jl --help
=#
using GraphLogic
process_main(ARGS)
