///|
pub struct ClientInstalledEffectOperationBorrow {
  priv mut original : ClientInstalledEffectOperationBorrow?
  priv mut owner : ClientInstalledManagedRun?
  priv mut ledger : @resources.Ledger?
  priv slot : Int
  priv member_index : Int
  priv mut extent : ClientInstalledEffectOperationExtent?
  // One original extent selection: owned input or detached successful output.
  priv mut input_selected : Bool
  priv mut construction_completed : Bool
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
  recovery_members? : Int = 0,
) -> @execution.ExecutionCapacity? {
  if children < 0 || recovery_members < 0 {
    return None
  }
  // The same-Run recovered input adds1H8R4W and one Run reference. Its
  // retirement method/context adds2H7R. One active stage borrow has2H4R
  // returned holders, release/status method pairs4H14R, and one returned
  // word. Body payloads remain on their original constructor tokens.
  // The original child vector has ONE entry per actual installed member,
  // independent of rows, future operation count or Host policy ceilings.
  guard @shape.collection_construction_extent({
      records: 11L,
      record_references: 36L,
      record_words: 5L,
      reference_arrays: 1L,
      reference_items: recovery_members.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: recovery_members.to_int64(),
    })
    is Some(recovery) else {
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
      // Optional owned output retains one wire callback frame and its
      // original method/output references; the wire DATA has its own extent.
      // Same-token staged input retains one grow method/context pair.
      records: (27L + 2L) * calls,
      // One original response-projection completion method is retained by
      // the physical child; its existing preparation latch owns the flight.
      // Optional same-response preflight object and its two original methods,
      // plus the installing original field, remain with this physical child.
      record_references: (64L + 3L + 2L + 4L + 1L + 8L + 4L) * calls,
      record_words: (12L + 2L + 3L + 2L) * calls,
      // Deferred member construction retains one original preparation-method
      // vector. Its length is bounded by these same checked child slots.
      reference_arrays: 3L * calls + 1L,
      reference_items: 15L * calls + count,
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
  // One Grant-only closure/context (2H9R), held Option/Int64 (1H1R1W).
  let retained : @execution.PreparationRepresentationUnits = {
    // Optional Host input tuple/Some and its retained opaque capacity. Wire
    // text remains with the already-funded original Preview producer.
    // One same-Run optional actual-row inventory adds its field and one Some
    // carrier at most, independently of how many operation bodies are live.
    // The request and footprint selectors each add one method/context pair
    // and a fixed original-coordinate call vector (4H14R3W each). The optional frame retains one
    // tuple/Some and the existing child reference, never another body owner.
    record_headers: 13L +
    8L +
    shared.record_headers +
    11L * count +
    69L +
    4L +
    recovery.record_headers,
    reference_slots: 22L +
    28L +
    slots +
    shared.reference_slots +
    17L * count +
    269L +
    4L +
    recovery.reference_slots,
    // The active codec retains its separately charged original output bound.
    scalar_words: 27L +
    6L +
    shared.scalar_words +
    29L * count +
    4L +
    recovery.scalar_words,
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
    construction_completed: false,
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
    (Some(before), Some(after)) if physical_equal(before, after) =>
      match before.constructor_frame {
        Some((_, Some(child))) =>
          check_installed_effect_request_projection_original(
            child, owner, ledger, preparation,
          )
        _ => Ok(())
      }
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
        constructor_frame: None,
        ledger_codec_active: false,
        ledger_codec_workspace: 0L,
        ledger_codec_retained: 0L,
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
  resize_installed_effect_operation_input(value, input, false)
}

///|
/// Continue the SAME synchronous constructor after its funded input preflight.
/// This can only grow its original selected backing inside its immutable Plan
/// maximum. It grants no operation, physical attempt, transfer or authority.
pub fn grow_installed_effect_operation_input(
  value : ClientInstalledEffectOperationBorrow,
  input : ClientInstalledEffectOperationExtent,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_input(value, input, true)
}

///|
fn resize_installed_effect_operation_input(
  value : ClientInstalledEffectOperationBorrow,
  input : ClientInstalledEffectOperationExtent,
  growing : Bool,
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
  if value.input_selected != growing ||
    owner.effect_operation_opening ||
    owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  if growing {
    if value.construction_completed {
      return Err(AlreadyBound)
    }
    guard value.started &&
      backing is @resources.NodeManagedRunOperationBacking::Construction(_) else {
      return Err(Unsupported)
    }
  }
  if input.operation != extent.operation ||
    input.physical_attempt != extent.physical_attempt ||
    input.transfer_bytes != extent.transfer_bytes ||
    (extent.physical_attempt && !value.started) ||
    (!extent.physical_attempt && value.started && !growing) {
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
        @execution.execution_capacity_retained_bytes(input.capacity) &&
        (
          !growing ||
          value.execution_limit <=
          @execution.execution_capacity_execution_bytes(input.capacity)
        )
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
/// The selected physical response callback and its same original flight have
/// completed. Retain the complete input/output backing and all cleanup duties;
/// only the private decode/projection workspace returns. Repeating this
/// absolute disposal cannot create another input, attempt or operation slot.
pub fn complete_installed_effect_operation_response_projection(
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
  guard backing is @resources.NodeManagedRunOperationBacking::Physical(_) &&
    value.started &&
    value.input_selected else {
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
  defer {
    owner.effect_operation_opening = false
  }
  @resources.complete_prepared_run_operation_response_projection(
    admission,
    plan,
    ledger,
    () => {
      check_installed_effect_operation_backing_original(
        value, owner, ledger, preparation, backing,
      )
    },
    backing,
  ).map_err(installed_effect_operation_reservation_issue)
}

///|
/// Retain the original request/output after its synchronous constructor has
/// completed. The existing Host supplies this boundary only after the actual
/// callback and its current/reentry fence, never for the capture placeholder,
/// an asynchronous/failed constructor, a physical operation or cleanup ACK.
pub fn complete_installed_effect_operation_construction(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  complete_installed_effect_operation_construction_owned(value, None, true)
}

///|
/// A synchronous phase has returned and dropped its private scratch. Keep all
/// retained inputs/outputs and the SAME staged constructor/coordinate open.
/// A later phase must grow this original again BEFORE its callback. This is
/// not final output completion, a work refund or physical cleanup evidence.
pub fn yield_installed_effect_operation_construction_workspace(
  value : ClientInstalledEffectOperationBorrow,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  complete_installed_effect_operation_construction_owned(value, None, false)
}

///|
/// The owned child has returned its SAME detached immutable output and its
/// original physical release has acknowledged close. Borrow its existing
/// canonical wire for bounded retained-tree DATA; do not parse, serialize,
/// dispatch or infer cleanup from a size. This consumes the existing extent
/// selection latch once, leaving the immutable Plan ceiling unchanged.
pub fn complete_installed_effect_operation_construction_output(
  value : ClientInstalledEffectOperationBorrow,
  wire : String,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  complete_installed_effect_operation_construction_owned(
    value,
    Some(wire),
    true,
  )
}

///|
fn complete_installed_effect_operation_construction_owned(
  value : ClientInstalledEffectOperationBorrow,
  output_wire : String?,
  finished : Bool,
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
  if !finished {
    guard value.extent is Some(extent) &&
      extent.maximum is Some(_) &&
      value.input_selected &&
      !value.construction_completed else {
      return Err(Unsupported)
    }
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) else {
    return Err(Retired)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  let output_retained = match output_wire {
    None => None
    Some(wire) => {
      guard value.extent is Some(extent) && !extent.physical_attempt else {
        return Err(Unsupported)
      }
      // A staged constructor has already selected its SAME original input.
      // Completion consumes a separate final-output latch, never that input
      // again. The Resource owner below also checks the live retained backing.
      let upper = match extent.maximum {
        Some(maximum) => {
          if value.construction_completed {
            return Err(AlreadyBound)
          }
          if !value.input_selected {
            return Err(Unsupported)
          }
          @execution.execution_capacity_retained_bytes(maximum.capacity)
        }
        None => {
          if value.input_selected {
            return Err(AlreadyBound)
          }
          @execution.execution_capacity_retained_bytes(extent.capacity)
        }
      }
      let bound = Int64::min(upper, 2147483647L).to_int()
      let bytes = match @scalar.admit_utf8_length(wire, bound) {
        Err(_) => return Err(InsufficientCapacity)
        Ok(bytes) => bytes
      }
      // Every JSON value node and open container costs at least one wire
      // byte. The original native wire is already canonical/validated; this
      // conservative DATA bound needs no second parser or content traversal.
      guard bytes > 0 &&
        local_file_store_json_capacity(bytes, bytes, bytes) is Some(output) &&
        @execution.execution_capacity_retained_bytes(output) <= upper else {
        return Err(InsufficientCapacity)
      }
      Some(@execution.execution_capacity_retained_bytes(output))
    }
  }
  owner.effect_operation_opening = true
  let original = () => {
    check_installed_effect_construction_original(
      value, owner, ledger, preparation, backing,
    )
  }
  let result = match output_retained {
    None =>
      @resources.complete_prepared_run_operation_construction(
        admission, plan, ledger, original, backing,
      )
    Some(retained) =>
      @resources.complete_prepared_run_operation_construction_output(
        admission, plan, ledger, original, backing, retained,
      )
  }
  let result = result.map_err(installed_effect_operation_reservation_issue)
  owner.effect_operation_opening = false
  if result is Ok(_) {
    if finished {
      value.construction_completed = true
    }
    if output_retained is Some(_) {
      value.input_selected = true
    }
  }
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
/// The existing Site issuer still validates the original decision and signs
/// the Grant. Only its constructor scratch is selected here, on the SAME
/// current Run/control token; no Receipt or provider callback enters this port.
pub fn begin_installed_effect_operation_grant_construction(
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
    grant_construction=true,
  )
}

///|
/// Project the SAME completed original request into its Host facts. Resolve
/// its spent coordinate to the original live child; neither callback arguments
/// nor Host quantities can replace the selected constructor demand. All
/// retained control outputs remain charged beside that child's native output.
pub fn begin_installed_effect_operation_request_projection(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  member_index : Int,
  operation_index : Int,
  row_index : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    true,
    request_projection=Some((member_index, operation_index, row_index)),
  )
}

///|
/// Select only the SAME Plan member's declared scratch-only opaque boundary
/// footprint constructor. No Host quantity, callback, Grant or new child is
/// accepted. Full original control retention/current/cleanup stays unchanged.
pub fn begin_installed_effect_operation_footprint_construction(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  member_index : Int,
  operation_index : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  resize_installed_effect_operation_control_construction(
    owner,
    prepared,
    request,
    plan,
    true,
    footprint_construction=Some((member_index, operation_index)),
  )
}

///|
// Called after the original Resource current, including on completion and
// other same-owner observations of a live/failed projection frame.
fn check_installed_effect_request_projection_original(
  child : ClientInstalledEffectOperationBorrow,
  owner : ClientInstalledManagedRun,
  ledger : @resources.Ledger,
  preparation : ClientInstalledManagedRunOriginal,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard child.original is Some(original) && physical_equal(original, child) else {
    return Err(ForeignOriginal)
  }
  guard !child.retired && child.backing is Some(backing) else {
    return Err(Retired)
  }
  if !child.started || !child.construction_completed {
    return Err(Unsupported)
  }
  check_installed_effect_construction_original(
    child, owner, ledger, preparation, backing,
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
  grant_construction? : Bool = false,
  request_projection? : (Int, Int, Int)? = None,
  footprint_construction? : (Int, Int)? = None,
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
        input_wire is Some(_) ||
        control.constructor_frame is Some(_) {
        return Err(AlreadyBound)
      }
  }
  let (codec_workspace, codec_retained) = match ledger_codec {
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
        is Some(codec) else {
        return Err(Unsupported)
      }
      (
        @execution.execution_capacity_execution_bytes(codec) -
        @execution.execution_capacity_retained_bytes(codec),
        @execution.execution_capacity_retained_bytes(codec),
      )
    }
    _ => (0L, 0L)
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
  let constructor_frame = if request_projection
    is Some((member_index, operation, row)) {
    if !active ||
      footprint_construction is Some(_) ||
      grant_construction ||
      input_wire is Some(_) ||
      ledger_codec is Some(_) {
      return Err(Unsupported)
    }
    let coordinate : ClientEffectOperationCoordinate = {
      member_index,
      per_row: true,
      operation_index: operation,
      row_index: row,
      lookup_probes: None,
    }
    guard control.coordinates.get(coordinate) is Some(slot) &&
      owner.effect_operations.get(slot) is Some(Some(child)) &&
      child.extent is Some(extent) &&
      !extent.physical_attempt &&
      child.execution_limit >=
      @execution.execution_capacity_retained_bytes(extent.capacity) else {
      return refuse_installed_effect_operation_after_current(
        owner,
        prepared,
        request,
        ForeignOriginal,
      ).map(_ => ())
    }
    match
      check_installed_effect_request_projection_original(
        child, owner, ledger, preparation,
      ) {
      Err(issue) =>
        return refuse_installed_effect_operation_after_current(
          owner, prepared, request, issue,
        ).map(_ => ())
      Ok(_) => ()
    }
    // This exact constructor already supplies native export, JSON output and
    // canonical comparison scratch. Its completed native/Host outputs stay
    // retained separately. Preserve the whole selected private envelope,
    // including a staged constructor's original retained floor.
    Some(
      (
        child.execution_limit -
        @execution.execution_capacity_retained_bytes(extent.capacity),
        Some(child),
      ),
    )
  } else if footprint_construction is Some((member_index, operation_index)) {
    if !active ||
      grant_construction ||
      input_wire is Some(_) ||
      ledger_codec is Some(_) {
      return Err(Unsupported)
    }
    guard plan.operations.get(member_index) is Some(demand) &&
      demand.member_extents.get(operation_index) is Some(extent) &&
      extent.operation.has_suffix(".footprint") &&
      !extent.physical_attempt &&
      extent.transfer_bytes == 0L &&
      extent.maximum is None &&
      extent.checked_row_capacity is None &&
      extent.checked_effect_id_capacity is None &&
      extent.host_input_limits is None &&
      @execution.execution_capacity_retained_bytes(extent.capacity) == 0L else {
      return refuse_installed_effect_operation_after_current(
        owner,
        prepared,
        request,
        ForeignOriginal,
      ).map(_ => ())
    }
    Some((@execution.execution_capacity_execution_bytes(extent.capacity), None))
  } else if grant_construction {
    if !active || input_wire is Some(_) || ledger_codec is Some(_) {
      return Err(Unsupported)
    }
    guard standard_create_grant_capacity() is Some(grant) else {
      return Err(Unsupported)
    }
    Some(
      (
        @execution.execution_capacity_execution_bytes(grant) -
        @execution.execution_capacity_retained_bytes(grant),
        None,
      ),
    )
  } else if input is Some((_, host)) {
    // This exact producer-owned Preview wire has its complete forest and
    // decoder workspace quoted above from the SAME Plan's member limits.
    // JSON.parse does not reconstruct Catalog/metadata or execute the full
    // recipe. Select its existing scratch on this SAME control frame; the
    // capacity combiner below still funds the whole original retained/idle
    // floor plus host retention and the complete input execution demand.
    if !active || ledger_codec is Some(_) {
      return Err(Unsupported)
    }
    Some(
      (
        @execution.execution_capacity_execution_bytes(host) -
        @execution.execution_capacity_retained_bytes(host),
        None,
      ),
    )
  } else if ledger_codec is Some(_) {
    control.constructor_frame
  } else {
    None
  }
  guard installed_effect_control_capacity(
      Some(control),
      plan,
      input~,
      constructor_frame=Some(constructor_frame),
      codec_workspace=Some(codec_workspace),
      codec_retained=Some(codec_retained),
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
      match
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        ) {
        Err(issue) => Err(issue)
        Ok(_) =>
          match constructor_frame {
            Some((_, Some(child))) =>
              check_installed_effect_request_projection_original(
                child, owner, ledger, preparation,
              )
            _ => Ok(())
          }
      }
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
          control.ledger_codec_retained = codec_retained
        }
        None => {
          control.construction_active = active
          control.constructor_frame = constructor_frame
        }
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
  guard installed_effect_operation_control_capacity(
      children.to_int(),
      recovery_members=plan.operations.length(),
    )
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
  retain_installed_effect_control_row_inventory(
    owner,
    preparation,
    admission,
    plan,
    ledger,
    control,
    rows,
    () => {
      guard owner.source_free_captured is Some(original) &&
        physical_equal(original, captured) &&
        @strategy.captured_effect_inputs_match_captured_run(inputs, captured) &&
        @strategy.captured_effect_inputs_retained(inputs) else {
        return Err(ForeignOriginal)
      }
      Ok(())
    },
  )
}

///|
/// Cold recovery already owns an admitted immutable Preview and its original
/// compiled Run. Read that inventory, never reparse the wire or accept a Host
/// row count, before the same Run constructs recovered member requests.
pub fn retain_installed_effect_recovered_input_inventory(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  preview : @publication.EffectPreviewIdentity,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(AlreadyBound)
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    physical_equal(plan, expected_plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  let bound = match
    @publication_host.bind_client_effect_compiled_run(
      prepared, allowed, definition,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  if plan.query_time is Some(time) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound, time, request,
    ) {
    return Err(ForeignOriginal)
  }
  if @publication.check_effect_preview_run_binding(
      @publication_host.client_effect_allowed_run_admission(allowed),
      definition,
      invocation,
      preview,
    )
    is Err(_) ||
    @publication.effect_preview_member_count(preview) !=
    plan.operations.length() {
    return Err(ForeignOriginal)
  }
  let mut rows = 0
  for member_index in 0..<plan.operations.length() {
    if @publication.effect_preview_member_effect_id(preview, member_index) !=
      Some(plan.operations[member_index].effect_id) {
      return Err(ForeignOriginal)
    }
    guard @publication.effect_preview_row_count(preview, member_index)
      is Some(count) &&
      count <= plan.rows else {
      return Err(InsufficientCapacity)
    }
    rows = Int::max(rows, count)
  }
  // A live capture may already back a larger input than its selected changes.
  // Keep that original inventory and reservation; recovery never shrinks it.
  if plan.closed_rows is Some(_) || control.captured_rows is Some(_) {
    if control.captured_rows is Some(original) && rows > original {
      return Err(ForeignOriginal)
    }
    return check_installed_effect_operation_original(
      owner,
      ledger,
      preparation,
      Some(control),
    )
  }
  retain_installed_effect_control_row_inventory(
    owner,
    preparation,
    admission,
    plan,
    ledger,
    control,
    rows,
    () => Ok(()),
  )
}

///|
// Warm capture and cold Preview use this SAME existing reservation/fold. Only
// the original inventory witness differs; consumed work is never refunded.
fn retain_installed_effect_control_row_inventory(
  owner : ClientInstalledManagedRun,
  preparation : ClientInstalledManagedRunOriginal,
  admission : @resources.PreparedRunAdmission[ClientInstalledEffectManagedPlan],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
  control : ClientEffectOperationControls,
  rows : Int,
  check_inventory : () -> Result[Unit, ClientInstalledManagedRunIssue],
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  if rows < 0 || rows > plan.rows {
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
      check_inventory()
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
  codec_retained? : Int64? = None,
  constructor_frame? : (Int64, ClientInstalledEffectOperationBorrow?)?? = None,
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
  let codec_retained = codec_retained.unwrap_or(
    match control {
      Some(value) => value.ledger_codec_retained
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
  // A failed/active constructor keeps its exact scratch on same-owner current
  // paths. Only explicit successful completion returns it. Every original
  // retained output and the fixed current/quantity frame remain charged.
  let constructor_frame = constructor_frame.unwrap_or(
    control.bind(value => value.constructor_frame),
  )
  let base_execution = match constructor_frame {
    None => @execution.execution_capacity_execution_bytes(base)
    Some((workspace, _)) => {
      guard workspace >= 0L &&
        @execution.checked_preparation_add_product(base_retained, workspace, 1L)
        is Some(execution) else {
        return None
      }
      Int64::max(base_idle, execution)
    }
  }
  // The next actual wire's decoder coexists with these original controls.
  // Its retained tree/output and scratch are additional demand on the SAME
  // reservation, not limited by an initial zero-row quote. A finite parent
  // must admit the complete sum before decoding. Host input stays separate.
  if codec_retained < 0L {
    return None
  }
  guard @execution.checked_preparation_add_product(
      base_retained, codec_retained, 1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, codec_workspace, 1L)
    is Some(codec_execution) &&
    @execution.execution_capacity(
      retained,
      Int64::max(base_execution, codec_execution),
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
