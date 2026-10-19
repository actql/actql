///|
// This receiver owns bounded copied values. It is not a resource issuer or a
// read permission. Only an authorized actual Session can transfer its rows.
struct NativeResultMaterialReceiver {
  store : @store.Store
  request : NativeResultAccessRequest
  resolved : @store.NativeCommittedResult
  identity : NativeResultMaterialIdentity
  schema : @publication.ResultMaterialSchema
  frames : @publication.DurableResultRowFrames
  rows : Array[@publication.ResultMaterialRow]
  max_bytes : Int
  max_rows : Int
  chunk_bytes : Int
  mut session : NativeResultAccessSession?
  mut sink : NativeResultSink?
  mut primary : NativeResultMaterialIssue?
  mut finished : Bool
  mut completed : Bool
  mut table_attempted : Bool
  mut table_receipt : NativeResultTableWriteReceipt?
  mut closed : Bool
}

///|
/// Immutable identities of the actual selected receiver and Store metadata.
/// These values alone cannot construct a receiver, grant or acknowledgement.
pub struct NativeResultMaterialIdentity {
  receiver_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
}

///|
pub(all) enum NativeResultMaterialIssue {
  MaterialInvalidLimits
  MaterialForeignSession
  MaterialNotComplete
  MaterialClosed
  MaterialOutputAlreadyAttempted
  MaterialOutputUnknown(Int)
  MaterialAccess(NativeResultAccessIssue)
  MaterialSink(NativeResultSinkIssue)
  MaterialSchema(@publication.ResultMaterialIssue)
  MaterialFrame(@publication.DurableResultRowFrameIssue)
}

///|
fn same_material_request(
  left : NativeResultAccessRequest,
  right : NativeResultAccessRequest,
) -> Bool {
  left.namespace_id == right.namespace_id &&
  left.authority_scope_cid == right.authority_scope_cid &&
  left.run_definition_cid == right.run_definition_cid &&
  left.principal_id == right.principal_id &&
  left.purpose == right.purpose &&
  left.result_name == right.result_name &&
  left.format == right.format &&
  left.attempt_id == right.attempt_id
}

///|
/// Observe only committed metadata through the same actual Store before
/// allocating the bounded row workspace. Caller authorization remains an
/// independent prerequisite; this constructor never opens a payload reader.
pub fn prepare_native_result_material_receiver(
  store : @store.Store,
  request : NativeResultAccessRequest,
  receiver_cid : String,
  max_bytes : Int,
  max_rows : Int,
  max_row_bytes : Int,
  max_fields : Int,
  chunk_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  allowed_policy_cids : Array[String],
) -> Result[NativeResultMaterialReceiver, NativeResultMaterialIssue] {
  if !valid_request(request) ||
    request.format != "json" ||
    !valid_cid(receiver_cid) ||
    max_bytes < 1 ||
    max_bytes > 16777216 ||
    max_rows < 0 ||
    max_row_bytes < 1 ||
    max_row_bytes > max_bytes ||
    max_fields < 1 ||
    max_fields > 128 ||
    chunk_bytes < 1 ||
    chunk_bytes > max_bytes ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_depth > 64 {
    return Err(MaterialInvalidLimits)
  }
  // Metadata uses the existing bounded contract envelope. The payload byte
  // ceiling is independent and remains enforced by the frame and sink.
  let resolved = match
    store.resolve_committed_result(
      request.namespace_id,
      request.authority_scope_cid,
      request.run_definition_cid,
      request.result_name,
      65536,
      max_nodes,
      max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(MaterialAccess(ResultUnavailable))
    Err(issue) => return Err(MaterialAccess(Store(issue)))
  }
  if resolved.read.row_count > max_rows.to_int64() ||
    resolved.read.result_fields.length() > max_fields ||
    !allowed_policy_cids.contains(resolved.read.effective_data_policy_cid) {
    return Err(MaterialInvalidLimits)
  }
  let schema_wire = match
    store.read_result_schema(resolved.read.result_schema_cid) {
    Ok(value) => value
    Err(issue) => return Err(MaterialAccess(Store(issue)))
  }
  let schema = match
    @publication.prepare_result_material_schema(
      schema_wire,
      resolved.read.result_fields,
      65536,
      max_nodes,
      max_depth,
      max_fields,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialSchema(issue))
  }
  let frames = match
    @publication.prepare_durable_result_row_frames(
      max_bytes, max_rows, max_row_bytes, max_depth, chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialFrame(issue))
  }
  Ok({
    store,
    request,
    resolved,
    identity: {
      receiver_cid,
      result_schema_cid: resolved.read.result_schema_cid,
      ordering_evidence_cid: resolved.read.ordering_evidence_cid,
    },
    schema,
    frames,
    rows: [],
    max_bytes,
    max_rows,
    chunk_bytes,
    session: None,
    sink: None,
    primary: None,
    finished: false,
    completed: false,
    table_attempted: false,
    table_receipt: None,
    closed: false,
  })
}

