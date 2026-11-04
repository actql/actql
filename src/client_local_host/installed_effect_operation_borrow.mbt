///|
pub struct ClientInstalledEffectOperationBorrow {
  priv mut original : ClientInstalledEffectOperationBorrow?
  priv mut owner : ClientInstalledManagedRun?
  priv mut ledger : @resources.Ledger?
  priv slot : Int
  priv member_index : Int
  priv mut extent : ClientInstalledEffectOperationExtent?
  priv mut input_selected : Bool
  priv mut backing : @resources.NodeManagedRunOperationBacking?
  // The SAME immutable extent's execution upper; never Host-supplied DATA.
  priv mut execution_limit : Int64
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
      // The selected extent Some adds1H2R1W; member/input-selected are2W.
      records: 26L * calls,
      record_references: (64L + 3L + 2L) * calls,
      record_words: (12L + 2L + 3L) * calls,
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
  // 32-field view and the same Run's control-work closure/context (6H,20R,3W).
  // Two references retain its successfully parsed Preview and original wire
  // for hot recovery; the same forest is never constructed a second time.
  // Internal original calls keep the original ledger, not nested wrappers.
  // These are fixed existing implementation holders, not another owner or
  // per-method fee. Source tests pin this inventory to the real declaration.
  let retained : @execution.PreparationRepresentationUnits = {
    // Optional Host input tuple/Some and its retained opaque capacity. Wire
    // text remains with the already-funded original Preview producer.
    // One same-Run optional actual-row inventory adds its field and one Some
    // carrier at most, independently of how many operation bodies are live.
    record_headers: 10L + shared.record_headers + 11L * count + 69L + 4L,
    reference_slots: 12L +
    slots +
    shared.reference_slots +
    17L * count +
    269L +
    4L,
    scalar_words: 25L + shared.scalar_words + 29L * count + 4L,
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
  // One synchronous input-quantity frame can run before the original byte
  // resize. It has at most sixteen returned constructor roles, each with its
  // capacity/Option/tuple/collection/call carriers (8H,64R,64W), plus its
  // argument/selection frame (8H,32R,16W). No payload is parsed here. Keep this
  // fixed frame prepaid in idle controls; it is not per occurrence or byte.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + keys.record_headers + 16L * 8L + 8L,
    reference_slots: slots + keys.reference_slots + 16L * 64L + 32L,
    scalar_words: keys.scalar_words + 16L * 64L + 16L,
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
  let original_extent = match
    prepared_installed_effect_managed_operation(
      plan, member_index, per_row, operation_index, operation,
    ) {
    Ok(extent) => extent
    Err(issue) =>
      return refuse_installed_effect_operation_after_current(
        owner, prepared, request, issue,
      )
  }
  let extent = if plan.closed_rows is None {
    guard owner.effect_operation_controls.bind(value => value.captured_rows)
      is Some(rows) &&
      (!per_row || row_index < rows) &&
      resolve_installed_effect_capture_extent(original_extent, rows)
      is Some(extent) else {
      return refuse_installed_effect_operation_after_current(
        owner,
        prepared,
        request,
        InsufficientCapacity,
      )
    }
    extent
  } else {
    original_extent
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
  guard installed_effect_control_capacity(previous_control, plan)
    is Some((control_capacity, control_idle)) else {
    return Err(Unsupported)
  }
  let reserved = @resources.reserve_prepared_run_operation(
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
    installed_effect_control_execution(
      previous_control, control_capacity, control_idle,
    ),
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
    member_index,
    extent: Some(extent),
    input_selected: false,
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
      value.extent = None
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
        ledger_codec_active: false,
        ledger_codec_workspace: 0L,
        captured_rows: None,
        host_input: None,
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
  guard installed_effect_control_capacity(previous, plan)
    is Some((capacity, idle)) else {
    return Err(Unsupported)
  }
  let reservation = match
    @resources.reserve_prepared_run_operation_controls(
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
        installed_effect_control_execution(previous, capacity, idle)
      } else if construction_deferred {
        idle
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
/// The actual original response/recovery input is now owned. Resolve its
/// constructor quantity using this SAME checked Plan's member/row inventory,
/// then grow only this token before entering that callback. The original
/// immutable maximum remains a rejection bound, not an up-front reservation
/// or permission. A physical child must already have spent its one attempt.
pub fn begin_installed_effect_operation_input(
  value : ClientInstalledEffectOperationBorrow,
  input : ClientInstalledEffectOperationExtent,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
  guard !value.retired &&
    value.owner is Some(owner) &&
    value.ledger is Some(ledger) &&
    value.backing is Some(backing) &&
    value.extent is Some(extent) else {
    return Err(Retired)
  }
  guard extent.maximum is Some(maximum) && input.maximum is None else {
    return Err(Unsupported)
  }
  if value.input_selected ||
    owner.effect_operation_opening ||
    owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  if input.operation != extent.operation ||
    input.physical_attempt != extent.physical_attempt ||
    input.transfer_bytes != extent.transfer_bytes ||
    (extent.physical_attempt && !value.started) ||
    (!extent.physical_attempt && value.started) {
    return Err(ForeignOriginal)
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    plan.operations.get(value.member_index) is Some(demand) else {
    return Err(Retired)
  }
  guard resolve_installed_effect_id_extent(input, demand.effect_id)
    is Some(input) &&
    (match plan.closed_rows {
      Some(rows) => Some(rows)
      None => owner.effect_operation_controls.bind(value => value.captured_rows)
    })
    is Some(rows) &&
    resolve_installed_effect_capture_extent(input, rows) is Some(input) &&
    // A deferred constructor holds retained backing, not its unused warm
    // workspace estimate. Its actual cold input may need less scratch.
    // Physical operations already hold their initial execution envelope.
    (match backing {
      @resources.NodeManagedRunOperationBacking::Construction(_) =>
        @execution.execution_capacity_retained_bytes(extent.capacity) <=
        @execution.execution_capacity_retained_bytes(input.capacity)
      @resources.NodeManagedRunOperationBacking::Physical(_) =>
        installed_effect_capacity_within(extent.capacity, input.capacity)
    }) &&
    installed_effect_capacity_within(input.capacity, maximum.capacity) else {
    return Err(InsufficientCapacity)
  }
  owner.effect_operation_opening = true
  let result = @resources.grow_prepared_run_operation_capacity(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_operation_backing_original(
        value, owner, ledger, preparation, backing,
      )
    },
    backing,
    @execution.execution_capacity_retained_bytes(input.capacity),
    @execution.execution_capacity_execution_bytes(input.capacity),
  ).map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      value.execution_limit = @execution.execution_capacity_execution_bytes(
        input.capacity,
      )
      value.input_selected = true
      value.started = true
      Ok(())
    }
  }
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
  let result = @resources.begin_prepared_run_operation_construction(
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
  let result = @resources.complete_prepared_run_operation_construction(
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
  guard backing is @resources.NodeManagedRunOperationBacking::Construction(_) else {
    return Err(Unsupported)
  }
  check_installed_effect_operation_backing_original(
    value, owner, ledger, preparation, backing,
  )
}

///|
fn check_installed_effect_operation_backing_original(
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
    value.backing is Some(current_backing) &&
    (match (current_backing, backing) {
      (
        @resources.NodeManagedRunOperationBacking::Construction(current),
        @resources.NodeManagedRunOperationBacking::Construction(original),
      ) => physical_equal(current, original)
      (
        @resources.NodeManagedRunOperationBacking::Physical(current),
        @resources.NodeManagedRunOperationBacking::Physical(original),
      ) => physical_equal(current, original)
      _ => false
    }) else {
    return Err(Retired)
  }
  Ok(())
}

///|
// One live control reservation. Original non-deferred borrowers retain their
// complete allowance; only the new synchronous caller has an inactive phase.
fn installed_effect_control_execution(
  control : ClientEffectOperationControls?,
  capacity : @execution.ExecutionCapacity,
  idle : Int64,
) -> Int64 {
  if control is Some(original) &&
    original.construction_deferred &&
    !original.construction_active {
    idle
  } else {
    @execution.execution_capacity_execution_bytes(capacity)
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
/// Refine this SAME control reservation from its producer-owned Preview wire
/// before Host JSON.parse. The immutable installing limits stay unchanged.
pub fn begin_installed_effect_operation_control_input(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  wire : String,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    true,
    input_wire=Some(wire),
  )
}

///|
/// Nested normalizing Ledger codec on this SAME synchronous control frame.
/// None is the existing fixed Ledger issuance schema bound, not an unknown
/// wire encoded as zero. Some is the actual original stored wire before parse.
pub fn begin_installed_effect_operation_ledger_codec(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  wire : String?,
  nodes : Int,
  depth : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    true,
    ledger_codec=Some((true, wire, nodes, depth)),
  )
}

///|
pub fn complete_installed_effect_operation_ledger_codec(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    true,
    ledger_codec=Some((false, None, 0, 0)),
  )
}

///|
fn resize_installed_effect_operation_control_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  active : Bool,
  input_wire? : String? = None,
  ledger_codec? : (Bool, String?, Int, Int)? = None,
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
  match ledger_codec {
    None =>
      if control.construction_active == active || control.ledger_codec_active {
        return Err(AlreadyBound)
      }
    Some((entering, _, _, _)) =>
      if !active ||
        !control.construction_active ||
        control.ledger_codec_active == entering ||
        input_wire is Some(_) {
        return Err(AlreadyBound)
      }
  }
  let codec_workspace = match ledger_codec {
    Some((true, wire, nodes, depth)) => {
      if nodes < 1 || nodes > 4096 || depth < 1 || depth > 32 {
        return Err(Unsupported)
      }
      let bytes = match wire {
        Some(wire) =>
          match @scalar.admit_utf8_length(wire, 1000000) {
            Ok(bytes) if bytes > 0 => bytes
            _ => return Err(Unsupported)
          }
        None =>
          match installed_effect_control_wire_bound(1, 1000000) {
            Ok(bytes) => bytes
            Err(issue) => return Err(issue)
          }
      }
      guard installed_effect_contract_response_construction_capacity(
          bytes, nodes, depth,
        )
        is Some(codec) &&
        @execution.execution_capacity_retained_bytes(codec) <=
        @execution.execution_capacity_retained_bytes(
          plan.operation_control_capacity,
        ) else {
        return Err(Unsupported)
      }
      @execution.execution_capacity_execution_bytes(codec) -
      @execution.execution_capacity_retained_bytes(codec)
    }
    _ => 0L
  }
  let input = match input_wire {
    None => None
    Some(wire) => {
      if !active {
        return Err(Unsupported)
      }
      match control.host_input {
        Some((original, _)) => {
          if original != wire {
            return Err(ForeignOriginal)
          }
          // The same successful selection cannot fund another parsed forest.
          // A failed byte resize below leaves host_input absent and retryable.
          return Err(AlreadyBound)
        }
        None => {
          let capacity = match
            installed_effect_host_preview_input_capacity(plan, wire) {
            Err(issue) => return Err(issue)
            Ok(value) => value
          }
          Some((wire, capacity))
        }
      }
    }
  }
  guard installed_effect_control_capacity(
      Some(control),
      plan,
      input~,
      codec_workspace=Some(codec_workspace),
    )
    is Some((capacity, idle)) else {
    return Err(Unsupported)
  }
  owner.effect_operation_opening = true
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let result = @resources.resize_prepared_run_operation_control_construction(
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
      idle
    },
  ).map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      if input is Some(original) {
        control.host_input = Some(original)
      }
      match ledger_codec {
        Some((entering, _, _, _)) => {
          control.ledger_codec_active = entering
          control.ledger_codec_workspace = codec_workspace
        }
        None => control.construction_active = active
      }
      Ok(())
    }
  }
}

