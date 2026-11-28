///|
// The exact original receipt gives the logical preimage envelope. Charge
// the retained String and the active writer/cursor before either is created.
fn begin_original_mock_effect_artifact_body(
  drive : StoredMockEffectTaskDrive,
  artifact : @host.ClientEffectLocalResultArtifact,
  stream : @execution.CompletedOutputExport,
  receipt : @execution.CompletedRelationExportReceipt,
) -> Int {
  guard @execution.completed_relation_export_snapshot_extent(stream, receipt)
    is Ok((bytes, nodes, _, depth)) else {
    return -32
  }
  let slots = Int64::min(2147483647L, 8L + 2L * depth.to_int64()).to_int()
  guard @encode.text_writer_live_key_inventory(bytes, depth, depth)
    is Some(writer) &&
    @values.wire_emit_workspace_construction_inventory(slots) is Some(emitter) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + emitter.record_headers + 22L,
      reference_slots: writer.reference_slots + emitter.reference_slots + 44L,
      scalar_words: writer.scalar_words + emitter.scalar_words + 36L,
      owned_utf16_units: writer.owned_utf16_units + emitter.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(work) &&
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(wire) &&
    @execution.execution_capacity(wire, wire) is Some(output) &&
    @execution.add_execution_capacity(drive.charged, output) is Some(total) &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      drive.capacity,
      total.retained_bytes,
      total.execution_bytes,
    )
    is Ok(_) else {
    return -4
  }
  drive.charged = total
  guard @resources.reserve_capacity(drive.ledger, 0L, work) is Ok(capacity) else {
    return -4
  }
  drive.body_workspace = Some(capacity)
  match
    @execution.start_completed_relation_export_snapshot(
      stream,
      receipt,
      bytes,
      nodes,
      depth,
      slots,
      logical_body=true,
    ) {
    Ok(snapshot) => {
      drive.body = Some({ artifact, snapshot, })
      1
    }
    Err(issue) => mock_effect_artifact_body_issue(issue)
  }
}

///|
fn advance_original_mock_effect_artifact_body(
  drive : StoredMockEffectTaskDrive,
  body : StoredMockEffectArtifactBody,
  artifacts : Array[StoredMockEffectArtifact],
  count : Int,
) -> Int {
  guard drive.artifact_capture is Some(capture) && capture.original() is Some(_) else {
    return -32
  }
  match body.snapshot.advance(256) {
    Err(issue) => return mock_effect_artifact_body_issue(issue)
    Ok((false, _)) => return 1
    Ok((true, _)) => ()
  }
  let (logical_body, _) = match body.snapshot.finish() {
    Ok(result) => result
    Err(issue) => return mock_effect_artifact_body_issue(issue)
  }
  artifacts.push({ capture, artifact: body.artifact, logical_body, })
  drive.body = None
  drive.artifact_capture = None
  if !retire_original_mock_effect_body_workspace(drive) {
    return -9
  }
  if artifacts.length() == count {
    0
  } else {
    1
  }
}

///|
fn retire_original_mock_effect_body_workspace(
  drive : StoredMockEffectTaskDrive,
) -> Bool {
  if drive.body_workspace is Some(capacity) {
    if @resources.settle_capacity(drive.ledger, capacity) is Err(_) {
      return false
    }
    drive.body_workspace = None
  }
  true
}

///|
fn mock_effect_artifact_body_issue(
  issue : @execution.CompletedExportIssue,
) -> Int {
  match issue {
    Admission(CaptureLimit) | Wire(Encoding(OutputLimit)) => -4
    Unavailable | ForeignMaterial => -32
    Closed | NotFinished => -33
    _ => -31
  }
}
