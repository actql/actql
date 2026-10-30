///|
/// The original managed Run retains this view of its existing B reservation.
/// It is not another Ledger, grant, physical dispatcher or cleanup Owner.
priv enum ClientEffectOperationBacking {
  Construction(@resources.CapacityReservation)
  Physical(@resources.Reservation)
}

///|
pub struct ClientInstalledEffectOperationBorrow {
  priv mut owner : ClientInstalledManagedRun?
  priv mut ledger : @resources.Ledger?
  priv member_index : Int
  priv per_row : Bool
  priv operation_index : Int
  priv row_index : Int
  priv mut backing : ClientEffectOperationBacking?
  priv mut started : Bool
  priv mut remaining_transfer : Int64
  priv mut retired : Bool
}

///|
/// Select the SAME original occurrence before constructor/I/O work. Row index
/// is checked against the original Plan bound; an equal extent or a spent
/// occurrence cannot be reissued. Authority still comes from Account/claim.
pub fn borrow_installed_effect_operation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  member_index : Int,
  per_row : Bool,
  operation_index : Int,
  row_index : Int,
  operation : String,
) -> Result[
  ClientInstalledEffectOperationBorrow,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Ok(plan) => plan
    Err(issue) => return Err(issue)
  }
  if !physical_equal(plan, expected_plan) ||
    row_index < 0 ||
    row_index >= (if per_row { plan.rows } else { 1 }) {
    return Err(ForeignOriginal)
  }
  let extent = match
    prepared_installed_effect_managed_operation(
      plan, member_index, per_row, operation_index, operation,
    ) {
    Ok(extent) => extent
    Err(issue) => return Err(issue)
  }
  for prior in owner.effect_operations {
    if prior.member_index == member_index &&
      prior.per_row == per_row &&
      prior.operation_index == operation_index &&
      prior.row_index == row_index {
      return Err(AlreadyBound)
    }
  }
  let ledger = match require_installed_managed_run(owner) {
    Ok(ledger) => ledger
    Err(issue) => return Err(issue)
  }
  let retained = @execution.execution_capacity_retained_bytes(extent.capacity)
  let execution = @execution.execution_capacity_execution_bytes(extent.capacity)
  // Empty/control-only DATA cannot fund an actual constructor or operation.
  if retained <= 0L || execution <= 0L {
    return Err(InsufficientCapacity)
  }
  let backing : ClientEffectOperationBacking = if extent.physical_attempt {
    match
      @resources.reserve_attempt(
        ledger,
        extent.transfer_bytes,
        retained,
        execution,
      ) {
      Ok(original) => Physical(original)
      Err(issue) => return Err(Ledger(issue))
    }
  } else {
    match @resources.reserve_capacity(ledger, retained, execution) {
      Ok(original) => Construction(original)
      Err(issue) => return Err(Ledger(issue))
    }
  }
  let value : ClientInstalledEffectOperationBorrow = {
    owner: Some(owner),
    ledger: Some(ledger),
    member_index,
    per_row,
    operation_index,
    row_index,
    backing: Some(backing),
    started: false,
    remaining_transfer: extent.transfer_bytes,
    retired: false,
  }
  owner.effect_operations.push(value)
  Ok(value)
}

///|
fn require_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard !value.retired &&
    value.owner is Some(owner) &&
    owner.effect_operations.any(prior => physical_equal(prior, value)) &&
    value.ledger is Some(original_ledger) else {
    return Err(Retired)
  }
  match require_installed_managed_run(owner) {
    Ok(ledger) if physical_equal(ledger, original_ledger) => Ok(ledger)
    Ok(_) => Err(ForeignOriginal)
    Err(issue) => Err(issue)
  }
}

///|
/// Account one possible physical use. This is not permission or a send.
pub fn start_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_effect_operation(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  if value.started {
    return Err(AlreadyBound)
  }
  guard value.backing is Some(Physical(original)) else {
    return Err(Unsupported)
  }
  match @resources.consume_reserved_attempt(ledger, original) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      value.started = true
      Ok(())
    }
  }
}

///|
/// Exact bytes enter before projection. Failure never refills the attempt.
pub fn charge_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
  bytes : Int64,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_effect_operation(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  guard value.started && value.backing is Some(Physical(original)) else {
    return Err(Unsupported)
  }
  match @resources.charge_transfer(ledger, original, bytes) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      value.remaining_transfer -= bytes
      Ok(())
    }
  }
}

///|
/// A lost reply retains possible transfer on the same spent reservation.
pub fn mark_installed_effect_operation_unknown(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  let ledger = match require_installed_effect_operation(value) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  guard value.started && value.backing is Some(Physical(original)) else {
    return Err(Unsupported)
  }
  match
    @resources.mark_transfer_uncertain(
      ledger,
      original,
      value.remaining_transfer,
    ) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      value.remaining_transfer = 0L
      Ok(())
    }
  }
}

///|
/// Only the existing Host's same-child cleanup path supplies this observation.
/// Pending stop, fulfilled Promise, saved wire and logical outcome are not ACKs.
pub fn retire_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
  original_cleanup_confirmed : Bool,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  if value.retired {
    return Ok(true)
  }
  if !original_cleanup_confirmed {
    return Ok(false)
  }
  guard value.ledger is Some(ledger) else { return Err(ForeignOriginal) }
  let result = match value.backing {
    Some(Construction(original)) => @resources.settle_capacity(ledger, original)
    Some(Physical(original)) => @resources.settle_reservation(ledger, original)
    None => return Err(ForeignOriginal)
  }
  match result {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      value.backing = None
      value.owner = None
      value.ledger = None
      value.retired = true
      Ok(true)
    }
  }
}
