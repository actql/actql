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
  if admission.purpose != LocalPreparation {
    return Err(Unavailable)
  }
  owner.transitioning = true
  let outcome = start_node_managed_run_admission(admission)
  owner.transitioning = false
  outcome
}

///|
/// Read the immutable limits of this exact started input admission before a
/// checked plan is transferred. No Ledger, new grant, purpose conversion or
/// second imported child is exposed. The later adoption rechecks currentness.
pub fn[I] node_local_preparation_limits(
  owner : NodePreparationAdmission[I],
  input : I,
) -> Result[LedgerLimits, ImportedChildLedgerIssue] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  match check_node_local_preparation_original(admission, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard admission.ledger is Some(ledger) else { return Err(Unavailable) }
  // Immutable original policy DATA only. The immediately following adoption
  // owns the reentrant current boundary and post-callback state fence. This
  // getter cannot admit a Run or certify currentness/physical cleanup.
  Ok(ledger_limits(ledger))
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
  match check_node_local_preparation_original(admission, input) {
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
  (
    NodeManagedRunAdmission[P],
    Ledger,
    PreparationRetirement,
    PreparationBodyBorrow[P],
  ),
  ImportedChildLedgerIssue,
] {
  if owner.transitioning {
    return Err(Unknown)
  }
  guard owner.admission is Some(admission) else { return Err(AlreadyConsumed) }
  match check_node_local_preparation_original(admission, input) {
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
  // The census belongs to the original preparation capacity. A separate
  // read-bootstrap owner cannot be transferred as a compatibility path.
  if admission.read_bootstrap_attempted || admission.read_bootstrap is Some(_) {
    return Err(Unavailable)
  }
  if !physical_equal(capacity.ledger, ledger) ||
    !(capacity.input is Some(original) && physical_equal(original, input)) ||
    !(capacity.body is Some(original) && physical_equal(original, prepared)) {
    return Err(ForeignOriginal)
  }
  if capacity.phase != Ready ||
    capacity.retirement_claimed ||
    capacity.borrowers > capacity.max_borrowers - 2 {
    return Err(Unavailable)
  }
  // Claim BOTH real holders before the one reentrant current callback: one
  // for the admission and one for the Run's actual raw fields. No token can
  // escape on refusal; the same reservation and old holders remain intact.
  owner.transitioning = true
  let transferred = transfer_preparation_adoption_holders(
    capacity,
    input,
    prepared,
    ledger,
    () => check_node_managed_run_admission(admission, ledger),
  )
  let (retirement, holder, run_holder) = match transferred {
    Err(issue) => {
      owner.transitioning = false
      return Err(issue)
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
  admission.prepared = None
  owner.admission = None
  owner.transitioning = false
  Ok((next, ledger, retirement, run_holder))
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
  check_node_local_preparation_original(admission, input)
}

///|
/// The actual local-preparation supplier was selected before a checked domain
/// existed. Keep that original input purpose through adoption; no completed
/// Plan can convert it to a separately issued Source, Model or Content child.
fn[I] check_node_local_preparation_original(
  admission : NodeManagedRunAdmission[I],
  input : I,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_preparation(admission, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if admission.purpose == LocalPreparation {
    Ok(())
  } else {
    Err(Unavailable)
  }
}
