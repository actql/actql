///|
/// The selected original publication recipe, quoted once before the enclosing
/// Plan. It adds physical byte demand, never Model attempts/tokens/permission
/// or a logical limit. The original input has already been identified; only
/// the completed raw Model relation is exported here.
pub fn native_client_mock_model_observation_capacity(
  limits : @infer.Limits,
) -> @execution.ExecutionCapacity? {
  if limits.model.max_items < 0 || limits.model.max_items > 2147483645 {
    return None
  }
  let identity = limits.identity
  let batch = Int::max(1, identity.wire.max_bytes)
  guard @infer.prepared_observation_issuance_metadata_bytes({
      max_slots: limits.model.max_items,
      max_wire_bytes: 16384,
      max_work: limits.model.max_items + 2,
    })
    is Some(metadata) &&
    @local_export.local_export_retention_capacity({
      max_rows: limits.output_rows,
      values: limits.output_values,
      wire: identity.wire,
      max_batch_bytes: batch,
    })
    is Some(payload) &&
    @local_export.local_export_retention_capacity({
      max_rows: limits.output_rows,
      values: limits.output_values,
      wire: identity.logical_wire,
      max_batch_bytes: batch,
    })
    is Some(logical) &&
    @encode.hash_writer_construction_inventory(
      identity.schema.max_nodes,
      identity.schema.max_depth,
    )
    is Some(hash) &&
    @encode.text_writer_construction_inventory(
      identity.schema.max_bytes,
      identity.schema.max_nodes,
      identity.schema.max_depth,
    )
    is Some(text) &&
    @execution.preparation_execution_capacity({
      retained: {
        // A distinct use of the SAME output belongs to this projection. These
        // are its use, two restricted completion views, projection token and
        // receiving tuple/options; no Model, row or input data is copied.
        record_headers: 10L,
        reference_slots: 28L,
        scalar_words: 10L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: hash.record_headers + text.record_headers,
        reference_slots: hash.reference_slots + text.reference_slots,
        scalar_words: hash.scalar_words + text.scalar_words,
        owned_utf16_units: hash.owned_utf16_units + text.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(views) &&
    @execution.execution_capacity_inventory(
      [
        { unit: QuotedBytes, count: metadata, copies: 1, },
        // Both existing writer owners remain beside their original row/ref
        // custody. The logical sink hashes only; its full export allowance is
        // a conservative bound, not a second row materialization.
        { unit: QuotedBytes, count: payload, copies: 1, },
        { unit: QuotedBytes, count: logical, copies: 1, },
      ],
      [
        {
          unit: CursorRootSlots,
          count: identity.workspace.to_int64(),
          copies: 1,
        },
        {
          unit: CursorRootSlots,
          count: identity.schema.max_fields.to_int64(),
          copies: 1,
        },
        {
          unit: CursorRootSlots,
          count: identity.schema.max_depth.to_int64(),
          copies: 1,
        },
      ],
      @execution.RetainedAlongsideExecution,
    )
    is Some(scanning) &&
    @execution.add_execution_capacity(views, scanning) is Some(base) else {
    return None
  }
  let mut complete = base
  // The already selected ordinary evidence codec: observation, invocation,
  // then local semantic projection. All three retained bodies may overlap.
  for _ in 0..<3 {
    guard @local.installed_json_effect_request_construction_capacity(
        complete, 16384, 1024, 20,
      )
      is Some(next) else {
      return None
    }
    complete = next
  }
  Some(complete)
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
