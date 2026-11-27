///|
fn completed_capture_value_verification_capacity(depth : Int) -> Int64? {
  guard depth >= 0 && depth <= (2147483647 - 8) / 2 else { return None }
  let frames = 2 * depth + 8
  // Both emitters write ordered objects. A typed JsonData wrapper can keep
  // one unordered key per open level. The broader node limit remains on the
  // writer, but only these frame/key arrays contribute to its live peak.
  guard @encode.hash_writer_live_key_inventory(depth, depth) is Some(hash) &&
    @admitted.wire_emit_workspace_construction_inventory(frames) is Some(wire) &&
    @shape.collection_construction_extent({
      // Recheck has one continuing container per level and one current node
      // or text/name frame. Its runtime Value and Contract are borrowed.
      records: 2L * frames.to_int64() + 12L,
      record_references: 5L * frames.to_int64() + 16L,
      record_words: 6L * frames.to_int64() + 16L,
      reference_arrays: 1L,
      reference_items: frames.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(recheck) else {
    return None
  }
  // Shared controls hold the two identity strings, work counters and
  // callbacks. Recheck retires before the next hash cursor allocates.
  let controls : @relation.PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 32L,
    scalar_words: 32L,
    owned_utf16_units: 144L,
    owned_wire_bytes: 0L,
  }
  guard @relation.preparation_representation_cost({
      record_headers: controls.record_headers +
      hash.record_headers +
      wire.record_headers,
      reference_slots: controls.reference_slots +
      hash.reference_slots +
      wire.reference_slots,
      scalar_words: controls.scalar_words +
      hash.scalar_words +
      wire.scalar_words,
      owned_utf16_units: controls.owned_utf16_units +
      hash.owned_utf16_units +
      wire.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(emission) &&
    @relation.preparation_representation_cost({
      ..controls,
      record_headers: controls.record_headers + recheck.record_headers,
      reference_slots: controls.reference_slots + recheck.reference_slots,
      scalar_words: controls.scalar_words + recheck.scalar_words,
    })
    is Some(validation) else {
    return None
  }
  Some(Int64::max(emission, validation))
}

///|
/// Check the persisted structured response against the actual accepted slot.
/// The saved body must hash to the original pre-validation wire identity.
/// Recheck the original retained typed Value under that Task's output
/// contract and compare its typed wire identity independently. No model
/// session, provider, request, output or durable custody is issued here.
pub fn verify_completed_model_capture_value(
  execution : ModelExecution,
  slot : Int,
  saved : @publication.ModelCaptureRecordRead,
  fund : (Int64) -> Bool,
  remaining_work? : Ref[Int]? = None,
) -> Result[Unit, ModelExecutionIssue] {
  let state = execution.state
  guard !execution.advancing &&
    !state.reclaimed &&
    !state.stop_requested &&
    state.accepted &&
    @bounded.session_stopped(execution.session) &&
    model_outcome_at(state, slot) is Some(Success(index)) &&
    state.captures.get(index) is Some(capture) &&
    capture.slot == slot &&
    state.invocation_evidence.get(index) is Some(observation) &&
    @publication.run_evidence_value_identity(observation) ==
    @publication.run_evidence_value_identity(
      @publication.model_capture_record_evidence(saved),
    ) &&
    @publication.model_capture_record_text(
      saved, "structured_response_artifact_cid",
    )
    is Some(expected_response) &&
    @publication.model_capture_record_text(
      saved, "validated_structured_output_cid",
    )
    is Some(expected_output) else {
    return Err(OutputIdentity)
  }
  let limits = state.limits.value_limits
  let bytes = Int64::min(state.limits.max_response_bytes, 2147483647L).to_int()
  guard completed_capture_value_verification_capacity(limits.max_depth)
    is Some(peak) &&
    fund(peak) else {
    return Err(Ledger(@resources.RetentionLimit))
  }
  if execution.advancing ||
    state.reclaimed ||
    state.stop_requested ||
    !state.accepted {
    return Err(OutputIdentity)
  }
  let remaining = Ref(state.limits.max_work)
  let exhausted = Ref(false)
  let spend = (units : Int) => {
    if units < 0 ||
      units > remaining.val ||
      (remaining_work is Some(total) && units > total.val) {
      exhausted.val = true
      false
    } else {
      remaining.val -= units
      if remaining_work is Some(total) {
        total.val -= units
      }
      true
    }
  }
  let observed = completed_capture_value_hash(bytes, limits, spend, writer => {
    @canonical.emit_value(
      @publication.model_capture_record_response(saved),
      writer,
    )
  })
  match observed {
    Ok(cid) if cid == expected_response => ()
    Ok(_) => return Err(OutputIdentity)
    Err(_) =>
      return if exhausted.val { Err(WorkLimit) } else { Err(OutputValue) }
  }
  let checked = match
    recheck_completed_capture_value(
      capture.value.value,
      @environment.model_task_output(state.task),
      limits,
      spend,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = completed_capture_value_hash(bytes, limits, spend, writer => {
    let cursor = @admitted.start_wire_emit(checked.value, writer)
    defer @admitted.cancel_wire_emit(cursor)
    while true {
      @encode.construction_work_step(writer, 1)
      if @admitted.advance_wire_emit(cursor) {
        break
      }
    }
  })
  match output {
    Ok(cid) if cid == expected_output => Ok(())
    Ok(_) => Err(OutputIdentity)
    Err(_) => if exhausted.val { Err(WorkLimit) } else { Err(OutputValue) }
  }
}

///|
fn completed_capture_value_hash(
  bytes : Int,
  limits : @admitted.Limits,
  spend : (Int) -> Bool,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Result[String, @encode.EncodeFailure] {
  try {
    let writer = @encode.work_hashing_writer(
      bytes,
      limits.max_nodes,
      limits.max_depth,
      spend,
    )
    defer @encode.cancel_writer(writer)
    emit(writer)
    Ok("sha256:" + @encode.finish_hash(writer))
  } catch {
    issue => Err(issue)
  }
}

///|
fn recheck_completed_capture_value(
  value : @admitted.Value,
  contract : @contract.Contract,
  limits : @admitted.Limits,
  spend : (Int) -> Bool,
) -> Result[@admitted.CheckedValue, ModelExecutionIssue] {
  guard @admitted.start_recheck_runtime_value(value, contract, limits)
    is Some(cursor) else {
    return Err(OutputValue)
  }
  defer @admitted.cancel_recheck_runtime_value(cursor)
  while spend(1) {
    match @admitted.advance_recheck_runtime_value(cursor) {
      RecheckContinue => ()
      RecheckComplete(checked, _, _) => return Ok(checked)
      RecheckFailed => return Err(OutputValue)
    }
  }
  Err(WorkLimit)
}
