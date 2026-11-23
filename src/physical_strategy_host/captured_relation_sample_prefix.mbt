///|
// Holds only the prefix and its existing boundary lease. The caller retains
// the actual output pin, admission and permission independently.
struct CapturedRelationSamplePrefix {
  boundary : CapturedTaskBoundary
  mut payload : (@encode.EncodedDocument, Int, Int)?
}

///|
pub(all) enum CapturedRelationSamplePrefixIssue {
  NotSelected
  StartUnavailable
  AttemptUnavailable
  StaleOriginal
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
  // port/plan lookup controls may coexist. No row or CID copies are added here.
  let wrapper = @execution.preparation_representation_cost({
    record_headers: 48L,
    reference_slots: 64L,
    scalar_words: 58L,
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
  guard source.original is Some(original) else { return Err(StaleOriginal) }
  if original.forking || original.returning != 0 {
    return Err(Boundary(ReadInProgress))
  }
  guard original.hooks.control is Some(control) && control.binding is Some(_) else {
    return Err(NotSelected)
  }
  guard captured_task_output_pin_matches_committed_relation(run, source, pin) else {
    return Err(StaleOriginal)
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
  let capacity = acquire_captured_boundary_read(
    run,
    original.hooks,
    original.record,
    source.phase,
    bytes,
  )
  original.forking = false
  let boundary = match capacity {
    Err(issue) => return Err(Boundary(issue))
    Ok(value) => value
  }
  if !captured_task_output_pin_matches_committed_relation(run, boundary, pin) {
    return_captured_task_boundary(boundary) |> ignore
    return Err(StaleOriginal)
  }
  let prefix = @execution.encode_completed_relation_sample_prefix(
    captured_output_pin_materialized(pin),
    max_items,
    schema,
    max_bytes,
    max_nodes,
    max_depth,
    original_current=() => {
      captured_task_output_pin_matches_committed_relation(run, boundary, pin)
    },
  )
  match prefix {
    Err(issue) => {
      return_captured_task_boundary(boundary) |> ignore
      Err(Prefix(issue))
    }
    Ok(payload) => Ok({ boundary, payload: Some(payload), })
  }
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
  guard captured_task_output_pin_matches_committed_relation(
      run,
      value.boundary,
      pin,
    ) &&
    value.boundary.original is Some(original) &&
    original.hooks.control is Some(control) &&
    control.binding is Some(_) &&
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
/// Dispose of the owned bytes before returning their backing. The existing
/// Run keeps any pending return on its original list after failure.
pub fn return_captured_relation_sample_prefix(
  value : CapturedRelationSamplePrefix,
) -> Result[Unit, CapturedTaskBoundaryIssue] {
  value.payload = None
  return_captured_task_boundary(value.boundary)
}
