///|
// A finite writer borrowing the existing funded read, not another capacity
// owner. The owning caller funds its Writer/control/backing and retains the
// resulting bytes until Store acknowledgement or actual failed-write cleanup.
// This private representation is not a restoration or Model-send authority.
struct OriginalStateWrite[T] {
  mut claim : FundedReadClaim[T]?
  mut origin : T?
  mut writer : @encode.Writer?
  state : OriginalLedgerSnapshot
  bounds : (Int, Int, Int)
  total : Int
  mut position : Int
  mut terminal : Bool
}

///|
pub(all) enum OriginalStateWriteIssue {
  InvalidQuantum
  Original(OriginalReadIssue)
  Resource(LedgerIssue)
  Encoding
  Terminal
} derive(Eq, Debug)

///|
pub(all) enum OriginalStateWritePoll {
  StateWriteContinue(work~ : Int)
  StateWriteComplete(work~ : Int)
  StateWriteFailed(OriginalStateWriteIssue, work~ : Int)
} derive(Eq, Debug)

///|
fn original_state_write_preparation_inventory(
  identity : OriginalLedgerIdentity,
) -> Result[LedgerOriginalInventory, OriginalStateWriteIssue] {
  let ledger = identity.ledger
  guard ledger.original_inventory is Some(inventory) &&
    physical_equal(identity, inventory.identity) &&
    physical_equal(identity.bootstrap, inventory.bootstrap) else {
    return Err(Original(ForeignOrigin))
  }
  if inventory.descriptor_issued || inventory.read_claimed {
    return Err(Original(SpentClaim))
  }
  if inventory.closing ||
    !original_read_bootstrap_available(ledger, identity.bootstrap) {
    return Err(Original(ChangedOriginalState))
  }
  Ok(inventory)
}

///|
// Check the existing opaque identity before allocating a dedicated Writer.
// This synchronous, non-consuming check neither admits byte capacity nor
// issues a descriptor, read claim, restoration authority or send permission.
// Its caller still funds validation/control and the Writer through the original
// bootstrap. Preparation repeats these same lifecycle checks after allocation.
pub fn check_original_state_write_preparation(
  identity : OriginalLedgerIdentity,
) -> Result[Unit, OriginalStateWriteIssue] {
  match original_state_write_preparation_inventory(identity) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(())
  }
}

///|
// Private integration candidate: the existing original Run owns bootstrap,
// census and this dedicated Writer before calling. Its complete reviewed
// envelope pays for validation, snapshots, control/backing and overlap first.
// No normal physical coefficient or public Model caller is adopted here.
// Charge codec blocks BEFORE capturing the immutable original descriptor/read
// state; no caller aggregate or prepayment Bool authorizes a Writer.
pub fn[T] prepare_original_state_write(
  identity : OriginalLedgerIdentity,
  origin : T,
  writer : @encode.Writer,
  retained_bytes : Int64,
  execution_bytes : Int64,
  binding_work? : Int = 0,
) -> Result[
  (FundedReadClaim[T], OriginalStateWrite[T]),
  OriginalStateWriteIssue,
] {
  let ledger = identity.ledger
  let inventory = match original_state_write_preparation_inventory(identity) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if retained_bytes <= 0L || execution_bytes <= 0L {
    return Err(Resource(InvalidCharge))
  }
  let n = inventory.reservations.length()
  let h = inventory.holdings.length()
  let d = inventory.delegations.length()
  if n >= inventory.max_reservations ||
    h > inventory.max_holdings ||
    d > inventory.max_delegations {
    return Err(Original(IncompleteInventory))
  }
  // Seventeen fixed blocks, each original token, and the funded read token
  // (one of the fixed blocks). Integer strings are at most twenty characters.
  // Admission pays all blocks before encoding so the saved planning total is
  // final, and cancellation/encoding failure never refunds consumed work.
  if n > 2147483630 || h > 2147483630 - n || d > 2147483630 - n - h {
    return Err(Original(IncompleteInventory))
  }
  let total = 17 + n + h + d
  if binding_work < 0 || binding_work > 2147483647 - total {
    return Err(Resource(InvalidCharge))
  }
  match charge_planning(ledger, total + binding_work) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // Subsequent admission failure never refunds planning. The original Run
  // still owns bootstrap/census and the supplied Writer; no read is concealed
  // in an error. A successful descriptor remains one-shot on a later refusal.
  let descriptor = match
    issue_recorded_original_ledger_descriptor(identity, origin) {
    Err(issue) => return Err(Original(issue))
    Ok(value) => value
  }
  let claim = match
    fund_original_read(
      ledger, origin, descriptor, retained_bytes, execution_bytes,
    ) {
    Err(issue) => return Err(Original(issue))
    Ok(value) => value
  }
  let value : OriginalStateWrite[T] = {
    claim: Some(claim),
    origin: Some(origin),
    writer: Some(writer),
    state: claim.admitted,
    bounds: (
      inventory.max_reservations,
      inventory.max_holdings,
      inventory.max_delegations,
    ),
    total,
    position: 0,
    terminal: false,
  }
  claim.phase = Writing(value)
  Ok((claim, value))
}

