///|
/// Only the physical-output facts consumed by restored snapshot persistence.
/// Computation, policy and input relations remain in the original admitted
/// artifact/derivation; this caller cannot fabricate unused issuer fields.
pub(all) struct NativeEffectfulSnapshotOutputContext {
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  retention : @publication.PublicationContract
  publication_attempt : @publication.PublicationContract
  store_authority_cid : String
  material_generation_cid : String
  max_payload_bytes : Int64
}

///|
/// Physical binding only: original Result definitions/artifacts are retained,
/// never reissued from Preview or a new computation.
pub(all) struct NativePublishedEffectfulResult {
  binding : @publication.PublicationContract
  binding_schema_wire : String
  payload : @store.NativePublicationPayloadInfo
}

///|
/// Persist the transferred SAME fully validated snapshot through the existing
/// Store payload owner. The caller's original Read funds the full serializer
/// extent before entry and retains failed child custody until real cleanup.
pub fn persist_effectful_result_snapshot_native(
  store : @store.Store,
  snapshot : @publication.CapturedResultSnapshot,
  context : NativeEffectfulSnapshotOutputContext,
  ordering : @publication.PublicationContract,
  result_schema_wire : String,
  codec_contract_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  schema_original? : @publication.CapturedEffectDependencyBody? = None,
) -> Result[NativePublishedEffectfulResult, NativePublicationOutputIssue] {
  let (definition, logical, schema, rows, bytes) = @publication.captured_result_snapshot_payload_identity(
    snapshot,
  )
  if bytes < 1 ||
    bytes.to_int64() > context.max_payload_bytes ||
    max_wire_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 {
    return Err(InvalidOutputConfiguration)
  }
  let request = match
    @payload.prepare_publication_payload_request(
      context.store_authority_cid,
      @publication.publication_contract_identity(context.publication_attempt),
      context.material_generation_cid,
      definition,
      logical,
      schema,
      @publication.publication_contract_identity(ordering),
      codec_contract_cid,
      bytes.to_int64(),
      rows.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Payload(issue))
  }
  let writer = match store.begin_payload(request) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  let stream = match
    @publication.start_captured_result_snapshot_payload(
      snapshot,
      Int::min(65536, bytes),
    ) {
    Ok(value) => value
    Err(issue) =>
      return match writer.cancel() {
        Ok(_) => Err(Snapshot(issue))
        Err(cleanup) => Err(SnapshotCleanup(issue, cleanup))
      }
  }
  while true {
    match stream.next() {
      Ok(Some(chunk)) =>
        match writer.append(@utf8.encode(chunk)) {
          Ok(_) => ()
          Err(issue) => {
            stream.cancel()
            return Err(cancel_writer_after_store_failure(writer, issue))
          }
        }
      Ok(None) => break
      Err(issue) =>
        return match writer.cancel() {
          Ok(_) => Err(Snapshot(issue))
          Err(cleanup) => Err(SnapshotCleanup(issue, cleanup))
        }
    }
  }
  let payload = match writer.seal() {
    Ok(value) => value
    Err(issue) => return Err(cancel_writer_after_store_failure(writer, issue))
  }
  let binding = match
    bind_sealed_effectful_result_snapshot_native(
      snapshot,
      context,
      ordering,
      result_schema_wire,
      codec_contract_cid,
      payload,
      max_wire_bytes,
      max_nodes,
      max_depth,
      schema_original~,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        reclaim_after_binding_failure(
          store,
          context.material_generation_cid,
          issue,
        ),
      )
  }
  Ok({ binding, binding_schema_wire: result_schema_wire, payload, })
}

///|
/// Bind the same sealed output from either the writer's return or a retained
/// Store observation. This never opens a writer or serializes the snapshot.
pub fn bind_sealed_effectful_result_snapshot_native(
  snapshot : @publication.CapturedResultSnapshot,
  context : NativeEffectfulSnapshotOutputContext,
  ordering : @publication.PublicationContract,
  result_schema_wire : String,
  codec_contract_cid : String,
  payload : @store.NativePublicationPayloadInfo,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  schema_original? : @publication.CapturedEffectDependencyBody? = None,
) -> Result[
  @publication.PublicationContract,
  @publication.DurableResultBindingIssue,
] {
  let (definition, logical, schema, rows, bytes) = @publication.captured_result_snapshot_payload_identity(
    snapshot,
  )
  if payload.material_generation_cid != context.material_generation_cid ||
    payload.publication_attempt_cid !=
    @publication.publication_contract_identity(context.publication_attempt) ||
    payload.result_definition_cid != definition ||
    payload.logical_relation_cid != logical ||
    payload.result_schema_cid != schema ||
    payload.ordering_evidence_cid !=
    @publication.publication_contract_identity(ordering) ||
    payload.durable_codec_cid != codec_contract_cid ||
    payload.row_count != rows.to_int64() ||
    payload.generation.size != bytes.to_int64() ||
    !payload.physical_digest.has_prefix("sha256:") {
    return Err(@publication.DurableBindingInvalidPhysicalIdentity)
  }
  @publication.issue_durable_result_binding_from_snapshot(
    snapshot,
    context.run_definition,
    context.invocation,
    ordering,
    context.retention,
    codec_contract_cid,
    result_schema_wire,
    payload.material_generation_cid,
    context.store_authority_cid,
    bytes,
    payload.physical_digest[7:].to_owned(),
    max_wire_bytes,
    max_nodes,
    max_depth,
    schema_original~,
  )
}