///|
pub fn NativeResultMaterialReceiver::identity(
  self : NativeResultMaterialReceiver,
) -> NativeResultMaterialIdentity {
  self.identity
}

///|
/// No physical I/O inside Journal authorization callbacks. Actual Store
/// currentness is checked by its original operations before/after delivery.
pub fn NativeResultMaterialReceiver::matches_request(
  self : NativeResultMaterialReceiver,
  request : NativeResultAccessRequest,
) -> Bool {
  !self.closed &&
  self.primary is None &&
  same_material_request(self.request, request)
}

///|
pub fn NativeResultMaterialReceiver::matches_facts(
  self : NativeResultMaterialReceiver,
  facts : NativeResultReadFacts,
) -> Bool {
  self.matches_request(facts.request) &&
  (
    facts.result_artifact_cid.is_empty() ||
    (
      facts.result_artifact_cid == self.resolved.read.result_artifact_cid &&
      facts.result_definition_cid == self.resolved.read.result_definition_cid &&
      facts.material_generation_cid ==
      self.resolved.read.material_generation_cid &&
      facts.public_index_entry_cid ==
      @publication.publication_contract_identity(
        self.resolved.public_index_entry,
      ) &&
      facts.result_manifest_cid ==
      @publication.publication_contract_identity(self.resolved.result_manifest)
    )
  )
}

///|
fn NativeResultMaterialReceiver::accept(
  self : NativeResultMaterialReceiver,
  bytes : Bytes,
) -> NativeResultSinkWrite {
  if self.closed || self.finished || self.primary is Some(_) {
    return SinkChunkFailed(0, 0)
  }
  let rows = match
    @publication.feed_durable_result_row_frames(self.frames, bytes) {
    Ok(value) => value
    Err(issue) => {
      self.primary = Some(MaterialFrame(issue))
      return SinkChunkFailed(0, 0)
    }
  }
  for wire in rows {
    match @publication.admit_result_material_row(self.schema, wire) {
      Ok(row) => self.rows.push(row)
      Err(issue) => {
        self.primary = Some(MaterialSchema(issue))
        return SinkChunkFailed(0, 0)
      }
    }
  }
  // The frame's partial row and every admitted row now belong to this exact
  // bounded receiver. No stdout write or external exposure was acknowledged.
  SinkChunkConfirmed
}

///|
fn NativeResultMaterialReceiver::finish(
  self : NativeResultMaterialReceiver,
) -> Bool {
  if self.closed || self.primary is Some(_) || self.finished {
    return false
  }
  match @publication.finish_durable_result_row_frames(self.frames) {
    Err(issue) => {
      self.primary = Some(MaterialFrame(issue))
      false
    }
    Ok(summary) => {
      if summary.rows != self.rows.length() ||
        summary.rows.to_int64() != self.resolved.read.row_count {
        self.primary = Some(MaterialSchema(@publication.MaterialInvalidRow))
        return false
      }
      self.finished = true
      true
    }
  }
}

