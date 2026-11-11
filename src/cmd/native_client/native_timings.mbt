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
// Differences belong to the SAME existing entered Request interval. Repeated
// getters/cached returns add zero, and a decreasing observation marks the
// existing recorder invalid instead of manufacturing a successful zero.
fn record_request_work_delta(
  before : (Int64, Int64, Int64, Int64),
  after : (Int64, Int64, Int64, Int64),
) -> Unit {
  native_timing_amount(66, after.0 - before.0)
  native_timing_amount(67, after.1 - before.1)
  native_timing_amount(68, after.2 - before.2)
  native_timing_amount(69, after.3 - before.3)
}

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

///|
// Observe only an actual existing entered frame. No diagnostic enters
// a scope or changes its primary/return/close result. Keep scalar counters only;
// the returned census alias retires here before the caller leaves its domain.
// Slots4..8 cover the returned normal Read;14,15,60..62 cover Compute cleanup.
// SQLite is unobserved: its normal deep SQL scope is not entered just to sample.
// They report one census and the original allocator's retained peak, not actual
// requested/live-loan bytes, allocation work or a retirement acknowledgement.
fn LocalCommandPreparationOriginal::record_domain_inventory(
  self : LocalCommandPreparationOriginal,
  host : @initial_arena.InstalledArenaHost,
  domain : @initial_arena.InstalledArenaDomain,
  first_tag : Int,
) -> Bool {
  if !self.extent_diagnostics {
    return false
  }
  match host.observe_domain_inventory(domain) {
    Err(_) => {
      native_timing_count(63)
      false
    }
    Ok(value) => {
      native_timing_amount(first_tag, value.capacity_bytes)
      native_timing_amount(first_tag + 1, value.page_bytes)
      let control_tag = if first_tag == 14 { 60 } else { first_tag + 2 }
      native_timing_amount(control_tag, value.control_bytes)
      native_timing_amount(control_tag + 1, value.occupied_bytes)
      native_timing_amount(control_tag + 2, value.peak_occupied_bytes)
      true
    }
  }
}

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
// Borrow original CID DATA; the fixed C recorder validates and copies <=71
// UTF16 units. No payload allocation, authority or cleanup ACK is introduced.
fn native_acceptance_identity(
  tag : Int,
  ordinal : Int,
  identity : String,
) -> Unit {
  native_acceptance_identity_raw(tag, ordinal, identity, identity.length())
}
