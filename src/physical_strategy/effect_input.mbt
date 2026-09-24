///|
/// One checked Effect source occurrence and its exact captured cell-backed
/// output. The ordinary task port may close while this owner is live. This is
/// neither a Preview nor an apply permit, and it does not copy Result cells.
struct CapturedEffectInput {
  source : CheckedEffectSourcePort
  pin : CapturedOutputPin
}

///|
/// One Effect Run's complete source inventory. Members without a Result
/// source retain their position but require no pin. The source inventory is
/// derived from the checked graph, never supplied by a caller.
struct CapturedEffectInputs {
  run : CapturedEffectRunDAG
  entries : Array[CapturedEffectInput?]
  pins : CapturedResultOutputSet
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
    pin_captured_result_output_set(run.captured, requests, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries : Array[CapturedEffectInput?] = []
  let mut pin_index = 0
  for source in sources {
    match source {
      Some(source) => {
        let pin = captured_result_output_set_pin_at(pins, pin_index).unwrap()
        entries.push(Some({ source, pin, }))
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
  inputs : CapturedEffectInputs,
  preview : @checked.EffectProgramRunPreview,
  max_work : Int,
) -> Result[CapturedEffectPreviewInputs, RunIssue] {
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
        @execution.completed_output_available(
          captured_effect_input_output(input),
        ) else {
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
    if @execution.completed_output_available(
        captured_effect_input_output(input),
      ) {
      Some(input)
    } else {
      None
    }
  })
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
pub fn captured_effect_input_at(
  value : CapturedEffectInputs,
  member_index : Int,
) -> CapturedEffectInput? {
  if value.live {
    value.entries.get(member_index).bind(entry => entry)
  } else {
    None
  }
}

///|
/// Revoke every consumer alias. Already returned input aliases share the
/// underlying pins and become unavailable after this release.
pub fn release_captured_effect_inputs(value : CapturedEffectInputs) -> Bool {
  if !value.live {
    return false
  }
  value.live = false
  release_captured_result_output_set(value.pins) |> ignore
  true
}

///|
/// Capture only the source retained by this checked Effect Run. An authored
/// name or caller-supplied output cannot replace its checked Stage Result port.
/// Nonterminal and managed representations require their own retained output
/// path before they can be accepted as Effect inputs.
pub fn pin_captured_effect_source(
  run : CapturedEffectRunDAG,
  member_index : Int,
  max_pins : Int,
) -> Result[CapturedEffectInput, RunIssue] {
  guard captured_effect_run_source_at(run, member_index) is Some(source) &&
    source.member_index == member_index else {
    return Err(ForeignCandidate)
  }
  let pin = match
    pin_captured_result_output(
      run.captured,
      source.task,
      source.occurrence,
      max_pins,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, pin, })
}

///|
/// Borrow an exact checked Result occurrence from its completed task. This
/// remains Host-private retention, not permission to disclose the Result or
/// use it as an Effect input. A different Program owner cannot relabel it.
pub fn pin_captured_result_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedResultOccurrence,
  max_pins : Int,
) -> Result[CapturedOutputPin, RunIssue] {
  let owner = @execution.managed_result_occurrence_owner(occurrence)
  let port = @execution.managed_result_occurrence_port(occurrence)
  let target = @ports.port_target(port)
  guard run.graph.owners.get(task) is Some(actual) &&
    physical_equal(actual, owner) else {
    return Err(ForeignCandidate)
  }
  if captured_task_target(run, task) != Some(target) {
    return Err(UnsupportedGraph)
  }
  let pin = match pin_captured_task_output(run, task, target, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = captured_output_pin_materialized(pin)
  if !@execution.completed_output_matches_port(output, owner, target) {
    release_captured_output_pin(pin) |> ignore
    return Err(ForeignCandidate)
  }
  Ok(pin)
}

///|
/// The checked occurrence retains its authored Result projection and order.
pub fn captured_effect_input_occurrence(
  value : CapturedEffectInput,
) -> @execution.ManagedResultOccurrence {
  value.source.occurrence
}

///|
/// The borrowed producer is live only while both the original completion and
/// this Effect input pin remain live. Projection is applied by the Result view
/// preparation, not by returning a caller-defined table here.
pub fn captured_effect_input_output(
  value : CapturedEffectInput,
) -> @execution.CompletedOutput {
  captured_output_pin_materialized(value.pin)
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
  @execution.start_completed_result_relation_export(
    captured_effect_input_output(value),
    value.source.occurrence,
    result_view,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
  )
}

///|
/// End the Effect consumer's retention once its Preview input has been safely
/// captured or abandoned. This does not acknowledge any mutation outcome.
pub fn release_captured_effect_input(value : CapturedEffectInput) -> Bool {
  release_captured_output_pin(value.pin)
}