///|
/// Retain the same acquired Session before installing its sink. A failed
/// installation keeps it available for cleanup and never repeats the read.
pub fn NativeResultMaterialReceiver::attach(
  self : NativeResultMaterialReceiver,
  session : NativeResultAccessSession,
) -> Result[Unit, NativeResultMaterialIssue] {
  if self.closed ||
    self.session is Some(_) ||
    self.primary is Some(_) ||
    !physical_equal(self.store, session.service.store) ||
    !same_material_request(self.request, session.request) ||
    session.resolved.read.durable_result_binding_cid !=
    self.resolved.read.durable_result_binding_cid ||
    session.resolved.read.material_generation_cid !=
    self.resolved.read.material_generation_cid ||
    session.resolved.read.result_schema_cid != self.identity.result_schema_cid ||
    session.resolved.read.ordering_evidence_cid !=
    self.identity.ordering_evidence_cid {
    return Err(MaterialForeignSession)
  }
  self.session = Some(session)
  match
    install_native_result_sink(
      session,
      self.chunk_bytes,
      self.max_bytes,
      bytes => self.accept(bytes),
      () => self.finish(),
    ) {
    Ok(sink) => {
      self.sink = Some(sink)
      Ok(())
    }
    Err(issue) => {
      self.primary = Some(MaterialSink(issue))
      Err(MaterialSink(issue))
    }
  }
}

///|
pub fn NativeResultMaterialReceiver::covers_read_limits(
  self : NativeResultMaterialReceiver,
  max_bytes : Int,
  max_uses : Int,
) -> Bool {
  !self.closed && self.max_bytes == max_bytes && max_uses == 1
}

///|
pub fn NativeResultMaterialReceiver::poll(
  self : NativeResultMaterialReceiver,
) -> Result[Bool, NativeResultMaterialIssue] {
  if self.closed {
    return Err(MaterialClosed)
  }
  guard self.sink is Some(sink) else { return Err(MaterialNotComplete) }
  match sink.poll() {
    Err(issue) => Err(MaterialSink(issue))
    Ok(SinkProgress) => Ok(false)
    Ok(SinkComplete(_)) => {
      self.completed = true
      Ok(true)
    }
    Ok(SinkFailed(issue, _)) => Err(self.primary.unwrap_or(MaterialSink(issue)))
  }
}

///|
/// This prepares display bytes only. It does not acknowledge stdout or close
/// any live Session/Store/Library; the caller must perform the real write.
pub fn NativeResultMaterialReceiver::table(
  self : NativeResultMaterialReceiver,
  max_output_bytes : Int,
) -> Result[String, NativeResultMaterialIssue] {
  if self.closed {
    return Err(MaterialClosed)
  }
  if !self.completed {
    return Err(MaterialNotComplete)
  }
  @publication.render_result_material_table(
    self.schema,
    self.rows,
    self.max_rows,
    max_output_bytes,
  ).map_err(issue => MaterialSchema(issue))
}

///|
/// Actual completed stdout write and flush, distinct from material transfer.
pub struct NativeResultTableWriteReceipt {
  confirmed_bytes : Int
}

///|
pub fn NativeResultMaterialReceiver::table_output_in_flight(
  self : NativeResultMaterialReceiver,
) -> Bool {
  !self.closed &&
  self.completed &&
  self.table_attempted &&
  self.table_receipt is None
}

///|
/// Reauthorize the original request for the distinct presentation phase, then
/// invoke the supported stdout API once. Unknown output never becomes a retry.
pub fn NativeResultMaterialReceiver::write_table(
  self : NativeResultMaterialReceiver,
  max_output_bytes : Int,
) -> Result[NativeResultTableWriteReceipt, NativeResultMaterialIssue] {
  if self.table_attempted {
    return Err(MaterialOutputAlreadyAttempted)
  }
  let table = match self.table(max_output_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard self.session is Some(session) else { return Err(MaterialNotComplete) }
  self.table_attempted = true
  match session.authorize_stage("table_output") {
    Err(issue) => return Err(MaterialAccess(issue))
    Ok(_) => ()
  }
  let bytes = @utf8.encode(table)
  let written = material_write_table_bytes(bytes, bytes.length())
  if written != 0 {
    return Err(MaterialOutputUnknown(written))
  }
  let receipt = { confirmed_bytes: bytes.length(), }
  self.table_receipt = Some(receipt)
  Ok(receipt)
}

///|
pub fn NativeResultMaterialReceiver::close(
  self : NativeResultMaterialReceiver,
) -> Result[Unit, NativeResultAccessIssue] {
  if self.closed {
    return Ok(())
  }
  if self.sink is Some(sink) {
    match sink.close() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if self.session is Some(session) {
    match session.close() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  self.rows.clear()
  @publication.cancel_durable_result_row_frames(self.frames)
  self.sink = None
  self.session = None
  self.closed = true
  Ok(())
}
