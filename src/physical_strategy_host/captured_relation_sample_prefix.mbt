///|
// Holds only the prefix and its existing boundary lease. The caller retains
// the actual output pin, admission and permission independently.
struct CapturedRelationSamplePrefix {
  boundary : CapturedTaskBoundary
  mut payload : (@encode.EncodedDocument, Int, Int)?
  mut resident : CapturedResidentGenerationPin?
}

///|
pub(all) enum CapturedRelationSamplePrefixIssue {
  NotSelected
  StartUnavailable
  AttemptUnavailable
  StaleOriginal
  AuthorityLost
  Work(@resources.LedgerIssue)
  Resident(RunIssue)
  InvalidLimits
  Boundary(CapturedTaskBoundaryIssue)
  Prefix(@execution.RelationSamplePrefixIssue)
}

///|
fn captured_sample_prefix_bytes(
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  guard @execution.completed_relation_sample_prefix_construction_bytes(
      schema, max_bytes, max_nodes, max_depth,
    )
    is Some(codec) else {
    return None
  }
  // Higher envelope and result/option, borrowed pin view, its amended
  // completion and live closure, original-current closure, and all original
  // port/plan lookup controls may coexist. The installed wrapper, origin and
  // later borrowed view add H5/R24/W6. The managed resident pin and its
  // exact completion/loan and authority checks add H15/R36/W16.
  // The shared work view and refusal state coexist with the two schema
  // writers and one per-column hash. No row copies are added.
  let wrapper = @execution.preparation_representation_cost({
    record_headers: 73L,
    reference_slots: 135L,
    scalar_words: 86L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  @execution.checked_preparation_add_product(
    captured_boundary_read_bytes + wrapper,
    codec,
    1L,
  )
}

///|
/// Record the existing Journal's acknowledged start on this Run's prepared
/// controller. The installed start receiver supplies the already authorized
/// original Definition, context and revision during the synchronous handoff.
pub fn acknowledge_captured_relation_sample_start(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  subject_cid : String,
  context_cid : String,
  revision : Int,
) -> Result[Unit, CapturedTaskControlIssue] {
  if run.stopped || hooks.closing {
    return Err(Stopped)
  }
  if !captured_control_owner_matches(run, hooks) {
    return Err(ForeignOwner)
  }
  guard hooks.control is Some(control) &&
    control.binding is Some(binding) &&
    hooks.original is Some(original) else {
    return Err(NotPrepared)
  }
  if control.changing || hooks.admitting_control {
    return Err(InProgress)
  }
  if binding.subject_cid != subject_cid || binding.context_cid != context_cid {
    return Err(AuthorizationMismatch)
  }
  if revision <= 0 {
    return Err(StaleRevision)
  }
  if control.sample_start_revision != 0 ||
    control.revision != 0 ||
    control.phase != Paused ||
    hooks.activation_grant is Some(_) ||
    hooks.before is Some(_) ||
    run.running is Some(_) ||
    run.generation != original.generation {
    return Err(AlreadyStarted)
  }
  control.sample_start_revision = revision
  Ok(())
}

///|
// Both materialized and managed completions debit the selected Run's existing
// planning owner. Preserve its typed refusal when a bounded sink stops.
fn encode_captured_relation_prefix(
  run : CapturedDAG,
  output : @execution.CompletedOutput,
  max_items : Int,
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  current : () -> Bool,
  pin_current : () -> Bool,
) -> Result[
  (@encode.EncodedDocument, Int, Int),
  CapturedRelationSamplePrefixIssue,
] {
  let refusal : Ref[@resources.LedgerIssue?] = Ref(None)
  let stale = Ref(false)
  let prefix = @execution.encode_completed_relation_sample_prefix(
    output,
    max_items,
    schema,
    max_bytes,
    max_nodes,
    max_depth,
    units => {
      match @resources.charge_planning(run.ledger, units) {
        Ok(_) => {
          let valid = pin_current()
          stale.val = !valid
          valid
        }
        Err(issue) => {
          refusal.val = Some(issue)
          false
        }
      }
    },
    original_current=current,
  )
  match refusal.val {
    Some(issue) => Err(Work(issue))
    None =>
      if stale.val {
        Err(StaleOriginal)
      } else {
        prefix.map_err(issue => Prefix(issue))
      }
  }
}

///|
/// Keep the actual original commit, pin and encoded prefix on the same Run.
/// The Host selects the Debug profile and supplies independent authority
/// before this internal borrow. The original attempt and Journal adoption
/// are separate from the successful construction of this prefix.
pub fn capture_captured_relation_sample_prefix(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
  pin : CapturedOutputPin,
  max_items : Int,
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedRelationSamplePrefix, CapturedRelationSamplePrefixIssue] {
  guard captured_task_output_pin_matches_committed_relation(run, source, pin) else {
    return Err(StaleOriginal)
  }
  let boundary = match
    fork_captured_relation_sample(
      run, source, max_items, schema, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // The exact coordinate was checked on this immutable graph before the
  // fork. Recheck the live pin and commit after reentry without rescanning
  // the graph on each encoder debit.
  let current = () => {
    captured_committed_relation_pin_current(run, boundary, pin)
  }
  if !current() {
    return_captured_task_boundary(boundary) |> ignore
    return Err(StaleOriginal)
  }
  let prefix = encode_captured_relation_prefix(
    run,
    captured_output_pin_materialized(pin),
    max_items,
    schema,
    max_bytes,
    max_nodes,
    max_depth,
    current,
    current,
  )
  match prefix {
    Err(issue) => {
      return_captured_task_boundary(boundary) |> ignore
      Err(issue)
    }
    Ok(payload) => Ok({ boundary, payload: Some(payload), resident: None, })
  }
}

///|
fn fork_captured_relation_sample(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
  max_items : Int,
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedTaskBoundary, CapturedRelationSamplePrefixIssue] {
  guard source.original is Some(original) else { return Err(StaleOriginal) }
  if original.forking || original.returning != 0 {
    return Err(Boundary(ReadInProgress))
  }
  guard original.hooks.control is Some(control) && control.binding is Some(_) else {
    return Err(NotSelected)
  }
  if control.sample_start_revision <= 0 {
    return Err(StartUnavailable)
  }
  if control.committed_attempt_sequence <= 0 {
    return Err(AttemptUnavailable)
  }
  guard max_items > 0 &&
    max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    captured_sample_prefix_bytes(schema, max_bytes, max_nodes, max_depth)
    is Some(bytes) else {
    return Err(InvalidLimits)
  }
  original.forking = true
  let result = acquire_captured_boundary_read(
    run,
    original.hooks,
    original.record,
    source.phase,
    bytes,
  )
  original.forking = false
  result.map_err(issue => Boundary(issue))
}

///|
/// Private post-commit supplier selection without opening an output or
/// acquiring Sample authority. Normal tasks have no selected receiver.
pub fn captured_relation_sample_start_selected(run : CapturedDAG) -> Bool {
  !run.stopped &&
  run.activation is Observed(hooks) &&
  !hooks.closing &&
  hooks.control is Some(control) &&
  control.sample_start_revision > 0 &&
  control.binding is Some(_)
}

///|
fn captured_managed_sample_pin_current(
  run : CapturedDAG,
  boundary : CapturedTaskBoundary,
  pin : CapturedResidentGenerationPin,
) -> Bool {
  guard pin.live &&
    physical_equal(run, pin.run) &&
    pin.task == boundary.task &&
    boundary.phase != Before &&
    captured_task_boundary_current(run, boundary) &&
    pin.reference is Managed(expected) &&
    run.outputs[pin.task] is Some(Managed(current)) else {
    return false
  }
  @execution.managed_completed_reference_same(expected, current)
}

///|
/// Accept only the live managed output that committed this original port and
/// the exact typed projection used by its fully ordered value receipt.
pub fn[T] capture_captured_managed_relation_sample_prefix(
  run : CapturedDAG,
  source : CapturedTaskBoundary,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  max_items : Int,
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  require_capture_current : () -> Bool,
) -> Result[CapturedRelationSamplePrefix, CapturedRelationSamplePrefixIssue] {
  let task = source.task
  guard source.phase != Before &&
    captured_task_boundary_current(run, source) &&
    captured_control_boundary_available(run.graph, task) &&
    captured_task_target(run, task) is Some(target) &&
    @execution.completed_has_cell_access(original) else {
    return Err(StaleOriginal)
  }
  let boundary = match
    fork_captured_relation_sample(
      run, source, max_items, schema, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let result = encode_captured_managed_relation_sample(
    run, boundary, completed, original, target, max_items, schema, max_bytes, max_nodes,
    max_depth, require_capture_current,
  )
  if result is Err(_) {
    return_captured_task_boundary(boundary) |> ignore
  }
  result
}

///|
fn[T] encode_captured_managed_relation_sample(
  run : CapturedDAG,
  boundary : CapturedTaskBoundary,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  target : @pipeline.Target,
  max_items : Int,
  schema : @execution.RelationSchemaIdentityLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  require_capture_current : () -> Bool,
) -> Result[CapturedRelationSamplePrefix, CapturedRelationSamplePrefixIssue] {
  let task = boundary.task
  guard @execution.managed_completed_output_original_occurrence(completed)
    is Some(occurrence) &&
    @execution.completed_output_occurrence_matches_original(
      occurrence, original,
    ) &&
    captured_managed_task_output_matches(run, task, target, completed) &&
    captured_task_boundary_current(run, boundary) else {
    return Err(StaleOriginal)
  }
  let pin = match acquire_captured_resident_generation_pin(run, task, 1) {
    Err(issue) => return Err(Resident(issue))
    Ok(value) => value
  }
  let denied = Ref(false)
  let result = encode_captured_relation_prefix(
    run,
    original,
    max_items,
    schema,
    max_bytes,
    max_nodes,
    max_depth,
    () => {
      if !require_capture_current() {
        denied.val = true
        false
      } else {
        captured_managed_sample_pin_current(run, boundary, pin)
      }
    },
    () => captured_managed_sample_pin_current(run, boundary, pin),
  )
  match result {
    Err(issue) => {
      release_captured_resident_generation_pin(pin) |> ignore
      Err(if denied.val { AuthorityLost } else { issue })
    }
    Ok(payload) =>
      Ok({ boundary, payload: Some(payload), resident: Some(pin), })
  }
}

///|
/// The lease owns the original resident pin; no caller-side Result export or
/// materialized-task pin can stand in for this managed generation.
pub fn captured_managed_relation_sample_prefix_current(
  run : CapturedDAG,
  value : CapturedRelationSamplePrefix,
) -> (@encode.EncodedDocument, Int, Int, Int, Int64, Int)? {
  guard value.resident is Some(pin) &&
    captured_managed_sample_pin_current(run, value.boundary, pin) &&
    value.boundary.original is Some(original) &&
    original.hooks.control is Some(control) &&
    control.committed_attempt_sequence > 0 &&
    control.sample_start_revision > 0 &&
    value.payload is Some((document, items, total)) else {
    return None
  }
  Some(
    (
      document,
      items,
      total,
      value.boundary.generation,
      control.committed_attempt_sequence.to_int64(),
      control.sample_start_revision,
    ),
  )
}

///|
/// Check the original prefix and pin without issuing a payload alias.
fn captured_relation_sample_prefix_available(
  run : CapturedDAG,
  value : CapturedRelationSamplePrefix,
  pin : CapturedOutputPin,
) -> Bool {
  value.payload is Some(_) &&
  captured_task_output_pin_matches_committed_relation(run, value.boundary, pin) &&
  value.boundary.original is Some(original) &&
  original.hooks.control is Some(control) &&
  control.binding is Some(_) &&
  control.committed_attempt_sequence > 0 &&
  control.sample_start_revision > 0
}

///|
/// Borrow the prefix and its commit generation, first-start revision and
/// attempt sequence. Consumer authorization and Journal adoption belong to
/// the Host. The consumer drops every alias before returning this capacity.
pub fn captured_relation_sample_prefix_current(
  run : CapturedDAG,
  value : CapturedRelationSamplePrefix,
  pin : CapturedOutputPin,
) -> (@encode.EncodedDocument, Int, Int, Int, Int64, Int)? {
  guard captured_relation_sample_prefix_available(run, value, pin) &&
    value.boundary.original is Some(original) &&
    original.hooks.control is Some(control) &&
    value.payload is Some((document, items, total)) else {
    return None
  }
  Some(
    (
      document,
      items,
      total,
      value.boundary.generation,
      control.committed_attempt_sequence.to_int64(),
      control.sample_start_revision,
    ),
  )
}

///|
/// Dispose of the owned bytes before returning their backing. The existing
/// Run keeps any pending return on its original list after failure.
pub fn return_captured_relation_sample_prefix(
  value : CapturedRelationSamplePrefix,
) -> Result[Unit, CapturedTaskBoundaryIssue] {
  value.payload = None
  if value.resident is Some(pin) {
    value.resident = None
    release_captured_resident_generation_pin(pin) |> ignore
  }
  return_captured_task_boundary(value.boundary)
}
