///|
/// Serialize only the SAME checked immutable rows. The original caller must
/// fund the writer/cursor/returned byte chunks before this construction. No
/// parse, Result issuer, Request, permission or physical ACK is introduced.
struct CapturedSnapshotPayload {
  snapshot : CapturedResultSnapshot
  writer : @encode.Writer
  emit : @json.CanonicalEmit
  mut done : Bool
  mut closed : Bool
}

///|
pub fn captured_result_snapshot_payload_extent(
  snapshot : CapturedResultSnapshot,
) -> (Int, Int, Int) {
  (snapshot.row_wire_bytes, snapshot.row_nodes, snapshot.row_depth)
}

///|
pub fn captured_result_snapshot_definition(
  snapshot : CapturedResultSnapshot,
) -> PublicationContract {
  snapshot.definition
}

///|
pub fn captured_result_snapshot_artifact(
  snapshot : CapturedResultSnapshot,
) -> PublicationContract {
  snapshot.artifact
}

///|
pub fn captured_result_snapshot_payload_identity(
  snapshot : CapturedResultSnapshot,
) -> (String, String, String, Int, Int) {
  (
    snapshot.definition.identity,
    contract_string(snapshot.artifact, "logical_result_cid").unwrap(),
    contract_string(snapshot.artifact, "result_schema_cid").unwrap(),
    @json.array_count(
      match snapshot.rows {
        @json.Array(rows) => rows
        _ => abort("invalid original rows")
      },
    ),
    snapshot.row_wire_bytes,
  )
}

///|
pub fn start_captured_result_snapshot_payload(
  snapshot : CapturedResultSnapshot,
  buffer_bytes : Int,
) -> Result[CapturedSnapshotPayload, CapturedRunIssuanceIssue] {
  try {
    let writer = @encode.buffered_writer(
      snapshot.row_wire_bytes,
      snapshot.row_nodes,
      snapshot.row_depth,
      buffer_bytes,
    )
    Ok({
      snapshot,
      writer,
      emit: @json.start_emit(snapshot.rows, writer),
      done: false,
      closed: false,
    })
  } catch {
    _ => Err(CaptureIssuanceEncoding)
  }
}

///|
/// One bounded batch of the existing canonical emitter. Empty progress is
/// allowed; None means every original byte was returned and usage matched.
pub fn CapturedSnapshotPayload::next(
  self : CapturedSnapshotPayload,
) -> Result[String?, CapturedRunIssuanceIssue] {
  if self.closed {
    return Err(CaptureIssuanceEncoding)
  }
  try {
    if self.done {
      let (bytes, nodes, depth) = @encode.finish_buffered_usage(self.writer)
      if bytes != self.snapshot.row_wire_bytes ||
        nodes != self.snapshot.row_nodes ||
        depth != self.snapshot.row_depth {
        self.cancel()
        return Err(CaptureIssuanceEncoding)
      }
      self.closed = true
      return Ok(None)
    }
    for _ in 0..<32 {
      if @json.advance_emit(self.emit) {
        self.done = true
        break
      }
    }
    Ok(Some(@encode.drain_buffered_output(self.writer)))
  } catch {
    _ => {
      self.cancel()
      Err(CaptureIssuanceEncoding)
    }
  }
}

///|
pub fn CapturedSnapshotPayload::cancel(self : CapturedSnapshotPayload) -> Unit {
  if !self.closed {
    self.closed = true
    @json.cancel_emit(self.emit)
    @encode.cancel_writer(self.writer)
  }
}

///|
/// The physical representation may change; all semantic Result contracts and
/// the original checked rows/field order remain those of this snapshot.
pub fn issue_durable_result_binding_from_snapshot(
  snapshot : CapturedResultSnapshot,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  ordering : PublicationContract,
  retention : PublicationContract,
  codec_contract_cid : String,
  result_schema_wire : String,
  material_generation_cid : String,
  store_authority_cid : String,
  byte_count : Int,
  physical_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  schema_original? : CapturedEffectDependencyBody? = None,
) -> Result[PublicationContract, DurableResultBindingIssue] {
  let (_, _, _, rows, original_bytes) = captured_result_snapshot_payload_identity(
    snapshot,
  )
  if byte_count != original_bytes {
    return Err(DurableBindingInvalidPhysicalIdentity)
  }
  issue_durable_result_binding(
    run_definition,
    snapshot.definition,
    invocation,
    snapshot.artifact,
    ordering,
    retention,
    codec_contract_cid,
    snapshot.fields,
    result_schema_wire,
    material_generation_cid,
    store_authority_cid,
    rows,
    byte_count,
    physical_sha256,
    max_wire_bytes,
    max_nodes,
    max_depth,
    schema_original~,
  )
}