///|
fn state_write_int(
  writer : @encode.Writer,
  value : Int,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(writer, value.to_string())
}

///|
fn state_write_long(
  writer : @encode.Writer,
  value : Int64,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(writer, value.to_string())
}

///|
fn state_write_optional_int(
  writer : @encode.Writer,
  value : Int?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(value) => state_write_int(writer, value)
    None => @encode.null_value(writer)
  }
}

///|
fn state_write_limits(
  writer : @encode.Writer,
  value : LedgerLimits,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  state_write_int(writer, value.planning_work)
  state_write_int(writer, value.attempts)
  state_write_int(writer, value.holdings)
  state_write_long(writer, value.transfer_bytes)
  state_write_long(writer, value.retained_bytes)
  state_write_long(writer, value.execution_bytes)
  @encode.end_array(writer)
}

///|
fn state_write_usage(
  writer : @encode.Writer,
  value : LedgerUsage,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  state_write_int(writer, value.planning_work)
  state_write_int(writer, value.attempts)
  state_write_int(writer, value.holdings)
  state_write_long(writer, value.transferred_bytes)
  state_write_long(writer, value.uncertain_transfer_bytes)
  state_write_long(writer, value.reserved_transfer_bytes)
  state_write_long(writer, value.held_bytes)
  state_write_long(writer, value.reserved_retention_bytes)
  state_write_long(writer, value.reserved_execution_bytes)
  state_write_long(writer, value.peak_retention_bytes)
  state_write_int(writer, value.reserved_attempts)
  state_write_int(writer, value.live_reservations)
  state_write_int(writer, value.live_delegations)
  @encode.end_array(writer)
}

///|
fn state_write_quantities(
  writer : @encode.Writer,
  value : QuantityAmounts,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  state_write_long(writer, value.tokens)
  state_write_long(writer, value.cost_units)
  state_write_long(writer, value.duration_ms)
  @encode.end_array(writer)
}

///|
fn state_write_optional_quantities(
  writer : @encode.Writer,
  value : QuantityAmounts?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(value) => state_write_quantities(writer, value)
    None => @encode.null_value(writer)
  }
}

///|
fn state_write_reservation(
  writer : @encode.Writer,
  value : OriginalReservationSnapshot,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  state_write_int(writer, value.serial)
  state_write_long(writer, value.transfer)
  state_write_long(writer, value.retention)
  state_write_long(writer, value.execution)
  @encode.bool_value(writer, value.open)
  @encode.bool_value(writer, value.cleanup_pending)
  state_write_optional_quantities(writer, value.quantities)
  state_write_optional_quantities(writer, value.uncertain_quantities)
  let (tokens, cost, duration) = value.observed_quantities
  @encode.begin_array(writer)
  @encode.bool_value(writer, tokens)
  @encode.bool_value(writer, cost)
  @encode.bool_value(writer, duration)
  @encode.end_array(writer)
  match value.completed_output {
    None => @encode.null_value(writer)
    Some((holding, bytes, execution)) => {
      @encode.begin_array(writer)
      state_write_optional_int(writer, holding)
      state_write_long(writer, bytes)
      state_write_long(writer, execution)
      @encode.end_array(writer)
    }
  }
  @encode.bool_value(writer, value.attempt_reserved)
  @encode.bool_value(writer, value.attempt_started)
  @encode.end_array(writer)
}

