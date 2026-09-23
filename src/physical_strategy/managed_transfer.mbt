///|
/// One explicit physical transfer owned by the captured Run. It is not a
/// language task, a consumer completion, or a content identity. The existing
/// Run ledger remains authoritative for its cumulative bytes, destination
/// retention, temporary execution capacity, and cleanup responsibility.
struct ManagedTransfer {
  owner : CapturedDAG
  source_task : Int
  reservation : @resources.Reservation
  mut transferred_bytes : Int64
  mut settled : Bool
  mut completed : Bool
  mut holding : @resources.Holding?
  mut released : Bool
}

///|
/// Common accounting receipt for a successfully retained destination
/// generation. Site and material generations stay in the Host-owned typed
/// transfer record; this receipt proves only the exact Run reservation and
/// source occurrence that paid for it.
struct ManagedTransferReceipt {
  owner : CapturedDAG
  source_task : Int
  attempt : Int
  transferred_bytes : Int64
  retained_bytes : Int64
  transfer : ManagedTransfer
}

///|
/// Admit a transfer only from a live completed managed producer. Existing
/// source holding is deliberately not reserved again. The destination holding
/// and temporary workspace are new physical resources and receive their own
/// reservation before any representation access starts.
pub fn begin_captured_managed_transfer(
  run : CapturedDAG,
  source_task : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[ManagedTransfer, RunIssue] {
  if run.stopped ||
    transfer_bytes < 0L ||
    retained_bytes < 0L ||
    execution_bytes < 0L {
    return Err(if run.stopped { Stopped } else { Physical(InvalidLimits) })
  }
  guard source_task >= captured_compute_first_task(run) &&
    run.done.get(source_task) == Some(true) &&
    run.lifetimes.get(source_task) is Some(lifetime) &&
    lifetime.live &&
    managed_task_output_reference(run, source_task) is Some(reference) &&
    @execution.managed_completed_reference_available(reference) else {
    return Err(MissingOutput)
  }
  let reservation = match
    @resources.reserve_attempt(
      run.ledger,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  Ok({
    owner: run,
    source_task,
    reservation,
    transferred_bytes: 0L,
    settled: false,
    completed: false,
    holding: None,
    released: false,
  })
}

///|
/// Charge bytes before admitting the corresponding destination batch. Spent
/// transfer is cumulative and is never refunded by cancellation or cleanup.
pub fn charge_captured_managed_transfer(
  run : CapturedDAG,
  transfer : ManagedTransfer,
  bytes : Int64,
) -> Result[Unit, @resources.LedgerIssue] {
  if !physical_equal(run, transfer.owner) ||
    transfer.completed ||
    transfer.settled {
    return Err(ForeignOwner)
  }
  match @resources.charge_transfer(run.ledger, transfer.reservation, bytes) {
    Err(issue) => Err(issue)
    Ok(_) => {
      transfer.transferred_bytes += bytes
      Ok(())
    }
  }
}

///|
/// Confirm actual source and destination operation stop. A cancellation request
/// or an outer Promise returning is not confirmation. False preserves the
/// reservation as an explicit cleanup responsibility.
pub fn settle_captured_managed_transfer(
  run : CapturedDAG,
  transfer : ManagedTransfer,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  if !physical_equal(run, transfer.owner) || transfer.completed {
    return Err(ForeignOwner)
  }
  if transfer.settled {
    return Ok(())
  }
  if !confirmed {
    return @resources.mark_cleanup_pending(run.ledger, transfer.reservation)
  }
  match
    @resources.settle_execution_reservation(
      run.ledger,
      transfer.reservation,
      remaining_execution=0L,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      transfer.settled = true
      Ok(())
    }
  }
}

///|
/// Commit one independently owned destination allocation only after transfer
/// stop and destination verification. The receipt does not complete a consumer
/// task and does not make a logical CID claim.
pub fn complete_captured_managed_transfer(
  run : CapturedDAG,
  transfer : ManagedTransfer,
  retained_bytes : Int64,
) -> Result[ManagedTransferReceipt, RunIssue] {
  if !physical_equal(run, transfer.owner) ||
    !transfer.settled ||
    transfer.completed ||
    transfer.released {
    return Err(NotReady)
  }
  guard managed_task_output_reference(run, transfer.source_task)
    is Some(reference) &&
    @execution.managed_completed_reference_available(reference) else {
    return Err(MissingOutput)
  }
  let holding = match
    @resources.retain_allocation(
      run.ledger,
      transfer.reservation,
      retained_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match @resources.settle_reservation(run.ledger, transfer.reservation) {
    Err(issue) => {
      @resources.release_allocation(run.ledger, holding) |> ignore
      return Err(Physical(issue))
    }
    Ok(_) => ()
  }
  transfer.holding = Some(holding)
  transfer.completed = true
  Ok({
    owner: run,
    source_task: transfer.source_task,
    attempt: @resources.reservation_serial(transfer.reservation),
    transferred_bytes: transfer.transferred_bytes,
    retained_bytes,
    transfer,
  })
}

///|
/// Abandon a transfer before commit. Destination cleanup must finish before
/// confirmed=true. Destination cleanup that no longer accesses the source is
/// independent from the source pin and can be retried without retaining it.
pub fn abort_captured_managed_transfer(
  run : CapturedDAG,
  transfer : ManagedTransfer,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  if !physical_equal(run, transfer.owner) || transfer.completed {
    return Err(ForeignOwner)
  }
  if !confirmed {
    return @resources.mark_cleanup_pending(run.ledger, transfer.reservation)
  }
  transfer.settled = true
  @resources.settle_reservation(run.ledger, transfer.reservation)
}

///|
/// Release only the destination holding owned by this successful transfer.
/// The source task holding and every consumer's admission remain independent.
pub fn release_captured_managed_transfer(
  run : CapturedDAG,
  receipt : ManagedTransferReceipt,
) -> Result[Bool, @resources.LedgerIssue] {
  let transfer = receipt.transfer
  if !physical_equal(run, receipt.owner) ||
    !physical_equal(run, transfer.owner) ||
    !transfer.completed {
    return Err(ForeignOwner)
  }
  if transfer.released {
    return Ok(false)
  }
  guard transfer.holding is Some(holding) else { return Err(InvalidCharge) }
  match @resources.release_allocation(run.ledger, holding) {
    Err(issue) => Err(issue)
    Ok(_) => {
      transfer.released = true
      transfer.holding = None
      Ok(true)
    }
  }
}

///|
pub fn captured_managed_transfer_pending(transfer : ManagedTransfer) -> Bool {
  !transfer.completed && @resources.reservation_pending(transfer.reservation)
}

///|
pub fn captured_managed_transfer_receipt_source(
  receipt : ManagedTransferReceipt,
) -> Int {
  receipt.source_task
}

///|
pub fn captured_managed_transfer_receipt_attempt(
  receipt : ManagedTransferReceipt,
) -> Int {
  receipt.attempt
}

///|
pub fn captured_managed_transfer_receipt_bytes(
  receipt : ManagedTransferReceipt,
) -> (Int64, Int64) {
  (receipt.transferred_bytes, receipt.retained_bytes)
}

///|
pub fn captured_managed_transfer_receipt_available(
  receipt : ManagedTransferReceipt,
) -> Bool {
  !receipt.transfer.released &&
  receipt.transfer.holding is Some(holding) &&
  @resources.holding_available(receipt.owner.ledger, holding)
}

///|
/// Bind an adapter-visible receipt to the exact completed Transfer and the
/// measurements used to construct its durable Host record. The attempt number
/// is an occurrence identifier; matching byte counts do not authorize a
/// foreign receipt or a released destination holding.
pub fn captured_managed_transfer_receipt_matches(
  receipt : ManagedTransferReceipt,
  transfer : ManagedTransfer,
  source_task : Int,
  transferred_bytes : Int64,
  retained_bytes : Int64,
) -> Bool {
  physical_equal(receipt.transfer, transfer) &&
  receipt.source_task == source_task &&
  receipt.attempt > 0 &&
  receipt.transferred_bytes == transferred_bytes &&
  receipt.retained_bytes == retained_bytes &&
  captured_managed_transfer_receipt_available(receipt)
}
