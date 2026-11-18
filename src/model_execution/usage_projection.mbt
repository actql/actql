///|
// Optional disclosure of an adopted observation, not a new capture, permission,
// completeness claim or provider-price calculation. Store confirmation remains
// with the Host's existing retained capture owner.
fn model_usage_projection_current(
  execution : ModelExecution,
  capacity : OriginalModelPublicationCapacity,
  capture : VerifiedModelCapture,
  slot : Int,
) -> Bool {
  guard physical_equal(capture.owner, execution) &&
    verified_model_capture_call_at(capture, slot) is Some(_) &&
    model_execution_invocation_evidence(execution, slot) is Some(_) &&
    model_outcome_at(execution.state, slot) is Some(Success(index)) &&
    execution.state.responses.get(index) is Some(_) &&
    execution.state.call_scope is Some(scope) else {
    return false
  }
  original_model_publication_capacity_matches_parent(capacity, execution, scope) &&
  original_model_publication_capacity_covers(capacity, 0L, 0L)
}

///|
fn emit_model_usage_projection(
  writer : @encode.Writer,
  capture : VerifiedModelCapture,
  slot : Int,
) -> Unit raise @encode.EncodeFailure {
  let state = capture.owner.state
  let call = verified_model_capture_call_at(capture, slot).unwrap()
  let evidence = model_execution_invocation_evidence(capture.owner, slot).unwrap()
  let observation = match
    @publication.model_invocation_evidence_usage(evidence) {
    Ok(value) => value
    Err(_) => raise @encode.InvalidStructure
  }
  @encode.begin_object(writer)
  @encode.key(writer, "input_tokens")
  emit_model_optional_tokens(writer, observation.input_tokens)
  @encode.key(writer, "invocation_evidence_cid")
  @encode.string_value(
    writer,
    @publication.run_evidence_value_identity(evidence),
  )
  @encode.key(writer, "model_call_slot_cid")
  @encode.string_value(writer, @publication.run_evidence_value_identity(call))
  @encode.key(writer, "model_task_contract_cid")
  @encode.string_value(writer, @environment.model_task_identity(state.task).2)
  @encode.key(writer, "observation_origin")
  @encode.string_value(
    writer,
    match observation.origin {
      @publication.Reported => "reported"
      @publication.HistoricalAdmitted => "historical_admitted"
    },
  )
  @encode.key(writer, "output_tokens")
  emit_model_optional_tokens(writer, observation.output_tokens)
  @encode.key(writer, "raw_response_artifact_cid")
  emit_model_optional_text(writer, observation.raw_response_artifact_cid)
  @encode.end_object(writer)
}

