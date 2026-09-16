///|
struct ObligationRetention {
  ledger : @resources.Ledger
  outputs : Array[ObligationOutputReservation]
  mut closed : Bool
}

///|
struct ObligationOutputReservation {
  owner : ObligationRetention
  reservation : @resources.Reservation
  metadata : Int
  mut holding : @resources.Holding?
}

///|
suberror RetentionFailure {
  State
  Capacity(@resources.LedgerIssue)
}

///|
#export_name("obligationRetention")
pub fn obligation_retention(
  bytes : Int64,
) -> ObligationRetention raise RetentionFailure {
  match
    @resources.create_ledger({
      planning_work: 0,
      attempts: 16,
      holdings: 16,
      transfer_bytes: 0L,
      retained_bytes: bytes,
      execution_bytes: 0L,
    }) {
    Ok(ledger) => { ledger, outputs: [], closed: false, }
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("obligationReserveOutput")
pub fn obligation_reserve_output(
  owner : ObligationRetention,
  file_bytes : Int,
  metadata : Int,
) -> ObligationOutputReservation raise RetentionFailure {
  if owner.closed || file_bytes < 0 || metadata < 0 {
    raise State
  }
  let reservation = match
    @resources.reserve_attempt(
      owner.ledger,
      0L,
      file_bytes.to_int64() + metadata.to_int64(),
      0L,
    ) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
  let output = { owner, reservation, metadata, holding: None, }
  owner.outputs.push(output)
  output
}

///|
#export_name("obligationHoldOutput")
pub fn obligation_hold_output(
  output : ObligationOutputReservation,
  file_bytes : Int,
) -> Unit raise RetentionFailure {
  if output.owner.closed || output.holding is Some(_) || file_bytes < 0 {
    raise State
  }
  match
    @resources.retain_allocation(
      output.owner.ledger,
      output.reservation,
      file_bytes.to_int64() + output.metadata.to_int64(),
    ) {
    Ok(holding) => output.holding = Some(holding)
    Err(issue) => raise Capacity(issue)
  }
  @resources.settle_reservation(output.owner.ledger, output.reservation).unwrap()
}

///|
#export_name("obligationRetentionUsage")
pub fn obligation_retention_usage(
  owner : ObligationRetention,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(owner.ledger)
}

///|
/// Trusted independent assembly calls only after Store teardown is confirmed.
#export_name("obligationRetentionReleased")
pub fn obligation_retention_released(
  owner : ObligationRetention,
) -> Unit raise RetentionFailure {
  if owner.closed {
    raise State
  }
  for output in owner.outputs {
    if output.holding is Some(holding) {
      @resources.release_allocation(owner.ledger, holding).unwrap()
    } else {
      @resources.settle_reservation(owner.ledger, output.reservation).unwrap()
    }
  }
  owner.outputs.clear()
  owner.closed = true
}
