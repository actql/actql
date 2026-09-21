///|
extern "C" fn physical_reconciliation_wait_ffi(milliseconds : Int) -> Unit = "actql_native_remote_transfer_reconciliation_wait"

///|
fn physical_reconciliation_wait(milliseconds : Int) -> Unit {
  physical_reconciliation_wait_ffi(milliseconds)
}