///|
// The actual same-Run Preview wire already belongs to its producer. Scan only
// UTF8 length here; do not parse, normalize, encode, check or compile it again.
fn installed_effect_host_preview_input_capacity(
  plan : ClientInstalledEffectManagedPlan,
  wire : String,
) -> Result[@execution.ExecutionCapacity, ClientInstalledManagedRunIssue] {
  let mut maximum : Int? = None
  for demand in plan.operations {
    for extent in demand.member_extents {
      if extent.host_input_limits is Some(limits) {
        maximum = Some(
          match maximum {
            None => limits.max_input_bytes
            Some(old) => Int::min(old, limits.max_input_bytes)
          },
        )
      }
    }
  }
  guard maximum is Some(maximum) else { return Err(Unsupported) }
  let bytes = match @scalar.admit_utf8_length(wire, maximum) {
    Err(_) => return Err(Unsupported)
    Ok(value) => value
  }
  if bytes < 1 {
    return Err(Unsupported)
  }
  let mut retained = 0L
  let mut workspace = 0L
  for demand in plan.operations {
    for extent in demand.member_extents {
      if extent.host_input_limits is Some(limits) {
        guard installed_standard_host_preview_input_parts(
            limits.max_input_bytes,
            limits.max_nodes,
            limits.max_depth,
            Some(bytes),
          )
          is Some((held, scratch)) &&
          standard_create_representation_capacity(
            { ..held, owned_utf16_units: 0L, },
            { ..scratch, owned_utf16_units: 0L, },
          )
          is Some(capacity) &&
          @execution.checked_preparation_add_product(
            retained,
            @execution.execution_capacity_retained_bytes(capacity),
            1L,
          )
          is Some(next) else {
          return Err(Unsupported)
        }
        retained = next
        workspace = Int64::max(
          workspace,
          @execution.execution_capacity_execution_bytes(capacity) -
          @execution.execution_capacity_retained_bytes(capacity),
        )
      }
    }
  }
  guard @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(capacity) else {
    return Err(Unsupported)
  }
  Ok(capacity)
}

