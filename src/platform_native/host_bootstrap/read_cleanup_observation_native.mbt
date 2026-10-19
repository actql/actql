///|
/// Pure physical metadata, never available capacity, permission or a cleanup
/// acknowledgement. Managed slot bytes are contained in managed page bytes.
pub(all) struct NativeReadCleanupObservation {
  users : Int64
  active : Int64
  generic_live_extents : Int64
  generic_live_pages : Int64
  managed_live_pages : Int64
  managed_live_blocks : Int64
  managed_requested_bytes : Int64
  managed_payload_capacity_bytes : Int64
  pending_extents : Int64
  pending_pages : Int64
  minimum_managed_request : Int64
  maximum_managed_request : Int64
  closing : Bool
  calling_thread_read : Bool
  calling_thread_owned : Bool
  context_payload_bytes : Int64
}

///|
#borrow(domain, output)
extern "C" fn read_cleanup_snapshot_ffi(
  domain : PhysicalExtentDomain,
  output : FixedArray[Int64],
  count : Int,
) -> Int = "actql_bootstrap_read_cleanup_snapshot"

///|
extern "C" fn cleanup_observation_control_clear_ffi() -> Int = "actql_bootstrap_control_scope_clear"

///|
/// The trusted caller covers this fixed output/copy in its existing initial
/// control before use. No child scope is entered to produce the observation.
/// Original identity remains required after normal currentness has stopped.
pub fn[T, C] NativeHostBootstrap::observe_backed_read_cleanup(
  self : NativeHostBootstrap[T],
  original : T,
  domain : NativeBackedExecutionDomain[T, C],
  child : C,
) -> Result[NativeReadCleanupObservation, NativeBackedExecutionIssue] {
  match self.original_read_carrier(original, domain, child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !domain.read_attempted || domain.read_retired {
    return Err(Bootstrap(Unavailable))
  }
  if cleanup_observation_control_clear_ffi() != 1 {
    return Err(Bootstrap(ReadersPending))
  }
  let values = FixedArray::make(16, 0L)
  let code = read_cleanup_snapshot_ffi(domain.physical, values, 16)
  if code != 0 {
    return Err(Bootstrap(Physical(code)))
  }
  Ok({
    users: values[0],
    active: values[1],
    generic_live_extents: values[2],
    generic_live_pages: values[3],
    managed_live_pages: values[4],
    managed_live_blocks: values[5],
    managed_requested_bytes: values[6],
    managed_payload_capacity_bytes: values[7],
    pending_extents: values[8],
    pending_pages: values[9],
    minimum_managed_request: values[10],
    maximum_managed_request: values[11],
    closing: values[12] == 1L,
    calling_thread_read: values[13] == 1L,
    calling_thread_owned: values[14] == 1L,
    context_payload_bytes: values[15],
  })
}

///|
extern "C" fn managed_value_layout_ffi(field : Int) -> Int64 = "actql_bootstrap_managed_value_layout"

///|
/// Exact public header sizes for the selected runtime: object header, UTF16
/// unit and String terminator, reference-containing value-array header, pointer.
/// Array wrapper/element lowering and the whole live envelope stay separate.
pub fn native_managed_value_layout() -> (Int64, Int64, Int64, Int64, Int64) {
  (
    managed_value_layout_ffi(0),
    managed_value_layout_ffi(1),
    managed_value_layout_ffi(2),
    managed_value_layout_ffi(3),
    managed_value_layout_ffi(4),
  )
}
