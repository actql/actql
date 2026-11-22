///|
/// The matched Host has consumed the projection and returned all byte
/// aliases. Drop the wire and reconcile its two copy pairs. The original
/// slot, physical callback and the remainder of its copy quote stay owned
/// until ordinary close. A refusal keeps this same slot for cleanup.
pub fn retire_consumed_output_transport(
  pool : BufferPool,
  slot : BufferSlot,
) -> Result[Unit, BufferIssue] {
  if !physical_equal(pool, slot.owner) {
    return Err(ForeignOwner)
  }
  guard pool_uses_vm_capacity(pool) &&
    !pool.closing &&
    slot.published &&
    slot.output_only &&
    slot.input_complete &&
    !slot.retired &&
    !slot.cleaned &&
    slot.wire is Some(_) &&
    slot.allocation is Some(allocation) &&
    slot.copy_capacity is Some(copy) else {
    return Err(Closed)
  }
  let vm = @resources.shared_allocation_usage(allocation)
  if vm.readers != 0 {
    return Err(CleanupPending)
  }
  let transfer = 2L * slot.wire_length.to_int64()
  let physical = @resources.shared_capacity_usage(copy).capacity
  if transfer <= 0L ||
    vm.bytes != transfer ||
    physical <= transfer ||
    slot.accounted_bytes != transfer + physical {
    return Err(InvalidLimits)
  }
  // input_complete stays set to prevent ever writing another output. No
  // physical cleanup callback or success receipt is issued here.
  slot.wire = None
  match
    @resources.reconcile_unborrowed_shared_allocation_after_cleanup(
      pool.capacity,
      allocation,
      transfer,
      0L,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  slot.accounted_bytes -= transfer
  pool.allocated_bytes -= transfer
  match
    @resources.reconcile_idle_shared_capacity_after_cleanup(
      copy,
      physical,
      physical - transfer,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  slot.accounted_bytes -= transfer
  pool.allocated_bytes -= transfer
  pool.copy_reserved_bytes -= transfer
  Ok(())
}
