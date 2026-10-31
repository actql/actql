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
  priv slot : Int
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
  // One shared conservative per-occurrence bound co-counts the existing
  // ordinary request controls and both physical/construction alternatives.
  // The original Host bound below is unchanged, including its three actual
  // argument vectors. Add only the coordinate and live stable-slot carriers;
  // retain the former larger view allowance after removing its coordinates.
  // Map buckets/nodes/growth come from their existing collection owner.
  guard @shape.collection_construction_extent({
      records: 25L * count,
      record_references: 64L * count,
      record_words: 12L * count,
      reference_arrays: 3L * count,
      reference_items: 14L * count,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: count,
    })
    is Some(shared) else {
    return None
  }
  // The existing fixed setup plus one control/index record and the bounded
  // transient lookup/result carriers. Charge this once, never per wrapper.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 9L + shared.record_headers + 11L * count,
    reference_slots: 11L + slots + shared.reference_slots + 17L * count,
    scalar_words: 19L + shared.scalar_words + 28L * count,
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
  lookup_probes? : Ref[Int64]? = None,
) -> Result[
  ClientInstalledEffectOperationBorrow,
  ClientInstalledManagedRunIssue,
] {
  let (plan, ledger) = match
    require_installed_effect_operation_plan(owner, prepared, request) {
    Ok(original) => original
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
  if owner.effect_operation_controls is Some(control) {
    let coordinate : ClientEffectOperationCoordinate = {
      member_index,
      per_row,
      operation_index,
      row_index,
      lookup_probes,
    }
    if control.coordinates.get(coordinate) is Some(_) {
      return Err(AlreadyBound)
    }
  } else if !owner.effect_operations.is_empty() {
    return Err(Retired)
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
  guard owner.effect_operation_controls is Some(control) else {
    return Err(Retired)
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
    slot: owner.effect_operations.length(),
    backing: Some(backing),
    started: false,
    retired: false,
  }
  value.original = Some(value)
  owner.effect_operations.push(Some(value))
  // The retained key owns only coordinates, never this transient work output
  // or a settled operation view. Its slot remains spent until Run retirement.
  control.coordinates.set(
    { member_index, per_row, operation_index, row_index, lookup_probes: None, },
    value.slot,
  )
  Ok(value)
}

///|
fn require_installed_effect_operation(
  value : ClientInstalledEffectOperationBorrow,
  lookup_probes? : Ref[Int64]? = None,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
  guard !value.retired &&
    value.owner is Some(owner) &&
    value.ledger is Some(original_ledger) else {
    return Err(Retired)
  }
  record_effect_operation_lookup_probe(lookup_probes)
  guard owner.effect_operations.get(value.slot) is Some(Some(original)) &&
    physical_equal(original, value) else {
    return Err(Retired)
  }
  match require_installed_managed_run(owner) {
    Ok(ledger) if physical_equal(ledger, original_ledger) => {
      // The original current callback may retire this operation while leaving
      // its Run live. Inspect the SAME stable slot again without another I/O.
      record_effect_operation_lookup_probe(lookup_probes)
      guard !value.retired &&
        value.owner is Some(original_owner) &&
        physical_equal(original_owner, owner) &&
        value.ledger is Some(current_ledger) &&
        physical_equal(current_ledger, ledger) &&
        owner.effect_operations.get(value.slot) is Some(Some(original)) &&
        physical_equal(original, value) else {
        return Err(Retired)
      }
      Ok(ledger)
    }
    Ok(_) => Err(ForeignOriginal)
    Err(issue) => Err(issue)
  }
}

///|
// Optional private component work output at the actual search/comparison,
// never at function entry. Ordinary callers pass None; this is not a quota,
// permission, callback, timing sample or retained Run field.
fn record_effect_operation_lookup_probe(probes : Ref[Int64]?) -> Unit {
  if probes is Some(probes) {
    probes.val += 1L
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
      if value.owner is Some(owner) &&
        owner.effect_operations.get(value.slot) is Some(Some(original)) &&
        physical_equal(original, value) {
        owner.effect_operations[value.slot] = None
      }
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
  owner.effect_operation_controls = Some({
    reservation: original,
    coordinates: Map([]),
  })
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
