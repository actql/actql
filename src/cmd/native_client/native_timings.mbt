///|
// Optional process diagnostics only. These calls never acknowledge cleanup,
// authorize work or change the command's result. The Native foundation owns
// bounded recording and best-effort stderr emission when explicitly enabled.
extern "C" fn native_timing_begin(tag : Int) -> Unit = "actql_native_timing_begin"

///|
extern "C" fn native_timing_end(tag : Int) -> Unit = "actql_native_timing_end"

///|
extern "C" fn native_timing_count(tag : Int) -> Unit = "actql_native_timing_count"
