///|
// One emitter supplies both the allocation-free measurement and exact private
// continuation bytes. It borrows the already captured originals; it performs
// no semantic checking, Source read, compilation, Model or Result execution.
fn emit_native_mock_effect_review(
  writer : @encode.Writer,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  schema_wires : Array[String],
  codec_cids : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  review_wire : String,
  authoring_cid : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("version", "actql-native-local-effect-review-reference/0.1"),
      ("provider", "native-local-project-mock"),
      ("request_scope_cid", @host.client_request_scope_cid(request)),
      ("authority_scope_cid", @host.client_request_authority_scope_cid(request)),
      ("request_id", @host.client_request_caller_id(request)),
      (
        "run_definition_wire",
        @publication.publication_contract_json(definition),
      ),
      ("invocation_wire", @publication.publication_contract_json(invocation)),
      ("result_manifest_wire", @publication.publication_contract_json(manifest)),
      (
        "computation_receipt_wire",
        @publication.publication_contract_json(receipt),
      ),
      ("captured_run_cid", @publication.publication_contract_identity(captured)),
      ("review_wire", review_wire),
      ("authoring_context_cid", authoring_cid),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.key(writer, "result_definition_wires")
  @encode.begin_array(writer)
  for value in definitions {
    @encode.string_value(writer, @publication.publication_contract_json(value))
  }
  @encode.end_array(writer)
  @encode.key(writer, "result_artifact_wires")
  @encode.begin_array(writer)
  for value in artifacts {
    @encode.string_value(writer, @publication.publication_contract_json(value))
  }
  @encode.end_array(writer)
  for
    (name, originals) in [
      ("result_derivation_wires", derivations),
      ("result_ordering_wires", orderings),
      ("result_retention_wires", retentions),
    ] {
    @encode.key(writer, name)
    @encode.begin_array(writer)
    for original in originals {
      @encode.string_value(
        writer,
        @publication.publication_contract_json(original),
      )
    }
    @encode.end_array(writer)
  }
  for
    (name, originals) in [
      ("result_schema_wires", schema_wires),
      ("result_codec_cids", codec_cids),
    ] {
    @encode.key(writer, name)
    @encode.begin_array(writer)
    for original in originals {
      @encode.string_value(writer, original)
    }
    @encode.end_array(writer)
  }
  @encode.end_object(writer)
}

