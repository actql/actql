///|
// Diagnostics remain separate from currentness, physical return and durable
// acknowledgment. Counts describe these selected Native call sites only.
extern "C" fn native_timing_begin(tag : Int) -> Unit = "actql_native_timing_begin"

///|
extern "C" fn native_timing_end(tag : Int) -> Unit = "actql_native_timing_end"

///|
extern "C" fn native_timing_count(tag : Int) -> Unit = "actql_native_timing_count"

///|
extern "C" fn native_acceptance_enabled() -> Bool = "actql_native_acceptance_enabled"

///|
#borrow(identity)
extern "C" fn native_acceptance_identity_raw(
  tag : Int,
  ordinal : Int,
  identity : String,
  length : Int,
) -> Unit = "actql_native_acceptance_identity"

///|
extern "C" fn native_acceptance_incomplete() -> Unit = "actql_native_acceptance_incomplete"

///|
// Borrow original CID DATA; the fixed C recorder validates and copies <=71
// UTF16 units. No payload allocation, authority or cleanup ACK is introduced.
fn native_acceptance_identity(
  tag : Int,
  ordinal : Int,
  identity : String,
) -> Unit {
  native_acceptance_identity_raw(tag, ordinal, identity, identity.length())
}

///|
// Read-only diagnostic snapshot; -1 is unavailable, never zero work or current.
extern "C" fn native_timing_counter_value(tag : Int) -> Int64 = "actql_native_timing_counter_value"

///|
// Lexical original File Work scope. This borrowed identity never leaves the
// private recorder, never becomes a root, and is cleared by the caller defer.
#borrow(ledger)
extern "C" fn native_file_capacity_observation(
  ledger : @resources.Ledger,
  kind : Int,
  serial : Int,
  requested : Int64,
  capacity : Int64,
  limit : Int64,
  reserved : Int64,
) -> Unit = "actql_resource_capacity_observation"
