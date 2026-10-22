///|
// Diagnostics remain separate from currentness, physical return and durable
// acknowledgment. Counts describe these selected Native call sites only.
extern "C" fn native_timing_begin(tag : Int) -> Unit = "actql_native_timing_begin"

///|
extern "C" fn native_timing_end(tag : Int) -> Unit = "actql_native_timing_end"

///|
extern "C" fn native_timing_count(tag : Int) -> Unit = "actql_native_timing_count"
