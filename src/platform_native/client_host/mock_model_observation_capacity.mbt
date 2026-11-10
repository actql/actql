///|
/// Fixed publication/use/view controls only. The original retained output
/// view coexists with transient restricted completion views at projection;
/// include their predicate/option/receiving and phase-quote controls together.
/// Output/schema/writer maxima
/// validate later constructors; they are not retained startup material.
pub fn native_client_mock_model_observation_capacity(
  limits : @infer.Limits,
) -> @execution.ExecutionCapacity? {
  if limits.model.max_items < 0 || limits.model.max_items > 2147483645 {
    return None
  }
  // The identity-preserving dependency reader keeps four original triples
  // (+one reference each), two temporary original input pairs, one map
  // closure/Some, and the original two-entry input array during projection.
  guard @execution.preparation_array_representation(1L, 2L, true)
    is Some(input_array) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 32L + 4L + input_array.record_headers,
      reference_slots: 128L + 10L + input_array.reference_slots,
      scalar_words: 64L + 1L + input_array.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// The existing finite flat-observation protocol allowance belongs at issuer
// construction with this terminal original's actual row count, not in the
// pre-execution Plan as a row/file output maximum.
fn NativeClientMockModelWork::observation_issuer_capacity(
  self : Self,
) -> @execution.ExecutionCapacity? {
  guard self.active is Some(active) &&
    self.prepared is Some(prepared) &&
    @model.prepared_model_call_count(prepared) is Some(count) &&
    count <= 2147483645 &&
    @infer.original_observation_issuance_metadata_bytes(active, {
      max_slots: count,
      max_wire_bytes: 16384,
      max_work: count + 2,
    })
    is Some(metadata) &&
    @execution.execution_capacity(metadata, metadata) is Some(issuer) else {
    return None
  }
  @execution.add_execution_capacity(self._retained_observation_capacity, issuer)
}

///|
// This same token grows only when actual phase demand exceeds its held peak.
// Covered bounded steps do not each invoke another Resource current callback.
fn NativeClientMockModelWork::grow_observation_capacity(
  self : Self,
  required : @execution.ExecutionCapacity,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.advancing &&
    !self.closing &&
    !self.closed &&
    self.active is Some(active) &&
    self.publication_capacity is Some(capacity) else {
    return Err(ForeignOriginal)
  }
  let retained = @execution.execution_capacity_retained_bytes(required)
  let execution = @execution.execution_capacity_execution_bytes(required)
  if retained <= self.publication_retained &&
    execution <= self.publication_execution {
    return Ok(())
  }
  match
    @infer.grow_original_infer_publication_capacity(
      active, capacity, retained, execution,
    ) {
    Err(issue) => return Err(Model(issue))
    Ok(_) => ()
  }
  self.publication_retained = Int64::max(self.publication_retained, retained)
  self.publication_execution = Int64::max(self.publication_execution, execution)
  Ok(())
}

///|
// Closed eight-member metadata, not row payload. Six original CIDs plus one
// ordinal determine its actual String bound; nine nodes and one container
// follow the existing protocol. Admission remains 16KiB/1024 nodes/depth20.
fn NativeClientMockModelWork::local_observation_projection_capacity(
  self : Self,
  receipt : @execution.CompletedRelationExportReceipt,
) -> @execution.ExecutionCapacity? {
  guard self.active is Some(active) &&
    active.call_scope is Some(scope) &&
    @publication.model_input_artifact_relation_identities(
      @host.client_infer_call_scope_artifact(scope),
    )
    is Some((logical, schema)) else {
    return None
  }
  let (unit, _) = @host.client_infer_call_scope_local_coordinate(scope)
  let output = @execution.logical_relation_cid(
    @execution.completed_relation_export_identity(receipt),
  )
  let output_schema = @execution.relation_schema_cid(
    @execution.completed_relation_export_schema_identity(receipt),
  )
  // Six escaped bytes per original UTF16 unit; 512 covers fixed vocabulary,
  // version, punctuation and safe-Int ordinal. The self CID is this producer's
  // original SHA256 spelling (71 units), never fabricated relation data.
  let strings = unit.length().to_int64() +
    logical.length().to_int64() +
    schema.length().to_int64() +
    output.length().to_int64() +
    output_schema.length().to_int64() +
    71L
  let bytes = Int64::min(16384L, 512L + 6L * strings).to_int()
  guard @encode.hash_writer_construction_inventory(9, 1) is Some(hash) &&
    @encode.text_writer_construction_inventory(bytes, 9, 1) is Some(text) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: 6L + hash.record_headers + text.record_headers,
        reference_slots: 16L + hash.reference_slots + text.reference_slots,
        scalar_words: 8L + hash.scalar_words + text.scalar_words,
        owned_utf16_units: hash.owned_utf16_units + text.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
      workspace: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(writers) &&
    @execution.execution_capacity(
      self.publication_retained,
      self.publication_execution,
    )
    is Some(held) &&
    @execution.add_execution_capacity(held, writers) is Some(complete) else {
    return None
  }
  @local.installed_json_effect_request_construction_capacity(
    complete, bytes, 9, 1,
  )
}

///|
/// Read the same original Work's immutable pre-execution byte demand. This
/// neither opens the Model nor prepares another recipe or resource owner.
pub fn NativeClientMockModelWork::observation_capacity(
  self : Self,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @host.ClientInferPlanGraph,
) -> @execution.ExecutionCapacity? {
  if self.open_attempted ||
    self.closing ||
    self.closed ||
    !physical_equal(self.request, request) ||
    !physical_equal(self.compiled, compiled) ||
    !physical_equal(self.definition, definition) ||
    !physical_equal(self.graph, graph) {
    None
  } else {
    Some(self._retained_observation_capacity)
  }
}
