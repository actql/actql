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
