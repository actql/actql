///|
pub struct ClientInstalledEffectOperationBorrow {
  priv mut original : ClientInstalledEffectOperationBorrow?
  priv mut owner : ClientInstalledManagedRun?
  priv mut ledger : @resources.Ledger?
  priv slot : Int
  priv mut backing : @resources.NodeManagedRunOperationBacking?
  // The SAME immutable extent's execution upper; never Host-supplied DATA.
  priv execution_limit : Int64
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
  // Existing Host-call upper bound also covers the single closed Resource
  // entry. The opening latch permits one such frame at a time, not one new
  // closure recipe per operation. Keep this fixed term in the same quote.
  // Control initialization is real even when the checked operation count is
  // zero; its fixed closed call cannot disappear with the row inventory.
  let calls = count + 1L
  // One shared conservative per-occurrence bound co-counts the existing
  // ordinary request controls and both physical/construction alternatives.
  // The original Host bound below is unchanged, including its three actual
  // argument vectors. Add only the coordinate and live stable-slot carriers;
  // retain the former larger view allowance after removing its coordinates.
  // Map buckets/nodes/growth come from their existing collection owner.
  // Add the actual original-task retention slots: pending constructor, joined
  // current fence, and pending binding close. Native settlement wrappers use
  // fewer Promise/closure alternatives than the former then/finally chains;
  // retain that existing record upper. One cleanup retirement cursor is a
  // scalar in the same fixed capture/cleanup frame, not another owner. Each
  // original token also retains its captured Int64 execution upper, one word
  // until retirement even while its constructor workspace is inactive. The
  // corresponding child/payload wrapper's synchronous flight-opening latch
  // occupies one more scalar; it starts before any original release callback.
  guard @shape.collection_construction_extent({
      records: 25L * calls,
      record_references: (64L + 3L) * calls,
      record_words: (12L + 2L) * calls,
      // Deferred member construction retains one original preparation-method
      // vector. Its length is bounded by these same checked child slots.
      reference_arrays: 3L * calls + 1L,
      reference_items: 14L * calls + count,
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
  // The actual Effect Ledger exposes31 methods and one DATA field. Its
  // caller view retains31 original-method/context pairs (2H,7R each), one
  // 32-field view and the same Run's control-work closure/context (6H,18R,3W).
  // Internal original calls keep the original ledger, not nested wrappers.
  // These are fixed existing implementation holders, not another owner or
  // per-method fee. Source tests pin this inventory to the real declaration.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 9L + shared.record_headers + 11L * count + 69L,
    reference_slots: 11L + slots + shared.reference_slots + 17L * count + 267L,
    scalar_words: 24L + shared.scalar_words + 29L * count,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // A growing backing overlaps its old backing. Price that constructor peak
  // through the same pinned append capacity, not an arbitrary byte margin.
  // Object.keys and its one loop iterator exist only while the original
  // 32-field caller view is constructed. Use the same collection owner.
  let keys = @shape.collection_construction_extent({
    records: 1L,
    record_references: 2L,
    record_words: 1L,
    reference_arrays: 1L,
    reference_items: 32L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + keys.record_headers,
    reference_slots: slots + keys.reference_slots,
    scalar_words: keys.scalar_words,
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
  select_installed_effect_operation_original(
    owner, prepared, request, expected_plan, member_index, per_row, operation_index,
    row_index, operation, false,
  )
}

///|
/// Retain the SAME pure occurrence and its complete returned/input backing
/// before Source/Preview. Its temporary constructor workspace is acquired by
/// begin_installed_effect_operation_construction immediately before work.
/// No new reservation, occurrence, permission or physical use is issued then.
pub fn retain_installed_effect_operation_construction(
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
  select_installed_effect_operation_original(
    owner, prepared, request, expected_plan, member_index, per_row, operation_index,
    row_index, operation, true,
  )
}

///|
// One original/latch boundary for full borrowing and retained constructor entry.
fn select_installed_effect_operation_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  member_index : Int,
  per_row : Bool,
  operation_index : Int,
  row_index : Int,
  operation : String,
  defer_construction : Bool,
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
    owner,
    prepared,
    request,
    expected_plan,
    member_index,
    per_row,
    operation_index,
    row_index,
    operation,
    defer_construction~,
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
  defer_construction? : Bool = false,
  lookup_probes? : Ref[Int64]? = None,
) -> Result[
  ClientInstalledEffectOperationBorrow,
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Unsupported)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.ledger is Some(ledger) else { return Err(Retired) }
  if !physical_equal(plan, expected_plan) ||
    row_index < 0 ||
    row_index >= (if per_row { plan.rows } else { 1 }) {
    return refuse_installed_effect_operation_after_current(
      owner,
      prepared,
      request,
      ForeignOriginal,
    )
  }
  let extent = match
    prepared_installed_effect_managed_operation(
      plan, member_index, per_row, operation_index, operation,
    ) {
    Ok(extent) => extent
    Err(issue) =>
      return refuse_installed_effect_operation_after_current(
        owner, prepared, request, issue,
      )
  }
  if defer_construction && extent.physical_attempt {
    return refuse_installed_effect_operation_after_current(
      owner,
      prepared,
      request,
      Unsupported,
    )
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
      return refuse_installed_effect_operation_after_current(
        owner,
        prepared,
        request,
        AlreadyBound,
      )
    }
  } else if !owner.effect_operations.is_empty() {
    return refuse_installed_effect_operation_after_current(
      owner,
      prepared,
      request,
      Retired,
    )
  }
  let retained = @execution.execution_capacity_retained_bytes(extent.capacity)
  let execution = @execution.execution_capacity_execution_bytes(extent.capacity)
  // Empty/control-only DATA cannot fund an actual constructor or operation.
  if retained <= 0L || execution <= 0L {
    return refuse_installed_effect_operation_after_current(
      owner,
      prepared,
      request,
      InsufficientCapacity,
    )
  }
  let previous_control = owner.effect_operation_controls
  let control_capacity = plan.operation_control_capacity
  let reserved = @resources.reserve_node_managed_run_operation(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_operation_original(
        owner, ledger, preparation, previous_control,
      )
    },
    previous_control.map(value => value.reservation),
    @execution.execution_capacity_retained_bytes(control_capacity),
    installed_effect_control_execution(previous_control, plan),
    extent.physical_attempt,
    extent.transfer_bytes,
    retained,
    if defer_construction {
      Int64::min(retained, execution)
    } else {
      execution
    },
  )
  let (reservation, body) = match reserved {
    Err(issue) =>
      return Err(installed_effect_operation_reservation_issue(issue))
    Ok(original) => original
  }
  // Retain the actual control BEFORE returning a later body refusal.
  let control = retain_installed_effect_operation_controls(
    owner, previous_control, reservation,
  )
  let backing = match body {
    Err(issue) => return Err(Ledger(issue))
    Ok(original) => original
  }
  let value : ClientInstalledEffectOperationBorrow = {
    original: None,
    owner: Some(owner),
    ledger: Some(ledger),
    slot: owner.effect_operations.length(),
    backing: Some(backing),
    execution_limit: execution,
    started: !extent.physical_attempt && !defer_construction,
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
// Preserve the old current/Unknown precedence for a refused operation. The
// successful path observes current only inside the closed Resource call.
fn refuse_installed_effect_operation_after_current(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  refusal : ClientInstalledManagedRunIssue,
) -> Result[
  ClientInstalledEffectOperationBorrow,
  ClientInstalledManagedRunIssue,
] {
  match require_installed_effect_operation_plan(owner, prepared, request) {
    Err(issue) => Err(issue)
    Ok(_) => Err(refusal)
  }
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
  guard value.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(original)) else {
    return Err(Unsupported)
  }
  if value.started {
    return Err(AlreadyBound)
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
  guard value.started &&
    value.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(original)) else {
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
  guard value.started &&
    value.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(original)) else {
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
    Some(@resources.NodeManagedRunOperationBacking::Construction(original)) =>
      @resources.settle_capacity(ledger, original)
    Some(@resources.NodeManagedRunOperationBacking::Physical(original)) =>
      @resources.settle_reservation(ledger, original)
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
// The SAME callback-free Local fence serves both closed Resource entrances.
fn check_installed_effect_operation_original(
  owner : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  preparation : ClientInstalledManagedRunOriginal,
  control : ClientEffectOperationControls?,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run_original(owner, ledger, preparation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match (control, owner.effect_operation_controls) {
    (None, None) => Ok(())
    (Some(before), Some(after)) if physical_equal(before, after) => Ok(())
    _ => Err(Retired)
  }
}

///|
fn installed_effect_operation_reservation_issue(
  issue : @resources.NodeManagedRunOperationIssue[
    ClientInstalledManagedRunIssue,
  ],
) -> ClientInstalledManagedRunIssue {
  match issue {
    @resources.NodeManagedRunOperationIssue::Original(issue) => issue
    @resources.NodeManagedRunOperationIssue::Control(issue) => Ledger(issue)
    @resources.NodeManagedRunOperationIssue::Admission(
      @resources.Resource(ResourceParked)
    ) => Ledger(ResourceParked)
    @resources.NodeManagedRunOperationIssue::Admission(issue) => Resource(issue)
  }
}

///|
// An admitted control remains owned here even if its later body refused.
fn retain_installed_effect_operation_controls(
  owner : ClientInstalledManagedRun,
  previous : ClientEffectOperationControls?,
  reservation : @resources.CapacityReservation,
  construction_deferred? : Bool = false,
) -> ClientEffectOperationControls {
  match previous {
    Some(control) => control
    None => {
      let control : ClientEffectOperationControls = {
        reservation,
        coordinates: Map([]),
        construction_deferred,
        construction_active: false,
      }
      owner.effect_operation_controls = Some(control)
      control
    }
  }
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
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  select_installed_effect_operation_controls(
    owner, prepared, request, expected_plan, false,
  )
}

///|
/// Retain all original management/grant/output controls before Source/Preview;
/// the actual synchronous control callback acquires its workspace separately.
pub fn retain_installed_effect_operation_controls_before_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  select_installed_effect_operation_controls(
    owner, prepared, request, expected_plan, true,
  )
}

///|
fn select_installed_effect_operation_controls(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  construction_deferred : Bool,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
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
  let result = begin_installed_effect_operation_controls_original(
    owner, prepared, request, expected_plan, construction_deferred,
  )
  owner.effect_operation_opening = false
  result
}

///|
fn begin_installed_effect_operation_controls_original(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  construction_deferred : Bool,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Unsupported)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.ledger is Some(ledger) else { return Err(Retired) }
  if !physical_equal(plan, expected_plan) {
    // Keep the old current/Unknown precedence for this refused Plan.
    return match
      require_installed_effect_operation_plan(owner, prepared, request) {
      Err(issue) => Err(issue)
      Ok(_) => Err(ForeignOriginal)
    }
  }
  let previous = owner.effect_operation_controls
  if previous is Some(original) &&
    original.construction_deferred != construction_deferred {
    return match
      require_installed_effect_operation_plan(owner, prepared, request) {
      Err(issue) => Err(issue)
      Ok(_) => Err(ForeignOriginal)
    }
  }
  let capacity = plan.operation_control_capacity
  let reservation = match
    @resources.reserve_node_managed_run_operation_controls(
      admission,
      plan,
      ledger,
      () => {
        check_installed_effect_operation_original(
          owner, ledger, preparation, previous,
        )
      },
      previous.map(value => value.reservation),
      @execution.execution_capacity_retained_bytes(capacity),
      if previous is Some(_) {
        installed_effect_control_execution(previous, plan)
      } else if construction_deferred {
        plan.operation_control_idle_execution
      } else {
        @execution.execution_capacity_execution_bytes(capacity)
      },
    ) {
    Err(issue) =>
      return Err(installed_effect_operation_reservation_issue(issue))
    Ok(original) => original
  }
  ignore(
    retain_installed_effect_operation_controls(
      owner,
      previous,
      reservation,
      construction_deferred~,
    ),
  )
  // Return this same immutable original, never a current proof or new Plan.
  Ok(plan)
}

///|
/// Acquire the original constructor workspace immediately before invocation.
/// Retained inputs and the spent coordinate already belong to this SAME token.
/// Reentry/retirement is fenced after one original Resource current; refused
/// growth changes neither the slot nor the retained backing or work history.
pub fn begin_installed_effect_operation_construction(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
  guard !value.retired &&
    value.owner is Some(owner) &&
    value.ledger is Some(ledger) &&
    value.backing is Some(backing) else {
    return Err(Retired)
  }
  guard backing is @resources.NodeManagedRunOperationBacking::Construction(_) else {
    return Err(Unsupported)
  }
  if value.started {
    return Err(AlreadyBound)
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Retired)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  let result = @resources.begin_node_managed_run_operation_construction(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_construction_original(
        value, owner, ledger, preparation, backing,
      )
    },
    backing,
    value.execution_limit,
  ).map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      value.started = true
      Ok(())
    }
  }
}

