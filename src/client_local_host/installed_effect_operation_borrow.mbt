///|
/// The original managed Run retains this view of its existing B reservation.
/// It is not another Ledger, grant, physical dispatcher or cleanup Owner.
priv enum ClientEffectOperationBacking {
  Construction(@resources.CapacityReservation)
  Physical(@resources.Reservation)
}

///|
pub struct ClientInstalledEffectOperationBorrow {
  priv mut original : ClientInstalledEffectOperationBorrow?
  priv mut owner : ClientInstalledManagedRun?
  priv mut ledger : @resources.Ledger?
  priv member_index : Int
  priv per_row : Bool
  priv operation_index : Int
  priv row_index : Int
  priv mut backing : ClientEffectOperationBacking?
  priv mut started : Bool
  priv mut retired : Bool
}

///|
// Variable same-Run inventory, not a new Root or provider allowance. The
// operation token below funds provider bodies; this separate capacity token
// keeps spent occurrence controls live after those bodies actually retire.
fn installed_effect_operation_control_capacity(
  children : Int,
) -> @execution.ExecutionCapacity? {
  if children < 0 {
    return None
  }
  guard closed_values_append_capacity(children) is Some(slots) else {
    return None
  }
  let count = children.to_int64()
  // Per selected occurrence: view(1H,4R,6W), original/owner/ledger/backing Some
  // (4H,4R,4W), backing variant(1H,1R,1W), original B Reservation
  // (1H,5R,8W), observed-quantity tuple(1H,0R,3W), and the pure branch's
  // CapacityReservation wrapper(1H,1R). Co-count the pure wrapper for every
  // physical alternative. No quantity/output holders are constructed here.
  // Shared original control reservation/wrapper/observed tuple/Some adds
  // (4H,7R,12W); one appended array backing adds (1H,slotsR). The existing
  // fixed Host/Run prelude and B original-inventory owner are not re-quoted.
  // The actual JS request child also survives body settlement in the SAME
  // capture retry inventory, so its controls belong HERE, not in provider body
  // capacity. Co-count this branch for every occurrence: child factory frame (including per-row/member selection)
  // (1H15R4W), current/drain/prepare/status closures(4H4R), child(1H4R),
  // original RSE context(1H11R1W), options(1H7R3W), constructor closure(1H2R),
  // capture retainer frame(1H3R2W), two wrappers(2H4R), captured methods(1H4R),
  // six drain/retry/async-finally closures(6H6R), four invalid-thenable join
  // callbacks(4H4R), and two live status snapshots(2H2W): 25H64R12W.
  // Three original Reflect.apply argument vectors have9+3+2 entries. Use the
  // pinned array representation; Promise engine backing stays opaque runtime
  // support, as in managed_cleanup_control_inventory, not a guessed RSS price.
  guard @shape.collection_construction_extent({
      records: 25L,
      record_references: 64L,
      record_words: 12L,
      reference_arrays: 3L,
      reference_items: 14L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(host) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 5L + (9L + host.record_headers) * count,
    reference_slots: 7L + slots + (15L + host.reference_slots) * count,
    scalar_words: 12L + (22L + host.scalar_words) * count,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // A growing backing overlaps its old backing. Price that constructor peak
  // through the same pinned append capacity, not an arbitrary byte margin.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: slots,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
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
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_closing {
    return Err(Retired)
  }
  if owner.effect_operation_opening {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  let result = borrow_installed_effect_operation_original(
    owner, prepared, request, expected_plan, member_index, per_row, operation_index,
    row_index, operation,
  )
  owner.effect_operation_opening = false
  result
}

///|
fn borrow_installed_effect_operation_original(
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
  match ensure_installed_effect_operation_controls(owner, ledger, plan) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
    original: None,
    owner: Some(owner),
    ledger: Some(ledger),
    member_index,
    per_row,
    operation_index,
    row_index,
    backing: Some(backing),
    started: false,
    retired: false,
  }
  value.original = Some(value)
  owner.effect_operations.push(value)
  Ok(value)
}

///|
fn require_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
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
    Ok(_) => Ok(())
  }
}

///|
/// Account the original physical driver's uncertain transfer on the same
/// spent reservation. Business Unknown does not guess an amount from a quota.
pub fn mark_installed_effect_operation_transfer_uncertain(
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
  match @resources.mark_transfer_uncertain(ledger, original, bytes) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Only the existing Host's same-child cleanup path supplies this observation.
/// Pending stop, fulfilled Promise, saved wire and logical outcome are not ACKs.
pub fn retire_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
  original_cleanup_confirmed : Bool,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
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

///|
fn ensure_installed_effect_operation_controls(
  owner : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if owner.effect_operation_controls is Some(_) {
    return Ok(())
  }
  let capacity = plan.operation_control_capacity
  let original = match
    @resources.reserve_capacity(
      ledger,
      @execution.execution_capacity_retained_bytes(capacity),
      @execution.execution_capacity_execution_bytes(capacity),
    ) {
    Ok(original) => original
    Err(issue) => return Err(Ledger(issue))
  }
  owner.effect_operation_controls = Some(original)
  Ok(())
}

///|
/// Debit the original Plan's already quoted management controls BEFORE the
/// Node consumer constructs its variable capture/child inventory. This is a
/// reservation on the same admitted Run, never another quote/Root/admission.
/// Direct original borrowers retain the same idempotent reserve fallback.
pub fn begin_installed_effect_operation_controls(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_closing {
    return Err(Retired)
  }
  if owner.effect_operation_opening {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  let result = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Err(issue) => Err(issue)
    Ok(plan) =>
      if !physical_equal(plan, expected_plan) {
        Err(ForeignOriginal)
      } else {
        match owner.ledger {
          None => Err(ForeignOriginal)
          Some(ledger) =>
            ensure_installed_effect_operation_controls(owner, ledger, plan)
        }
      }
  }
  owner.effect_operation_opening = false
  result
}