///|
/// Existing original ModelWork -> paired Store custody -> original Journal
/// waiting. The same checked computation/Preview supplies all private bytes.
/// This neither approves nor applies an Effect and never creates a Resident
/// Source owner to represent the multi-Source Native computation.
pub fn NativeClientMockModelWork::save_effect_review_in_original_read(
  self : NativeClientMockModelWork,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  schema_wires : Array[String],
  codec_cids : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview_identity : @publication.EffectPreviewIdentity,
  review_wire : String,
  authoring_cid : String,
  store_authority : String,
  connection : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.effect_review is None &&
    self.first_start is Some(first) &&
    self.local_observation is Some(_) &&
    materials.request == Some(self.request) &&
    physical_equal(materials.run_definition, self.definition) else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  self.capture.save_original_effect_review_in_original_read(
    first,
    self.namespace_id,
    self.principal,
    self.current_time,
    () => !self.closing && !self.closed,
    saved => self.effect_review = Some(saved),
    store,
    materials,
    invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    schema_wires,
    codec_cids,
    manifest,
    receipt,
    captured,
    preview_identity,
    review_wire,
    authoring_cid,
    store_authority,
    connection,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Persist in the captured Read after the original first-start proof. The
/// original command retains every partial Store child before the next call.
pub fn NativeLocalJournalCapture::save_original_effect_review_in_original_read(
  self : Self,
  first : NativeClientWorkFirstStart,
  namespace_id : String,
  principal : String,
  current_time : () -> String,
  owner_current : () -> Bool,
  retain : (NativeMockEffectReview) -> Unit,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  schema_wires : Array[String],
  codec_cids : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured : @publication.PublicationContract,
  preview_identity : @publication.EffectPreviewIdentity,
  review_wire : String,
  authoring_cid : String,
  store_authority : String,
  connection : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    let definition = materials.run_definition
    if materials.request != Some(first.request) ||
      first.definition_cid !=
      @publication.publication_contract_identity(definition) {
      return Err(ForeignOriginal)
    }
    let (key_bytes, key_nodes, key_depth) = native_mock_model_evidence_key_codec_limits
    mock_model_require(
      self
      .prepare_model_entry_construction(
        Some(key_bytes),
        nodes=key_nodes,
        depth=key_depth,
        additional=Some((65536, 4096, 64)),
        additional_controls=Some({
          // Closed emitter field pairs/Array, two digest/hex controls and the
          // following measurement Writer. No input body is copied here.
          record_headers: 52L,
          reference_slots: 89L,
          // Same saved-review carrier adds one constructor-inventory word.
          scalar_words: 425L,
          owned_utf16_units: 256L,
          owned_wire_bytes: 192L,
        }),
      )
      .map_err(issue => Original(issue)),
    )
    if definitions.length() != artifacts.length() ||
      definitions.length() != derivations.length() ||
      definitions.length() != orderings.length() ||
      definitions.length() != retentions.length() ||
      definitions.length() != schema_wires.length() ||
      definitions.length() != codec_cids.length() {
      return Err(ForeignOriginal)
    }
    let binding = mock_model_require(
      @publication.prepare_effect_capture_holding_binding(
        definition, invocation, definitions, artifacts, manifest, receipt, captured,
        preview_identity, store_authority, max_bytes, max_nodes, max_depth,
      ).map_err(issue => Review(Binding(issue))),
    )
    let measure = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    emit_native_mock_effect_review(
      measure,
      first.request,
      definition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      schema_wires,
      codec_cids,
      manifest,
      receipt,
      captured,
      review_wire,
      authoring_cid,
    )
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(measure)
    mock_model_require(
      self
      .prepare_model_entry_construction(
        Some(bytes),
        nodes~,
        depth~,
        // Both returned private metadata Strings survive beside Store children.
        // Checkpoint admission retains its existing separate 64KiB wire limit.
        additional_controls=Some({
          record_headers: 2L,
          reference_slots: 0L,
          scalar_words: 0L,
          owned_utf16_units: bytes.to_int64() + 65536L,
          owned_wire_bytes: 0L,
        }),
      )
      .map_err(issue => Original(issue)),
    )
    let writer = @encode.writer(bytes, nodes, depth)
    emit_native_mock_effect_review(
      writer,
      first.request,
      definition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      schema_wires,
      codec_cids,
      manifest,
      receipt,
      captured,
      review_wire,
      authoring_cid,
    )
    let continuation = @encode.finish(writer)
    guard @publication.run_definition_run_id(definition) is Ok(run_id) &&
      @publication.run_definition_lifetime(definition) is Some((_, until)) else {
      return Err(ForeignOriginal)
    }
    let created_at = current_time()
    if !@host.client_effect_run_start_current(
        materials.allowed,
        definition,
        created_at,
      ) {
      return Err(ForeignOriginal)
    }
    let checkpoint = @checkpoint.seal_checkpoint(
        {
          checkpoint_id: run_id + "/effect-review",
          continuation_state_cid: "sha256:" +
          @sha.hex(@utf8.encode(continuation)),
          subject: @checkpoint.RunUnit(
            run_id~,
            unit_id=@host.client_effect_compilation_unit_id(
              materials.compilation,
            ),
            run_definition_cid=@publication.publication_contract_identity(
              definition,
            ),
          ),
          phase: @checkpoint.Commit,
          kind: @checkpoint.EffectSet,
          required_artifact_cid: @publication.effect_preview_semantic_identity(
            preview_identity,
          ),
          review_projection_cid: "sha256:" + @sha.hex(@utf8.encode(review_wire)),
          requirements: [@checkpoint.EffectScopeApproved],
          reason_code: "effect_review",
          human_summary: "Approve the complete Effect Set",
          created_at,
          expires_at: until,
        },
        native_checkpoint_limits(),
      ).map_err(issue => Review(Checkpoint(@host.Checkpoint(issue))))
      |> mock_model_require
    let metadata = @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: continuation.length().to_int64() +
      checkpoint.wire.length().to_int64(),
      owned_wire_bytes: 0L,
    }).unwrap()
    self.save_effect_review_original_in_scope(
      first,
      definition,
      namespace_id,
      principal,
      current_time,
      owner_current,
      retain,
      store,
      materials.allowed,
      binding,
      preview_identity,
      review_wire,
      authoring_cid,
      checkpoint,
      continuation,
      {
        authorization_context_cid: @host.client_request_authority_scope_cid(
          first.request,
        ),
        environment_binding_cid: @host.prepared_client_effect_computation_environment_cid(
          materials.prepared,
        ),
      },
      connection,
      max_bytes,
      max_nodes,
      max_depth,
      metadata,
    )
  } catch {
    NativeMockModelStop(issue) => Err(issue)
    _ => Err(Encoding)
  }
}