///|
fn[T] original_state_write_block(
  value : OriginalStateWrite[T],
  claim : FundedReadClaim[T],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let descriptor = claim.descriptor
  let step = value.position
  let n = descriptor.reservations.length()
  let h = descriptor.holdings.length()
  let d = descriptor.delegations.length()
  let state = value.state
  match step {
    0 => {
      @encode.begin_array(writer)
      @encode.string_value(writer, "actql-original-ledger-state/0.1")
    }
    1 => state_write_limits(writer, state.limits)
    2 => state_write_usage(writer, state.usage)
    3 => {
      @encode.begin_array(writer)
      let (planning, attempts, holdings) = state.delegated
      state_write_int(writer, planning)
      state_write_int(writer, attempts)
      state_write_int(writer, holdings)
      @encode.end_array(writer)
    }
    4 => state_write_optional_quantities(writer, state.quantity_limits)
    5 => {
      @encode.begin_array(writer)
      state_write_quantities(writer, state.quantities.reserved)
      state_write_quantities(writer, state.quantities.uncertain)
      state_write_quantities(writer, state.quantities.consumed)
      @encode.end_array(writer)
    }
    6 => {
      @encode.begin_array(writer)
      state_write_optional_int(writer, state.next_capacity_serial)
      state_write_optional_int(writer, state.next_attempt_serial)
      state_write_optional_int(writer, state.next_holding_serial)
      @encode.end_array(writer)
    }
    7 => {
      @encode.begin_array(writer)
      let (reservations, holdings, delegations) = value.bounds
      state_write_int(writer, reservations)
      state_write_int(writer, holdings)
      state_write_int(writer, delegations)
      @encode.bool_value(writer, true) // descriptor issued by the census
      @encode.bool_value(writer, true) // read claim issued, not send permission
      @encode.bool_value(writer, false) // not closing; checked on every poll
      @encode.string_value(writer, "reading")
      @encode.bool_value(writer, true) // the one-shot state write was admitted
      @encode.end_array(writer)
    }
    8 => state_write_reservation(writer, descriptor.bootstrap_state)
    9 => @encode.begin_array(writer)
    _ =>
      if step < 10 + n {
        state_write_reservation(writer, descriptor.reservations[step - 10].1)
      } else if step == 10 + n {
        state_write_reservation(writer, claim.read_state)
      } else if step == 11 + n {
        @encode.end_array(writer)
      } else if step == 12 + n {
        @encode.begin_array(writer)
      } else if step < 13 + n + h {
        let (token, live) = descriptor.holdings[step - 13 - n]
        @encode.begin_array(writer)
        state_write_int(writer, token.serial)
        state_write_int(writer, token.reservation_serial)
        state_write_long(writer, token.bytes)
        @encode.bool_value(writer, live)
        @encode.end_array(writer)
      } else if step == 13 + n + h {
        @encode.end_array(writer)
      } else if step == 14 + n + h {
        @encode.begin_array(writer)
      } else if step < 15 + n + h + d {
        let (token, observed) = descriptor.delegations[step - 15 - n - h]
        @encode.begin_array(writer)
        state_write_int(writer, token.reservation.serial)
        state_write_limits(writer, token.limits)
        @encode.begin_array(writer)
        let (
          planning,
          attempts,
          holdings,
          transfer,
          uncertain,
          pending,
          reservations,
          delegations,
        ) = observed
        state_write_int(writer, planning)
        state_write_int(writer, attempts)
        state_write_int(writer, holdings)
        state_write_long(writer, transfer)
        state_write_long(writer, uncertain)
        state_write_int(writer, pending)
        state_write_int(writer, reservations)
        state_write_int(writer, delegations)
        @encode.end_array(writer)
        @encode.end_array(writer)
      } else {
        // The last two fixed blocks close delegations and the root.
        @encode.end_array(writer)
      }
  }
}

///|
fn[T] retire_original_state_write(value : OriginalStateWrite[T]) -> Unit {
  value.claim = None
  value.origin = None
  value.writer = None
  value.terminal = true
}

///|
pub fn[T] cancel_original_state_write(value : OriginalStateWrite[T]) -> Unit {
  if value.claim is Some(claim) &&
    claim.phase is Writing(current) &&
    physical_equal(current, value) {
    claim.phase = Stopping
    if value.writer is Some(writer) {
      @encode.cancel_writer(writer)
    }
  }
  retire_original_state_write(value)
  // The actual read/bootstrap custody remains with the existing Run owner.
}

///|
pub fn[T] advance_original_state_write(
  value : OriginalStateWrite[T],
  quantum : Int,
) -> OriginalStateWritePoll {
  if quantum <= 0 {
    return StateWriteFailed(InvalidQuantum, work=0)
  }
  if value.terminal {
    return StateWriteFailed(Terminal, work=0)
  }
  guard value.claim is Some(claim) &&
    value.origin is Some(origin) &&
    value.writer is Some(writer) else {
    cancel_original_state_write(value)
    return StateWriteFailed(Terminal, work=0)
  }
  if !(claim.phase is Writing(current) && physical_equal(current, value)) ||
    !funded_read_state_matches(claim, origin) ||
    claim.admitted != value.state {
    cancel_original_state_write(value)
    return StateWriteFailed(Original(ChangedOriginalState), work=0)
  }
  let mut work = 0
  while work < quantum && value.position < value.total {
    original_state_write_block(value, claim, writer) catch {
      _ => {
        cancel_original_state_write(value)
        return StateWriteFailed(Encoding, work=work + 1)
      }
    }
    value.position += 1
    work += 1
  }
  if value.position == value.total {
    // The same paid Writer completes once. The immutable admitted state is
    // untouched, and the existing one-shot consumer may now prepare/enter.
    claim.phase = Written
    retire_original_state_write(value)
    StateWriteComplete(work~)
  } else {
    StateWriteContinue(work~)
  }
}

///|
// Route the existing Owner's claim to its exact Writer, without issuing a
// second control or exposing the private origin through another wrapper.
// A foreign caller cannot cancel or advance the real Writer. The owning
// caller still funds each census validation and the complete codec overlap.
pub fn[T] advance_funded_read_state_write(
  claim : FundedReadClaim[T],
  origin : T,
  quantum : Int,
) -> OriginalStateWritePoll {
  if !physical_equal(origin, claim.descriptor.origin) {
    return StateWriteFailed(Original(ForeignOrigin), work=0)
  }
  guard claim.phase is Writing(writer) else {
    return StateWriteFailed(Terminal, work=0)
  }
  advance_original_state_write(writer, quantum)
}