///|
// Original per-operation control allowances times the actual completed member
// inventory. This reuses the existing control/collection tariffs; body tokens
// still reserve their own bytes, transfer and attempts at their real entrance.
fn installed_effect_control_capacity_for_rows(
  plan : ClientInstalledEffectManagedPlan,
  rows : Int,
) -> (@execution.ExecutionCapacity, Int64)? {
  if rows < 0 || rows > plan.rows {
    return None
  }
  let mut children = 0L
  let mut retained = 0L
  let mut workspace = 0L
  for demand in plan.operations {
    guard @execution.checked_preparation_add_product(
        children,
        demand.row_extents.length().to_int64(),
        rows.to_int64(),
      )
      is Some(count) &&
      @execution.checked_preparation_add_product(
        count,
        demand.member_extents.length().to_int64(),
        1L,
      )
      is Some(count) &&
      count <= 2147483647L else {
      return None
    }
    children = count
    if demand.controls_per_row is Some(original) {
      guard @execution.execution_capacity_inventory_add(
          retained,
          QuotedBytes,
          @execution.execution_capacity_retained_bytes(original),
          rows,
        )
        is Some(next) else {
        return None
      }
      retained = next
      if rows > 0 {
        workspace = Int64::max(
          workspace,
          @execution.execution_capacity_execution_bytes(original) -
          @execution.execution_capacity_retained_bytes(original),
        )
      }
    }
  }
  guard installed_effect_operation_control_capacity(children.to_int())
    is Some(base) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(base),
      retained,
      1L,
    )
    is Some(idle) &&
    @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) &&
    @execution.execution_capacity(retained, execution) is Some(implementation) &&
    @execution.add_execution_capacity(base, implementation) is Some(capacity) else {
    return None
  }
  Some((capacity, idle))
}

