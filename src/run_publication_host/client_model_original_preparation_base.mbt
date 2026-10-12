///|
pub(all) enum ClientModelOriginalPreparationBaseIssue {
  Origin(ClientModelOriginalOriginIssue)
  State(ClientNodeModelStateIssue)
  InvalidBounds
  Encoding
} derive(Eq, Debug)

///|
// Data-only finalization of the SAME original read/Writer. The input contains
// no caller-authored resource body, resource CID, phase or cut. Only this
// Writer's complete EncodedDocument supplies the embedded exact bytes.
//
// Before entry the existing original bootstrap/read envelope must fund all
// twelve validation/getter borrows, the field array, encoder final text and
// EncodedDocument, hash/UTF-8 workspace, and the outer Writer/final-text overlap.
// The codec ceilings below are not that physical envelope or a work grant.
// This synchronous bounded-data primitive adds no persistent field, token,
// reservation or Owner. It does not adopt numeric fees or public startup.
//
// `storage` must come from A's actual same-port opaque handle getter. Matching
// kind/CID/data here never authenticates Store custody, an ACK, a current cut,
// restored resources or Model send. The caller keeps the returned wire funded
// until its original Store ACK or failed-write cleanup has really completed.
pub fn finish_client_model_original_preparation_base(
  value : ClientNodeModelStateWriter,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  storage : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientModelOriginalPreparationBaseIssue] {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(InvalidBounds)
  }
  guard value.read is Some(read) && value.writer is Some(writer) else {
    return Err(State(State(@resources.Terminal)))
  }
  // Equal Run/plan data does not associate a foreign Scope's Writer with this
  // exact existing original scope. No exposed Ledger or caller Bool is used.
  if !physical_equal(read.origin, scope.origin) ||
    !client_model_read_origin_matches(read, compiled, definition, plan) {
    return Err(Origin(ForeignRun))
  }
  if !client_model_read_available(read, compiled, definition, plan) {
    return Err(State(State(@resources.Terminal)))
  }
  guard layout is Some(bound) else { return Err(Origin(Layout(Unavailable))) }
  // Verify the already reserved, selected envelope before additional field or
  // encoder allocations. The existing token predicate is not proof that an
  // installation's declared bytes justify this primitive's physical overlap.
  if !client_model_read_preparation_available(
      read, compiled, definition, plan, bound.execution_bytes,
      retained_bytes=bound.retained_bytes,
    ) {
    return Err(Origin(Unavailable))
  }
  let fields : Array[(String, String)] = []
  for
    field in [
      "barrier_cid", "execution_context_cid", "host_policy_cid", "layout_artifact_cid",
      "parameter_values_cid", "prepared_invocation_cid", "program_definition_cid",
      "response_profile_cid", "run_definition_cid", "run_id", "runtime_artifact_cid",
      "storage_binding_cid",
    ] {
    let original = match
      client_model_original_origin_field(
        scope, compiled, definition, plan, layout, installation, runtime_artifact_cid,
        layout_artifact_cid, probability, storage, field,
      ) {
      Ok(original) => original
      Err(issue) => return Err(Origin(issue))
    }
    fields.push((field, original))
  }
  // No awaited work or user callback intervenes between the live checks and
  // finalization. A Writing/stopped/handed-off read cannot publish this base.
  let document = @encode.finish_document(writer) catch {
    _ => {
      @encode.cancel_writer(writer)
      value.writer = None
      stop_client_model_read(read)
      return Err(Encoding)
    }
  }
  @encode.cancel_writer(writer)
  value.writer = None
  if @encode.document_bytes(document) > max_bytes {
    stop_client_model_read(read)
    return Err(Encoding)
  }
  let digest = match @sha.text_hex(@encode.document_text(document)) {
    Ok(digest) => digest
    Err(_) => {
      stop_client_model_read(read)
      return Err(Encoding)
    }
  }
  let outer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => {
      stop_client_model_read(read)
      return Err(Encoding)
    }
  }
  let wire = (fn() -> String raise @encode.EncodeFailure {
    // Closed canonical key order; raw data strings use the existing encoder,
    // not the NFC/configuration canonicalizer. No self-CID cycle is introduced.
    @encode.begin_ordered_object(outer)
    @encode.ordered_key(outer, "cut")
    @encode.null_value(outer)
    @encode.ordered_key(outer, "origin")
    @encode.begin_ordered_object(outer)
    for (name, original) in fields {
      @encode.ordered_key(outer, name)
      @encode.string_value(outer, original)
    }
    @encode.end_object(outer)
    @encode.ordered_key(outer, "resource_phase")
    @encode.string_value(outer, "preparation_base")
    @encode.ordered_key(outer, "resource_state")
    @encode.emit_document(outer, document)
    @encode.ordered_key(outer, "resource_state_cid")
    @encode.string_value(outer, "sha256:" + digest)
    @encode.ordered_key(outer, "version")
    @encode.string_value(outer, "actql-model-original-resource-state/0.1")
    @encode.end_object(outer)
    @encode.finish(outer)
  })() catch {
    _ => {
      @encode.cancel_writer(outer)
      stop_client_model_read(read)
      // The stopped read stays with its same cleanup Owner even when an
      // outer encoding fails. Never issue a replacement descriptor/serial.
      return Err(Encoding)
    }
  }
  @encode.cancel_writer(outer)
  Ok(wire)
}
