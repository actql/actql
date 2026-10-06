///|
/// Delivery custody is discharged only after terminal execution and explicit
/// physical release. This is not Run cancellation confirmation: success may
/// win a cancellation race, and recovery-after-loss is not a release receipt.
fn cancellation_delivery_can_retire(
  execution : RemoteExecutionState,
  cleanup : RemoteCleanupState,
  material_available : Bool,
  quarantined_capacity : Bool,
) -> Bool {
  let terminal = match execution {
    NativeSettled | ExecutionFailed | ExecutionCancelled => true
    _ => false
  }
  terminal &&
  cleanup == CleanupReleased &&
  !material_available &&
  !quarantined_capacity
}

///|
fn cancellation_delivery_from_codes(
  execution : Int,
  cleanup : Int,
  material_available : Bool,
  quarantined_capacity : Bool,
) -> Bool {
  match
    (execution_state_from_code(execution), cleanup_state_from_code(cleanup)) {
    (Ok(execution), Ok(cleanup)) =>
      cancellation_delivery_can_retire(
        execution, cleanup, material_available, quarantined_capacity,
      )
    _ => false
  }
}

///|
/// Project an admitted response. The Host must durably admit that observation
/// before retiring its delivery waiter; an absent or lost response is no proof.
pub fn remote_dispatch_response_can_retire_cancellation_delivery(
  response : RemoteDispatchResponse,
) -> Bool {
  cancellation_delivery_from_codes(
    response.execution,
    response.cleanup,
    response.material_available,
    response.quarantined_capacity,
  )
}

///|
/// Project only the latest durably committed Coordinator observation. This
/// retires Cancel delivery custody, without changing Site or Run state.
pub fn coordinator_can_retire_cancellation_delivery(
  record : CoordinatorDispatchIntentRecord,
) -> Bool {
  record.site_revision >= 0 &&
  cancellation_delivery_from_codes(
    record.site_execution,
    record.site_cleanup,
    record.site_material_available,
    record.site_quarantined_capacity,
  )
}
