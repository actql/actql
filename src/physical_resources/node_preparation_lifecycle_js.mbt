///|
/// A Local preparation owns the selected imported child before a Prepared
/// value exists. Its factory is private until the fixed Root supplies the
/// original input-purpose ports and funds this control envelope.
struct NodePreparationAdmission[I] {
  mut admission : NodeManagedRunAdmission[I]?
  mut transitioning : Bool
}

///|
pub fn[I] start_node_preparation_admission(
  owner : NodePreparationAdmission[I],
) -> Result[Ledger, ImportedChildLedgerIssue] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  owner.transitioning = true
  let outcome = start_node_managed_run_admission(admission)
  owner.transitioning = false
  outcome
}

///|
/// Install the original census before allocating the first preparation token.
/// The fixed initial supplier funds bootstrap controls and their bounded slot
/// inventories. Starting the imported child remains the separate one-use call;
/// a failed initialization leaves its bootstrap on that same cleanup owner.
pub fn[I] begin_node_preparation_inventory(
  owner : NodePreparationAdmission[I],
  input : I,
  retained_bytes : Int64,
  execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[OriginalLedgerIdentity, ImportedChildLedgerIssue] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  match check_node_managed_run_preparation(admission, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard admission.ledger is Some(ledger) else { return Err(Unavailable) }
  owner.transitioning = true
  let outcome = match
    reserve_node_managed_run_read_bootstrap(
      admission, input, ledger, retained_bytes, execution_bytes,
    ) {
    Err(issue) => Err(issue)
    Ok(bootstrap) =>
      begin_original_ledger_inventory(
        ledger, bootstrap, max_reservations, max_holdings, max_delegations,
      ).map_err(issue => {
        match issue {
          Resource(issue) => ImportedChildLedgerIssue::Resource(issue)
          _ => Unavailable
        }
      })
  }
  owner.transitioning = false
  outcome
}

///|
/// No new child, start, take, quota or reservation is created here. The
/// completed preparation debit remains on the exact imported Ledger. The old
/// input-facing admission is consumed only after that transfer succeeds.
pub fn[I, P] adopt_node_preparation_admission(
  owner : NodePreparationAdmission[I],
  input : I,
  capacity : PreparationCapacity[I, P],
  prepared : P,
) -> Result[
  (NodeManagedRunAdmission[P], Ledger, PreparationRetirement),
  ImportedChildLedgerIssue,
] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  match check_node_managed_run_preparation(admission, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard admission.ledger is Some(ledger) else { return Err(Unavailable) }
  let child = admission.child
  if !admission.attempted ||
    admission.cleaned ||
    child.pending_report is Some(_) ||
    child.pending_report_issue is Some(_) ||
    child.stop_attempted ||
    child.origin.stopping {
    return Err(Unavailable)
  }
  // Bootstrap may have been installed before preparation. Transfer its
  // actual recorded census, never reinitialize it from equal aggregate bytes.
  match admission.read_bootstrap {
    None => if admission.read_bootstrap_attempted { return Err(Unavailable) }
    Some(bootstrap) => {
      guard admission.read_bootstrap_attempted &&
        ledger.original_inventory is Some(inventory) &&
        physical_equal(inventory.bootstrap, bootstrap) &&
        original_ledger_inventory_available(inventory.identity) else {
        return Err(Unavailable)
      }
    }
  }
  owner.transitioning = true
  match check_node_managed_run_admission(admission, ledger) {
    Err(issue) => {
      owner.transitioning = false
      return Err(issue)
    }
    Ok(_) => ()
  }
  let holder = match borrow_preparation_body(capacity) {
    Err(issue) => {
      owner.transitioning = false
      return Err(
        match issue {
          ForeignOriginal => ForeignOriginal
          Resource(issue) => Resource(issue)
          _ => Unavailable
        },
      )
    }
    Ok(value) => value
  }
  let transferred = transfer_preparation_retirement_to_run(
    capacity, input, prepared, ledger,
  )
  let retirement = match transferred {
    Err(issue) => {
      return_preparation_body_borrow(holder) |> ignore
      owner.transitioning = false
      return Err(
        match issue {
          ForeignOriginal => ForeignOriginal
          Resource(issue) => Resource(issue)
          _ => Unavailable
        },
      )
    }
    Ok(value) => value
  }
  let next = prepare_node_managed_run_original(
    admission.child,
    prepared,
    admission.abort_unpublished,
    purpose=admission.purpose,
  )
  next.attempted = true
  next.ledger = Some(ledger)
  next.preparation_holder = Some(holder)
  next.read_bootstrap_attempted = admission.read_bootstrap_attempted
  next.read_bootstrap = admission.read_bootstrap
  admission.read_bootstrap = None
  admission.prepared = None
  owner.admission = None
  owner.transitioning = false
  Ok((next, ledger, retirement))
}

///|
/// Preparation scratch/body retirement must have completed first: the normal
/// cleanup census rejects an outstanding preparation reservation. Uncertain
/// stop/report outcomes keep this exact original owner, never create a retry.
pub fn[I] cleanup_node_preparation_admission(
  owner : NodePreparationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  owner.transitioning = true
  let outcome = cleanup_node_managed_run_admission(admission)
  owner.transitioning = false
  outcome
}

///|
/// Before starting the original child, the fixed phase driver must bind the
/// same retained input receipt. No equal-shaped or foreign receipt may select
/// a different preparation body under this admission's Ledger.
pub fn[I] check_node_preparation_input(
  owner : NodePreparationAdmission[I],
  input : I,
) -> Result[Unit, ImportedChildLedgerIssue] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  check_node_managed_run_preparation(admission, input)
}
