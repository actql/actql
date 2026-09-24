///|
/// One checked Effect source occurrence and its exact captured output. The
/// ordinary task port may close while this owner is live. Resident material
/// remains with the installed Host; this neither copies rows nor permits apply.
struct CapturedEffectInput {
  source : CheckedEffectSourcePort
  borrow : CapturedAnyResultBorrow
}

///|
/// One Effect Run's complete source inventory. Members without a Result
/// source retain their position but require no pin. The source inventory is
/// derived from the checked graph, never supplied by a caller.
struct CapturedEffectInputs {
  run : CapturedEffectRunDAG
  entries : Array[CapturedEffectInput?]
  pins : CapturedAnyResultOutputSet
  mut live : Bool
}

///|
/// A checked private Preview paired with the live captured inputs of its
/// exact Run. Preview order is mapped back to authored Effect occurrences.
/// This is input custody, not Artifact evidence or mutation authority.
struct CapturedEffectPreviewInputs {
  preview : @checked.EffectProgramRunPreview
  inputs : CapturedEffectInputs
  source_indexes : Array[Int?]
}

///|
/// Pin all Result-consuming members as one custody step. A later missing,
/// foreign, or over-limit source cannot strand earlier consumer holdings.
pub fn pin_captured_effect_sources(
  run : CapturedEffectRunDAG,
  max_pins : Int,
) -> Result[CapturedEffectInputs, RunIssue] {
  let requests : Array[(Int, @execution.ManagedResultOccurrence)] = []
  let sources : Array[CheckedEffectSourcePort?] = []
  for index in 0..<captured_effect_run_source_count(run) {
    let source = captured_effect_run_source_at(run, index)
    if source is Some(source) {
      if source.member_index != index {
        return Err(ForeignCandidate)
      }
      requests.push((source.task, source.occurrence))
    }
    sources.push(source)
  }
  let pins = match
    pin_captured_any_result_output_set(run.captured, requests, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries : Array[CapturedEffectInput?] = []
  let mut pin_index = 0
  for source in sources {
    match source {
      Some(source) => {
        let borrow = captured_any_result_output_set_borrow_at(pins, pin_index).unwrap()
        entries.push(Some({ source, borrow, }))
        pin_index += 1
      }
      None => entries.push(None)
    }
  }
  Ok({ run, entries, pins, live: true, })
}

///|
/// Resolve Preview members to the checked source inventory without accepting
/// a caller-supplied index or matching equal-CID but foreign Run owners.
pub fn checked_effect_preview_source_indexes(
  run : CheckedEffectRunDAG,
  preview : @checked.EffectProgramRunPreview,
  max_work : Int,
) -> Result[Array[Int?], RunIssue] {
  if max_work < 0 {
    return Err(PreviewWorkLimit)
  }
  if !physical_equal(
      run.run,
      @checked.effect_program_run_preview_owner(preview),
    ) {
    return Err(ForeignCandidate)
  }
  let stage = @checked.effect_program_run_preview_stage(preview)
  let identity = @checked.effect_program_run_preview_identity(preview)
  let headers = @checked.effect_program_static_headers(
    @checked.effect_program_run_static_candidate(run.run),
  )
  let mut remaining = max_work
  let member_indexes : Map[String, Int] = Map([])
  for index in 0..<@syntax.effect_header_count(headers) {
    if remaining == 0 {
      return Err(PreviewWorkLimit)
    }
    remaining -= 1
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == stage {
      member_indexes[@syntax.effect_header_id(header)] = index
    }
  }
  let indexes : Array[Int?] = []
  for preview_index in 0..<@publication.effect_preview_member_count(identity) {
    if remaining == 0 {
      return Err(PreviewWorkLimit)
    }
    remaining -= 1
    let id = @publication.effect_preview_member_effect_id(
      identity, preview_index,
    ).unwrap()
    guard member_indexes.get(id) is Some(index) else {
      return Err(ForeignCandidate)
    }
    let source = run.computation.sources.get(index).bind(value => value)
    let expected = @publication.effect_preview_member_source_result(
      identity, preview_index,
    )
    match source {
      Some(source) => {
        if expected !=
          Some(@execution.managed_result_occurrence_name(source.occurrence)) {
          return Err(ForeignCandidate)
        }
        indexes.push(Some(index))
      }
      None => {
        if expected is Some(_) {
          return Err(ForeignCandidate)
        }
        indexes.push(None)
      }
    }
  }
  Ok(indexes)
}

///|
/// Bind a private Preview to the already pinned inputs of the same captured
/// Run. A missing or revoked physical input cannot become Preview custody.
pub fn bind_captured_effect_preview_inputs(
  run : CapturedEffectRunDAG,
  inputs : CapturedEffectInputs,
  preview : @checked.EffectProgramRunPreview,
  max_work : Int,
) -> Result[CapturedEffectPreviewInputs, RunIssue] {
  if !physical_equal(inputs.run, run) {
    return Err(ForeignCandidate)
  }
  if !inputs.live {
    return Err(NotReady)
  }
  let indexes = match
    checked_effect_preview_source_indexes(inputs.run.checked, preview, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for index in indexes {
    if index is Some(index) {
      guard inputs.entries.get(index).bind(value => value) is Some(input) &&
        captured_any_result_borrow_available(input.borrow) else {
        return Err(NotReady)
      }
    }
  }
  Ok({ preview, inputs, source_indexes: indexes, })
}

///|
pub fn captured_effect_preview_owner(
  value : CapturedEffectPreviewInputs,
) -> @checked.EffectProgramRunPreview {
  value.preview
}

///|
pub fn captured_effect_preview_input_at(
  value : CapturedEffectPreviewInputs,
  preview_index : Int,
) -> CapturedEffectInput? {
  if !value.inputs.live {
    return None
  }
  let input = value.source_indexes
    .get(preview_index)
    .bind(index => {
      index.bind(index => value.inputs.entries.get(index).bind(entry => entry))
    })
  input.bind(input => {
    if captured_any_result_borrow_available(input.borrow) {
      Some(input)
    } else {
      None
    }
  })
}

///|
pub(all) enum CapturedEffectPlanIssue {
  InvalidMember
  NotReady
  ForeignBinding
  Plan(@results.EffectPlanBindingIssue)
} derive(Debug)

///|
/// Recover the checked Plan for a Preview member from the same captured Run
/// that owns its pinned Result. The caller cannot substitute a rule, Result
/// name, or physical producer. Row evaluation and apply remain separate.
pub fn captured_effect_preview_plan_terminal(
  value : CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[@results.EffectPlanTerminal?, CapturedEffectPlanIssue] {
  if !value.inputs.live {
    return Err(NotReady)
  }
  if max_fields < 0 || max_work < 0 {
    return Err(Plan(@results.EffectPlanBindingIssue::InvalidLimits))
  }
  guard value.source_indexes.get(preview_index) is Some(source_index) else {
    return Err(InvalidMember)
  }
  guard source_index is Some(member_index) else { return Ok(None) }
  guard captured_effect_preview_input_at(value, preview_index) is Some(input) else {
    return Err(NotReady)
  }
  let static_candidate = @checked.effect_program_run_static_candidate(
    value.inputs.run.checked.run,
  )
  let effects = @checked.effect_program_static_effects(static_candidate)
  guard @results.effect_result_binding_at(
      @results.effect_static_candidate_results(effects),
      member_index,
    )
    is Some(binding) &&
    input.source.member_index == member_index else {
    return Err(ForeignBinding)
  }
  if @syntax.effect_header_kind(@results.effect_result_binding_header(binding)) ==
    "command" {
    return Ok(None)
  }
  let rules = @results.effect_static_candidate_mapping_rules(effects)
  let terminal = match
    @results.effect_plan_terminal_for_member(
      rules, member_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  if terminal is Some(terminal) &&
    @results.effect_plan_terminal_source_result(terminal) !=
    @execution.managed_result_occurrence_name(input.source.occurrence) {
    return Err(ForeignBinding)
  }
  Ok(terminal)
}

///|
pub(all) enum CapturedEffectGuardIssue {
  InvalidLimits
  NotReady
  Current(@effect.EffectPreviewTargetGuardIssue)
} derive(Debug)

///|
/// Check all current target guards while every required checked input remains
/// pinned. The caller must obtain observations under current Site authority.
/// This preflight is not a mutation permit or evidence of payload equality.
pub fn check_captured_effect_preview_target_guards(
  value : CapturedEffectPreviewInputs,
  observations : Array[@effect.EffectTargetVersionObservation],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectGuardIssue] {
  if max_rows < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if !value.inputs.live {
    return Err(NotReady)
  }
  for index in 0..<value.source_indexes.length() {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return Err(NotReady)
    }
  }
  @effect.check_effect_preview_target_guards(
    @checked.effect_program_run_preview_identity(value.preview),
    observations,
    max_rows,
    max_work,
  ).map_err(issue => Current(issue))
}

///|
pub(all) enum CapturedEffectCurrentBindingIssue {
  InvalidLimits
  CapacityExceeded
  NotReady
  InventoryMismatch
  ForeignSource(Int)
  ForeignContract(Int)
  ForeignCapability(Int)
  ForeignAuthority(Int)
} derive(Debug)

///|
/// Compare all currently observed source, resolved Contract, capability, and
/// authority bindings against the same private Preview and captured input.
/// The Site must establish current observations under authenticated authority;
/// matching caller-supplied CIDs alone never grant an apply permit.
pub fn check_captured_effect_preview_current_bindings(
  value : CapturedEffectPreviewInputs,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectCurrentBindingIssue] {
  if max_members < 1 || max_members > 1000 || max_work < 1 {
    return Err(InvalidLimits)
  }
  if !value.inputs.live {
    return Err(NotReady)
  }
  let identity = @checked.effect_program_run_preview_identity(value.preview)
  let count = @publication.effect_preview_member_count(identity)
  if count < 1 ||
    count > max_members ||
    source_binding_cids.length() != count ||
    resolved_contract_cids.length() != count ||
    capability_evidence_cids.length() != count ||
    authority_scope_cids.length() != count {
    return Err(InventoryMismatch)
  }
  if count > max_work / 4 {
    return Err(CapacityExceeded)
  }
  for index in 0..<count {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return Err(NotReady)
    }
    if @publication.effect_preview_member_source_binding_cid(identity, index) !=
      Some(source_binding_cids[index]) {
      return Err(ForeignSource(index))
    }
    if @publication.effect_preview_member_resolved_contract_cid(identity, index) !=
      Some(resolved_contract_cids[index]) {
      return Err(ForeignContract(index))
    }
    if @publication.effect_preview_member_capability_evidence_cid(
        identity, index,
      ) !=
      Some(capability_evidence_cids[index]) {
      return Err(ForeignCapability(index))
    }
    if @publication.effect_preview_member_authority_scope_cid(identity, index) !=
      Some(authority_scope_cids[index]) {
      return Err(ForeignAuthority(index))
    }
  }
  Ok(())
}

///|
pub fn release_captured_effect_preview_inputs(
  value : CapturedEffectPreviewInputs,
) -> Bool {
  release_captured_effect_inputs(value.inputs)
}

///|
pub fn captured_effect_inputs_count(value : CapturedEffectInputs) -> Int {
  value.entries.length()
}

///|
/// Revoke the ordinary output port only while this checked Effect consumer
/// already owns its pin. The caller cannot close a producer merely by naming
/// a task or member before custody has been acquired.
pub fn close_captured_effect_source_port(
  value : CapturedEffectInputs,
  member_index : Int,
) -> Bool {
  if !value.live {
    return false
  }
  guard value.entries.get(member_index).bind(entry => entry) is Some(input) &&
    captured_any_result_borrow_available(input.borrow) else {
    return false
  }
  close_captured_task_output(value.run.captured, input.source.task)
  true
}

///|
pub fn captured_effect_input_at(
  value : CapturedEffectInputs,
  member_index : Int,
) -> CapturedEffectInput? {
  if !value.live {
    return None
  }
  value.entries
  .get(member_index)
  .bind(entry => entry)
  .bind(input => {
    if captured_any_result_borrow_available(input.borrow) {
      Some(input)
    } else {
      None
    }
  })
}

///|
/// Revoke every consumer alias. Already returned input aliases share the
/// underlying pins and become unavailable after this release.
pub fn release_captured_effect_inputs(value : CapturedEffectInputs) -> Bool {
  if !value.live {
    return false
  }
  value.live = false
  release_captured_any_result_output_set(value.pins) |> ignore
  true
}

///|
/// Capture only the source retained by this checked Effect Run. An authored
/// name or caller-supplied output cannot replace its checked Stage Result port.
/// A resident output can be pinned here, but its concrete representation and
/// checked Result view must still be supplied before any Effect payload exists.
pub fn pin_captured_effect_source(
  run : CapturedEffectRunDAG,
  member_index : Int,
  max_pins : Int,
) -> Result[CapturedEffectInput, RunIssue] {
  guard captured_effect_run_source_at(run, member_index) is Some(source) &&
    source.member_index == member_index else {
    return Err(ForeignCandidate)
  }
  let borrow = match
    borrow_captured_any_result_output(
      run.captured,
      source.task,
      source.occurrence,
      max_pins,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, borrow, })
}

///|
pub fn captured_effect_input_member_index(value : CapturedEffectInput) -> Int {
  value.source.member_index
}

///|
/// The producer Task selected by the checked graph expansion. The logical
/// Stage remains on the source occurrence and must not index physical output.
pub fn captured_effect_input_task(value : CapturedEffectInput) -> Int {
  value.source.task
}

///|
/// The checked occurrence retains its authored Result projection and order.
pub fn captured_effect_input_occurrence(
  value : CapturedEffectInput,
) -> @execution.ManagedResultOccurrence {
  captured_any_result_borrow_occurrence(value.borrow)
}

///|
/// The borrowed producer is live only while both the original completion and
/// this Effect input pin remain live. Projection is applied by the Result view
/// preparation, not by returning a caller-defined table here.
pub fn captured_effect_input_output(
  value : CapturedEffectInput,
) -> @execution.CompletedOutput? {
  captured_any_result_borrow_cell_output(value.borrow)
}

///|
/// The Host's concrete resident output must be the same committed generation
/// that this checked Effect source pinned; an equal CID or Result name is not
/// enough. Matching does not establish a view or grant mutation authority.
pub fn[T] captured_effect_input_matches_managed(
  value : CapturedEffectInput,
  output : @execution.ManagedCompletedOutput[T],
) -> Bool {
  captured_any_result_borrow_matches_managed(value.borrow, output)
}

///|
pub fn captured_effect_input_matches_carrier(
  value : CapturedEffectInput,
  output : @execution.CarrierManagedCompletedOutput,
) -> Bool {
  captured_any_result_borrow_matches_carrier(value.borrow, output)
}

///|
/// Prepare the authored Result projection and order from this exact retained
/// Effect source. The existing bounded Result exporter owns the row traversal;
/// this port does not materialize a second table or accept caller rows. The
/// Effect input pin must remain live until the export has finished or cancelled.
/// The resulting bytes are input evidence, not an Effect Plan or apply permit.
pub fn start_captured_effect_input_export(
  value : CapturedEffectInput,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  match value.borrow.kind {
    Cells(borrow) =>
      start_captured_result_borrow_export(
        borrow, result_view, max_rows, values, payload_wire, logical_wire, schema_limits,
        max_batch_bytes,
      )
    Resident(_) => Err(NotCellRepresentation)
  }
}

///|
/// End the Effect consumer's retention once its Preview input has been safely
/// captured or abandoned. This does not acknowledge any mutation outcome.
pub fn release_captured_effect_input(value : CapturedEffectInput) -> Bool {
  release_captured_any_result_borrow(value.borrow)
}