///|
/// Bind actual completed input inventory to this Run's existing control token
/// before capture/export constructors. The Plan keeps its original policy
/// ceiling; neither an equal checked graph nor a Host-supplied count qualifies.
pub fn retain_installed_effect_captured_input_inventory(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  inputs : @strategy.CapturedEffectInputs,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  // Availability may call the original installed material. Fence that call,
  // its metadata projection and the later Resource current in one same-owner
  // flight; a nested call cannot observe or admit another inventory.
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    owner.source_free_captured is Some(captured) else {
    return Err(Retired)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !physical_equal(plan, expected_plan) ||
    !@strategy.captured_effect_inputs_match_captured_run(inputs, captured) ||
    !@strategy.captured_effect_inputs_match_computation(
      inputs,
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ) {
    return Err(ForeignOriginal)
  }
  // A closed inventory already funded its original constructors. Do not turn
  // a scalar/no-input member into a relation, recount known rows or add another
  // current callback merely because the normal Host shares this entrance.
  if plan.closed_rows is Some(_) {
    return check_installed_effect_operation_original(
      owner,
      ledger,
      preparation,
      Some(control),
    )
  }
  // Exactly one metadata observation, no count-only row/provider pass. A
  // revoked generation cannot supply a number; its pending cleanup stays put.
  guard @strategy.captured_effect_inputs_row_inventory(inputs, plan.rows)
    is Some(rows) else {
    return Err(InsufficientCapacity)
  }
  if control.construction_active ||
    control.ledger_codec_active ||
    (control.captured_rows is Some(original) && original != rows) {
    return Err(AlreadyBound)
  }
  guard installed_effect_control_capacity(
      Some(control),
      plan,
      captured_rows=Some(rows),
    )
    is Some((capacity, idle)) else {
    return Err(Unsupported)
  }
  let result = @resources.resize_prepared_run_operation_control_construction(
    admission,
    plan,
    ledger,
    () => {
      match
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard owner.source_free_captured is Some(original) &&
        physical_equal(original, captured) &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured) &&
        @strategy.captured_effect_inputs_retained(inputs) else {
        return Err(ForeignOriginal)
      }
      Ok(())
    },
    control.reservation,
    @execution.execution_capacity_retained_bytes(capacity),
    installed_effect_control_execution(Some(control), capacity, idle),
  ).map_err(installed_effect_operation_reservation_issue)
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      if plan.closed_rows is None {
        control.captured_rows = Some(rows)
      }
      Ok(())
    }
  }
}

