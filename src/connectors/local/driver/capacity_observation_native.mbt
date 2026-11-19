///|
// Optional diagnostic sink only. The Core stub has no filesystem dependency.
#borrow(ledger)
extern "C" fn capacity_observation(
  ledger : @resources.Ledger,
  kind : Int,
  serial : Int,
  requested : Int64,
  capacity : Int64,
  limit : Int64,
  reserved : Int64,
) -> Unit = "actql_resource_capacity_observation"
