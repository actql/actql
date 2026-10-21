///|
// Optional process diagnostics only. These calls never acknowledge cleanup,
// authorize work or change the command's result. The Native foundation owns
// bounded recording and best-effort stderr emission when explicitly enabled.
extern "C" fn native_timing_begin(tag : Int) -> Unit = "actql_native_timing_begin"

///|
extern "C" fn native_timing_end(tag : Int) -> Unit = "actql_native_timing_end"

///|
extern "C" fn native_timing_count(tag : Int) -> Unit = "actql_native_timing_count"

///|
extern "C" fn native_timing_amount(tag : Int, amount : Int64) -> Unit = "actql_native_timing_amount"

///|
// Observe only an already-entered original backing loan. Diagnostics never
// acquire another loan, change a command failure or supply capacity/close ACK.
fn LocalCommandPreparationOriginal::observe_extent_work(
  self : LocalCommandPreparationOriginal,
  host : @initial_arena.InstalledArenaHost,
  scope : @initial_arena.InstalledArenaBackingBorrow,
) -> @initial_bootstrap.NativeExtentWork? {
  if !self.extent_diagnostics {
    return None
  }
  match host.observe_backing_extent_work(scope) {
    Ok(value) => Some(value)
    Err(_) => {
      native_timing_count(52)
      None
    }
  }
}

///|
// These deltas cover physical facility construction only. Nested allocator
// work, later use and the OS's initial anonymous zero supply are separate.
fn record_command_extent_work(
  before : @initial_bootstrap.NativeExtentWork?,
  after : @initial_bootstrap.NativeExtentWork?,
  first_tag : Int,
) -> Unit {
  guard before is Some(before) && after is Some(after) else { return }
  if after.allocations < before.allocations ||
    after.allocated_bytes < before.allocated_bytes ||
    after.zeroed_bytes < before.zeroed_bytes {
    native_timing_count(52)
    return
  }
  native_timing_amount(
    first_tag,
    after.allocated_bytes - before.allocated_bytes,
  )
  native_timing_amount(first_tag + 1, after.zeroed_bytes - before.zeroed_bytes)
  native_timing_amount(first_tag + 2, after.allocations - before.allocations)
}