///|
// Preserve every retained Host forest until this same control Owner retires.
// Synchronous Host parsing and the old control callbacks do not overlap their
// private scratch. Native member/cold/physical backing remains independent.
fn installed_effect_control_capacity(
  control : ClientEffectOperationControls?,
  plan : ClientInstalledEffectManagedPlan,
  input? : (String, @execution.ExecutionCapacity)? = None,
  codec_workspace? : Int64? = None,
  captured_rows? : Int? = None,
) -> (@execution.ExecutionCapacity, Int64)? {
  let selected = match input {
    Some(value) => Some(value)
    None =>
      match control {
        None => None
        Some(value) => value.host_input
      }
  }
  // Other same-owner reservation/current paths must retain a live or failed
  // nested codec's prefix. Only its explicit synchronous completion supplies
  // Some(0); observing another operation is never a workspace return.
  let codec_workspace = codec_workspace.unwrap_or(
    match control {
      Some(value) => value.ledger_codec_workspace
      None => 0L
    },
  )
  let rows = match captured_rows {
    Some(_) => captured_rows
    None => control.bind(value => value.captured_rows)
  }
  let (base, base_idle) = if plan.closed_rows is None && rows is Some(rows) {
    guard installed_effect_control_capacity_for_rows(plan, rows) is Some(value) else {
      return None
    }
    value
  } else {
    (plan.operation_control_capacity, plan.operation_control_idle_execution)
  }
  let base_retained = @execution.execution_capacity_retained_bytes(base)
  guard @execution.checked_preparation_add_product(
      base_retained, codec_workspace, 1L,
    )
    is Some(codec_execution) &&
    @execution.execution_capacity(
      base_retained,
      Int64::max(
        @execution.execution_capacity_execution_bytes(base),
        codec_execution,
      ),
    )
    is Some(original) else {
    return None
  }
  guard selected is Some((_, host)) else { return Some((original, base_idle)) }
  let host_retained = @execution.execution_capacity_retained_bytes(host)
  guard @execution.checked_preparation_add_product(
      @execution.execution_capacity_retained_bytes(original),
      host_retained,
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(base_idle, host_retained, 1L)
    is Some(idle) &&
    @execution.checked_preparation_add_product(
      @execution.execution_capacity_execution_bytes(original),
      host_retained,
      1L,
    )
    is Some(control_execution) &&
    @execution.checked_preparation_add_product(
      base_idle,
      @execution.execution_capacity_execution_bytes(host),
      1L,
    )
    is Some(input_execution) &&
    @execution.execution_capacity(
      retained,
      Int64::max(control_execution, input_execution),
    )
    is Some(capacity) else {
    return None
  }
  Some((capacity, idle))
}
