///|
/// Immutable accounting DATA after every original live token has settled.
/// This is not an authenticated Journal record, a physical stop observation,
/// a replacement permission or a factory for a Ledger. The existing Host must
/// bind its saved bytes to the original Run/definition and current transaction.
struct LedgerContinuationState {
  state : OriginalLedgerSnapshot
}

///|
pub(all) enum LedgerContinuationIssue {
  InvalidRecord
  PendingOriginal
  ChangedOriginal
  ChangedLimits
  AlreadyRestored
  NotPristine
  Encoding
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
fn continuation_state_valid(state : OriginalLedgerSnapshot) -> Bool {
  let limits = state.limits
  let usage = state.usage
  // Do not add counters before bounding them: malformed saved Int64 fields
  // must not overflow while testing the exact original transfer envelope.
  if !backed_unresolved_limits_valid(limits) ||
    usage.planning_work < 0 || usage.planning_work > limits.planning_work ||
    usage.attempts < 0 || usage.attempts > limits.attempts ||
    usage.reserved_attempts != 0 || usage.holdings != 0 ||
    usage.live_reservations != 0 || usage.live_delegations != 0 ||
    usage.transferred_bytes < 0L || usage.transferred_bytes > limits.transfer_bytes ||
    usage.uncertain_transfer_bytes < 0L ||
    usage.uncertain_transfer_bytes > limits.transfer_bytes - usage.transferred_bytes ||
    usage.reserved_transfer_bytes != 0L || usage.held_bytes != 0L ||
    usage.reserved_retention_bytes != 0L || usage.reserved_execution_bytes != 0L ||
    usage.peak_retention_bytes < 0L || usage.peak_retention_bytes > limits.retained_bytes ||
    state.delegated != (0, 0, 0) ||
    !valid_quantities(state.quantities.reserved) ||
    state.quantities.reserved != zero_quantities() ||
    !valid_quantities(state.quantities.uncertain) ||
    !valid_quantities(state.quantities.consumed) {
    return false
  }
  if state.next_capacity_serial is Some(value) && value > -1 {
    return false
  }
  if state.next_attempt_serial is Some(value) &&
    (value < 0 || value < usage.attempts) {
    return false
  }
  if state.next_holding_serial is Some(value) && value < 0 {
    return false
  }
  match state.quantity_limits {
    None => state.quantities.uncertain == zero_quantities() &&
      state.quantities.consumed == zero_quantities()
    // Actual observed quantity overruns remain debt. Do not clamp them to the
    // configured limit or make a saved overrun admit another physical attempt.
    Some(limits) => valid_quantities(limits)
  }
}

///|
fn continuation_quiescent(ledger : Ledger) -> Bool {
  let usage = ledger.usage
  usage.reserved_attempts == 0 && usage.holdings == 0 &&
  usage.live_reservations == 0 && usage.live_delegations == 0 &&
  usage.reserved_transfer_bytes == 0L && usage.held_bytes == 0L &&
  usage.reserved_retention_bytes == 0L && usage.reserved_execution_bytes == 0L &&
  ledger.delegated_planning == 0 && ledger.delegated_attempts == 0 &&
  ledger.delegated_holdings == 0 &&
  ledger.quantity_usage.reserved == zero_quantities()
}

///|
/// Capture after the existing owner has retired its actual children, before
/// retiring this parent. Unknown cumulative transfer/quantity debt is retained;
/// no pending live token can be converted into a zero-current snapshot.
/// The caller funds this fixed DATA control and its later Writer/read overlap.
pub fn capture_quiescent_ledger_state(
  ledger : Ledger,
) -> Result[LedgerContinuationState, LedgerContinuationIssue] {
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !continuation_quiescent(ledger) {
    return Err(PendingOriginal)
  }
  let state = original_ledger_snapshot(ledger)
  if !continuation_state_valid(state) {
    return Err(InvalidRecord)
  }
  Ok({ state, })
}

///|
/// A snapshot is historical DATA, not a fence. The same live holder must
/// prevent new work and check this exact state at its Journal commit boundary.
pub fn check_ledger_continuation_current(
  ledger : Ledger,
  saved : LedgerContinuationState,
) -> Result[Unit, LedgerContinuationIssue] {
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !continuation_quiescent(ledger) || original_ledger_snapshot(ledger) != saved.state {
    return Err(ChangedOriginal)
  }
  Ok(())
}

///|
/// Fixed private accounting codec using the existing original-state field
/// readers. Its input tree is already admitted/funded by the actual caller.
/// Successful decoding supplies no authentication, currentness or capacity.
pub fn admit_quiescent_ledger_state(
  source : @decode.Cursor,
) -> Result[LedgerContinuationState, LedgerContinuationIssue] {
  let state = (fn() -> OriginalLedgerSnapshot raise OriginalStateDocumentFailure {
    document_array(source, 7)
    if @decode.text(document_at(source, 0)) != Ok("actql-ledger-continuation/0.1") {
      raise BadDocument
    }
    let quantities = document_at(source, 4)
    document_array(quantities, 3)
    let cursors = document_at(source, 5)
    document_array(cursors, 3)
    let delegated = document_at(source, 6)
    document_array(delegated, 3)
    OriginalLedgerSnapshot::{
      limits: document_limits(document_at(source, 1)),
      usage: document_usage(document_at(source, 2)),
      quantity_limits: document_optional_quantities(document_at(source, 3)),
      quantities: {
        reserved: document_quantities(document_at(quantities, 0)),
        uncertain: document_quantities(document_at(quantities, 1)),
        consumed: document_quantities(document_at(quantities, 2)),
      },
      next_capacity_serial: document_optional_int(document_at(cursors, 0)),
      next_attempt_serial: document_optional_int(document_at(cursors, 1)),
      next_holding_serial: document_optional_int(document_at(cursors, 2)),
      delegated: (
        document_count(document_at(delegated, 0)),
        document_count(document_at(delegated, 1)),
        document_count(document_at(delegated, 2)),
      ),
    }
  })() catch {
    _ => return Err(InvalidRecord)
  }
  if !continuation_state_valid(state) {
    return Err(InvalidRecord)
  }
  Ok({ state, })
}

///|
/// Emit into the existing caller's funded bounded Writer. Integer strings
/// preserve every Int64 and exhausted serial cursor without Double conversion.
pub fn write_ledger_continuation_state(
  saved : LedgerContinuationState,
  writer : @encode.Writer,
) -> Result[Unit, LedgerContinuationIssue] {
  let state = saved.state
  try {
    @encode.begin_array(writer)
    @encode.string_value(writer, "actql-ledger-continuation/0.1")
    state_write_limits(writer, state.limits)
    state_write_usage(writer, state.usage)
    state_write_optional_quantities(writer, state.quantity_limits)
    @encode.begin_array(writer)
    state_write_quantities(writer, state.quantities.reserved)
    state_write_quantities(writer, state.quantities.uncertain)
    state_write_quantities(writer, state.quantities.consumed)
    @encode.end_array(writer)
    @encode.begin_array(writer)
    state_write_optional_int(writer, state.next_capacity_serial)
    state_write_optional_int(writer, state.next_attempt_serial)
    state_write_optional_int(writer, state.next_holding_serial)
    @encode.end_array(writer)
    @encode.begin_array(writer)
    state_write_int(writer, state.delegated.0)
    state_write_int(writer, state.delegated.1)
    state_write_int(writer, state.delegated.2)
    @encode.end_array(writer)
    @encode.end_array(writer)
    Ok(())
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Initialize ONE pristine, separately admitted original Ledger. This does not
/// create a parent, authenticate saved bytes or recreate live resource tokens.
/// The trusted Host must bind the saved state to its same request/definition
/// and checked plan before it calls this typed entry or any provider code.
pub fn restore_quiescent_ledger_state(
  ledger : Ledger,
  saved : LedgerContinuationState,
) -> Result[Unit, LedgerContinuationIssue] {
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if ledger.continuation_restored {
    return Err(AlreadyRestored)
  }
  if ledger.limits != saved.state.limits {
    return Err(ChangedLimits)
  }
  let zero = zero_quantities()
  if !continuation_quiescent(ledger) || ledger.original_inventory is Some(_) ||
    ledger.next_attempt_serial != Some(0) || ledger.next_holding_serial != Some(0) ||
    ledger.next_capacity_serial != Some(-1) || ledger.quantity_limits is Some(_) ||
    ledger.quantity_usage.uncertain != zero || ledger.quantity_usage.consumed != zero ||
    ledger.usage.planning_work != 0 || ledger.usage.attempts != 0 ||
    ledger.usage.transferred_bytes != 0L || ledger.usage.uncertain_transfer_bytes != 0L ||
    ledger.usage.peak_retention_bytes != 0L {
    return Err(NotPristine)
  }
  // No callback or await between the final pristine check and atomic seeding.
  // Keeping the cursors includes identities issued and settled with zero work.
  ledger.continuation_restored = true
  let state = saved.state
  ledger.usage = state.usage
  ledger.next_capacity_serial = state.next_capacity_serial
  ledger.next_attempt_serial = state.next_attempt_serial
  ledger.next_holding_serial = state.next_holding_serial
  ledger.quantity_limits = state.quantity_limits
  ledger.quantity_usage = state.quantities
  Ok(())
}
