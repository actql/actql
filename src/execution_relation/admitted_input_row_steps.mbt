///|
/// Reuse the same bounded field recheck and row charge as retained outputs.
/// Only the existing supplied-input buffer changes: no completed-output or
/// Source evidence is created by assembling already admitted response rows.
pub fn start_admitted_input_row(
  input : AdmittedInput,
  max_workspace_slots : Int,
  read : (Int) -> @admitted.Value?,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  start_admitted_buffer_row_state(
    input.buffer,
    max_workspace_slots,
    column => read(column).map(value => Present(value)),
    false,
  )
}

///|
pub fn advance_admitted_input_row(
  row : AdmittedOutputRowCursor,
) -> Result[Bool, AdmittedOutputRowIssue] {
  advance_admitted_output_row(row)
}

///|
pub fn start_admitted_presence_input_row(
  input : AdmittedInput,
  max_workspace_slots : Int,
  read : (Int) -> RelationCell?,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  start_admitted_buffer_row_state(input.buffer, max_workspace_slots, read, true)
}

///|
pub fn prepare_bounded_admitted_input(
  owner : @lower.BoundPrepared,
  input_index : Int,
  max_rows : Int,
  limits : ValueLimits,
) -> Result[AdmittedInput, CaptureIssue] {
  prepare_admitted_input(owner, input_index, max_rows, limits).map(input => {
    input.buffer.deferred_reclamation = true
    input
  })
}

///|
pub fn cleanup_admitted_input_row(row : AdmittedOutputRowCursor) -> Bool {
  cleanup_admitted_output_row(row)
}

///|
pub fn admitted_input_work(input : AdmittedInput) -> Int {
  input.buffer.budget.work
}

///|
/// Request preparation, key comparison and cursor advancement consume the
/// same allowance as row admission, without charging row values twice.
pub fn charge_admitted_input_external_work(
  input : AdmittedInput,
  units : Int,
) -> Bool {
  charge_external_value_work(input.buffer.budget, units)
}

///|
/// A stopped acquisition assembly retains its existing buffer until sliced
/// reclamation completes. The caller must invalidate its own supplied-read
/// liveness before reclaiming a sealed buffer; borrowed inputs are not targets.
pub fn reclaim_admitted_input(input : AdmittedInput, quantum : Int) -> Bool {
  revoke_admitted_buffer(input.buffer)
  advance_admitted_buffer_reclamation(input.buffer, quantum)
}