///|
fn model_usage_measure_capacity(calls : Int) -> @relation.ExecutionCapacity? {
  guard @encode.measuring_writer_construction_extent(7, 1) is Some(writer) &&
    model_usage_host_extent(calls) is Some(host) else {
    return None
  }
  @relation.preparation_execution_capacity({
    // The measured three-scalar result remains live into output construction.
    retained: {
      record_headers: host.record_headers + 1L,
      reference_slots: host.reference_slots,
      scalar_words: host.scalar_words + 3L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      // Original selection/Option/result aliases and up to two Int64 decimal
      // strings. Twenty units is the signed Int64 decimal domain, not a tariff.
      record_headers: writer.record_headers + 6L,
      reference_slots: writer.reference_slots + 8L,
      scalar_words: writer.scalar_words + 8L,
      owned_utf16_units: 40L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn model_usage_host_extent(calls : Int) -> @shape.CollectionConstructionExtent? {
  guard @shape.collection_construction_extent({
      // Fixed window: inventory, subject, child, binding, original, wires,
      // capture argument, manifest and record argument (9); async input (1),
      // child callbacks/check/shared control (5), own status descriptor plus
      // selected completion/failed-item temporaries (3), async result and
      // suspended callback carrier (2). No callback-owned payload is enumerated.
      // Per slot: original call and final completion, each <=4 references.
      records: 20L + 2L * calls.to_int64(),
      // Fixed fields above, captured original/control aliases and handoff
      // aliases fit 96 references/24 scalar words; strings remain borrowed.
      record_references: 96L + 8L * calls.to_int64(),
      record_words: 24L,
      reference_arrays: 2L,
      reference_items: 2L * calls.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(host) &&
    @relation.preparation_array_representation(1L, calls.to_int64(), true)
    is Some(items) else {
    return None
  }
  Some({
    // SAME-owner continuation: 1H/5R/10W; one live action 1H/2R/3W;
    // completed item tuples 1H/1R/2W each, plus the retained array backing.
    // Original INFER facade adds 1H/2R/1W for its same Execution/child/reentry.
    // After record, a current-loss replacement outer manifest and getter alias
    // coexist with the recorded one: 1H/7R. Items remain the SAME borrowed array.
    // Six bounded Option/Result/selection carriers and their original aliases
    // cover next/observe/current getter frames, not a numerical spare budget.
    record_headers: host.record_headers +
    items.record_headers +
    10L +
    calls.to_int64(),
    reference_slots: host.reference_slots +
    items.reference_slots +
    28L +
    calls.to_int64(),
    scalar_words: host.scalar_words +
    items.scalar_words +
    24L +
    2L * calls.to_int64(),
  })
}

///|
fn model_usage_copy_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
  calls : Int,
) -> @relation.ExecutionCapacity? {
  if bytes < 1 || calls < 1 {
    return None
  }
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    model_usage_host_extent(calls) is Some(host) else {
    return None
  }
  @relation.preparation_execution_capacity({
    retained: {
      // Output String, measured geometry, returned wire/extent tuple and its
      // Result/Option aliases coexist at the handoff.
      record_headers: host.record_headers + 4L,
      reference_slots: host.reference_slots + 4L,
      scalar_words: host.scalar_words + 8L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    workspace: {
      // TextWriter already includes its returned String; that String's header
      // and B units move to retained above rather than being charged twice.
      record_headers: writer.record_headers - 1L + 6L,
      reference_slots: writer.reference_slots + 8L,
      scalar_words: writer.scalar_words + 8L,
      owned_utf16_units: writer.owned_utf16_units - bytes.to_int64() + 40L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn grow_model_usage_phase(
  capacity : OriginalModelPublicationCapacity,
  retained_prefix : Int64,
  execution_prefix : Int64,
  next : @relation.ExecutionCapacity,
) -> Result[Unit, ModelExecutionIssue] {
  guard capacity.owner is Some(funding) &&
    funding.state.call_scope is Some(scope) &&
    @relation.checked_preparation_add_product(
      retained_prefix,
      @relation.execution_capacity_retained_bytes(next),
      1L,
    )
    is Some(retained) &&
    @relation.checked_preparation_add_product(
      execution_prefix,
      @relation.execution_capacity_execution_bytes(next),
      1L,
    )
    is Some(execution) else {
    return Err(InvalidLimits)
  }
  grow_original_model_publication_capacity(
    capacity, funding, scope, retained, execution,
  )
}

///|
fn measure_model_usage_projection(
  capture : VerifiedModelCapture,
  slot : Int,
  max_bytes : Int,
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  let writer = @encode.measuring_writer(max_bytes, 16, 1)
  emit_model_usage_projection(writer, capture, slot)
  @encode.finish_measurement_usage(writer)
}

///|
/// Existing original Model publication backing funds both bounded passes.
/// Prefixes are the caller's SAME original live publication baseline and
/// materialization, not a fresh allowance. Neither Store confirmation nor
/// destination disclosure permission is inferred from this read.
pub fn project_original_model_capture_usage(
  execution : ModelExecution,
  capacity : OriginalModelPublicationCapacity,
  capture : VerifiedModelCapture,
  slot : Int,
  retained_prefix : Int64,
  execution_prefix : Int64,
  max_bytes : Int,
) -> Result[(String, Int64, Int64), ModelExecutionIssue] {
  if retained_prefix < 0L ||
    execution_prefix < 0L ||
    max_bytes < 1 ||
    max_bytes > 1048576 {
    return Err(InvalidLimits)
  }
  if !model_usage_projection_current(execution, capacity, capture, slot) {
    return Err(OutputIdentity)
  }
  let count = verified_model_capture_call_count(capture).unwrap()
  let measure = model_usage_measure_capacity(count).unwrap()
  match
    grow_model_usage_phase(capacity, retained_prefix, execution_prefix, measure) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !model_usage_projection_current(execution, capacity, capture, slot) {
    return Err(OutputIdentity)
  }
  try {
    // The measuring Writer's frame ends here; only its scalar geometry survives.
    let (bytes, nodes, depth) = measure_model_usage_projection(
      capture, slot, max_bytes,
    )
    let next = model_usage_copy_capacity(bytes, nodes, depth, count).unwrap()
    match
      grow_model_usage_phase(capacity, retained_prefix, execution_prefix, next) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if !model_usage_projection_current(execution, capacity, capture, slot) {
      return Err(OutputIdentity)
    }
    let writer = @encode.writer(bytes, nodes, depth)
    emit_model_usage_projection(writer, capture, slot)
    let wire = @encode.finish(writer)
    Ok((wire, capacity.retained_bytes, capacity.execution_bytes))
  } catch {
    _ => Err(OutputIdentity)
  }
}

///|
/// Fund the complete fixed usage/Host control window before its inventory,
/// subject, authorization binding or cleanup child is constructed. This shares
/// the projection's peak on the same original publication reservation.
pub fn prepare_original_model_capture_usage(
  execution : ModelExecution,
  capacity : OriginalModelPublicationCapacity,
  capture : VerifiedModelCapture,
  retained_prefix : Int64,
  execution_prefix : Int64,
) -> Result[(Int64, Int64), ModelExecutionIssue] {
  if retained_prefix < 0L || execution_prefix < 0L {
    return Err(InvalidLimits)
  }
  if !model_usage_projection_current(execution, capacity, capture, 0) {
    return Err(OutputIdentity)
  }
  let count = verified_model_capture_call_count(capture).unwrap()
  match
    grow_model_usage_phase(
      capacity,
      retained_prefix,
      execution_prefix,
      model_usage_measure_capacity(count).unwrap(),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !model_usage_projection_current(execution, capacity, capture, 0) {
    return Err(OutputIdentity)
  }
  Ok((capacity.retained_bytes, capacity.execution_bytes))
}
