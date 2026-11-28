///|
/// An already debited Task workspace on its original Resource inventory.
/// The holder can observe the same paid byte backing without acquiring it.
struct StartedTaskWorkspace {
  reservation : Reservation
  attempt_sequence : Int
}

///|
pub fn capture_started_task_workspace(
  ledger : Ledger,
  token : Reservation,
) -> StartedTaskWorkspace? {
  if started_task_workspace_current(ledger, token) {
    Some({ reservation: token, attempt_sequence: token.attempt_sequence, })
  } else {
    None
  }
}

///|
fn started_task_workspace_current(ledger : Ledger, token : Reservation) -> Bool {
  reservation_check_current(ledger, token) is Ok(_) &&
  token.serial >= 0 &&
  token.attempt_sequence > 0 &&
  !token.attempt_reserved &&
  !token.cleanup_pending &&
  token.completed_output is None &&
  (token.quantities is None || token.quantities == no_model_quantity_amounts) &&
  token.uncertain_quantities is None &&
  ledger.original_inventory is Some(inventory) &&
  !inventory.closing &&
  inventory.reservations.by_serial(token.serial) is Some(original) &&
  physical_equal(original, token)
}

///|
/// Observe only this existing consumer's handed-off lifetime. The Model may
/// have spent work/quantities or acquired further resources, so its current
/// aggregate is not the initial read snapshot. The original bootstrap, input
/// tokens and exact read reservation must still be live and unchanged, except
/// for the same producer's completed output or the same bound preparation's
/// monotone byte-only bootstrap growth. The selected Whole output can also
/// supply its own started metered workspace. These observations grant no ACK.
/// This is not a new read claim, restored Ledger or dispatch permission.
pub fn[T] funded_read_consumer_handed_off_origin(
  value : FundedReadConsumer[T],
  output_workspace? : StartedTaskWorkspace? = None,
) -> T? {
  if value.claim is Some(claim) && claim.children is Some(_) {
    return original_read_child_origin(claim, value, true, output_workspace~)
  }
  guard value.claim is Some(claim) &&
    claim.phase is ConsumerHandedOff(current) &&
    physical_equal(current, value) &&
    check_original_resources_mutable(claim.descriptor.ledger) is Ok(_) &&
    capacity_reservation_open(claim.read) &&
    capacity_reservation_open(claim.descriptor.bootstrap) &&
    original_reservation_snapshot(claim.read.reservation) == claim.read_state &&
    claim.descriptor.ledger.original_inventory is Some(inventory) &&
    original_tokens_match(
      claim.descriptor,
      completed_outputs=true,
      // Only this already-handed-off original may follow its adopted body's
      // publication grow. Standalone/unbound/retiring censuses stay exact.
      // The existing matcher still checks the same opaque bootstrap token,
      // monotone byte extents and every other original charge/lifetime field.
      bootstrap_growth=(
          inventory.binding == PreparationBound ||
          inventory.binding == PreparationBoundSpent
        ) &&
        physical_equal(inventory.identity.ledger, claim.descriptor.ledger) &&
        physical_equal(inventory.identity.bootstrap, claim.descriptor.bootstrap) &&
        physical_equal(inventory.bootstrap, claim.descriptor.bootstrap),
      output_workspace~,
    ) else {
    return None
  }
  Some(claim.descriptor.origin)
}