///|
/// Retain the original request/output after its synchronous constructor has
/// completed. The existing Host supplies this boundary only after the actual
/// callback and its current/reentry fence, never for the capture placeholder,
/// an asynchronous/failed constructor, a physical operation or cleanup ACK.
pub fn complete_installed_effect_operation_construction(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
  guard !value.retired &&
    value.owner is Some(owner) &&
    value.ledger is Some(ledger) &&
    value.backing is Some(backing) else {
    return Err(Retired)
  }
  guard backing is @resources.NodeManagedRunOperationBacking::Construction(_) else {
    return Err(Unsupported)
  }
  if !value.started {
    return Err(Unsupported)
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Retired)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  let result = @resources.complete_node_managed_run_operation_construction(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_construction_original(
        value, owner, ledger, preparation, backing,
      )
    },
    backing,
  ).map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  result
}

///|
// Callback-free original/slot/backing fence AFTER the one Resource current.
fn check_installed_effect_construction_original(
  value : ClientInstalledEffectOperationBorrow,
  owner : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  preparation : ClientInstalledManagedRunOriginal,
  backing : @resources.NodeManagedRunOperationBacking,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  match check_installed_managed_run_original(owner, ledger, preparation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard !value.retired &&
    value.owner is Some(current_owner) &&
    physical_equal(current_owner, owner) &&
    value.ledger is Some(current_ledger) &&
    physical_equal(current_ledger, ledger) &&
    owner.effect_operations.get(value.slot) is Some(Some(current)) &&
    physical_equal(current, value) &&
    value.backing
    is Some(
      @resources.NodeManagedRunOperationBacking::Construction(current_backing)
    ) &&
    backing
    is @resources.NodeManagedRunOperationBacking::Construction(original_backing) &&
    physical_equal(current_backing, original_backing) else {
    return Err(Retired)
  }
  Ok(())
}

///|
// One live control reservation. Original non-deferred borrowers retain their
// complete allowance; only the new synchronous caller has an inactive phase.
fn installed_effect_control_execution(
  control : ClientEffectOperationControls?,
  plan : ClientInstalledEffectManagedPlan,
) -> Int64 {
  if control is Some(original) &&
    original.construction_deferred &&
    !original.construction_active {
    plan.operation_control_idle_execution
  } else {
    @execution.execution_capacity_execution_bytes(
      plan.operation_control_capacity,
    )
  }
}

///|
pub fn begin_installed_effect_operation_control_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner, prepared, request, plan, true,
  )
}

///|
pub fn complete_installed_effect_operation_control_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner, prepared, request, plan, false,
  )
}

///|
fn resize_installed_effect_operation_control_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  active : Bool,
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
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) else {
    return Err(Retired)
  }
  if !physical_equal(plan, expected_plan) {
    return match
      require_installed_effect_operation_plan(owner, prepared, request) {
      Err(issue) => Err(issue)
      Ok(_) => Err(ForeignOriginal)
    }
  }
  if !control.construction_deferred {
    return Err(Unsupported)
  }
  if control.construction_active == active {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  let capacity = plan.operation_control_capacity
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let result = @resources.resize_node_managed_run_operation_control_construction(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_operation_original(
        owner,
        ledger,
        preparation,
        Some(control),
      )
    },
    control.reservation,
    retained,
    if active {
      @execution.execution_capacity_execution_bytes(capacity)
    } else {
      plan.operation_control_idle_execution
    },
  ).map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      control.construction_active = active
      Ok(())
    }
  }
}
