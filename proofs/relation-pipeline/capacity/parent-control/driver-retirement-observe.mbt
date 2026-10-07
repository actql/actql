///|
#borrow(root)
extern "C" fn driver_retirement_probe(
  root : Ref[@local.ManagedProviderExecution?],
  task : Int,
  phase : Int,
) -> String = "actql_proof_driver_retirement"
