///|
/// Originals recovered from the authenticated capture and continuation in one
/// adopted Read. This is computation and publication DATA only.
pub struct ClientEffectSavedComputation {
  preview : ClientEffectSavedReviewReference
  invocation : @publication.PublicationContract
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  capture : @publication.PreparedCapturedEffectRun
  retained : @publication.RetainedEffectfulComputation
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  derivations : Array[@publication.PublicationContract]
  orderings : Array[@publication.PublicationContract]
  retentions : Array[@publication.PublicationContract]
  schemas : Array[String]
  codecs : Array[String]
}

///|
fn read_client_effect_saved_contract(
  wire : String,
  kind : String,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
) -> Result[@publication.PublicationContract, ClientCheckpointJournalIssue] {
  guard @scalar.admit_utf8_length(wire, limits.max_wire_bytes) is Ok(bytes) &&
    bytes > 0 &&
    fund(bytes, Int::min(limits.max_nodes, bytes), limits.max_depth) else {
    return Err(ClientCheckpointJournalIssue::InvalidMaterial)
  }
  @publication.admit_publication_contract(
    kind,
    wire,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(_ => InvalidMaterial)
}

///|
/// Restore the original computation before any signed decision or public
/// Result publication. The caller owns the same Read and pays the actual
/// input/constructor forest through the callbacks. No Source is invoked.
pub fn restore_client_effect_saved_computation(
  original : ClientEffectSavedReviewReference,
  authenticated_capture : String,
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
  work : (Int) -> Bool,
) -> Result[ClientEffectSavedComputation, ClientCheckpointJournalIssue] {
  let fields = original.fields
  fn single(field, kind) {
    guard client_checkpoint_text(fields, field) is Some(wire) else {
      return Err(ClientCheckpointJournalIssue::InvalidMaterial)
    }
    read_client_effect_saved_contract(wire, kind, limits, fund)
  }
  let count = original.waiting.checkpoint.declared_results.length()
  if count < 1 || count > 128 {
    return Err(ClientCheckpointJournalIssue::InvalidMaterial)
  }
  fn texts(field) {
    guard @decode.lookup(fields, field) is Some(cursor) &&
      @decode.array_length(cursor) == Some(count) else {
      return Err(ClientCheckpointJournalIssue::InvalidMaterial)
    }
    let bodies = Array(capacity=count)
    for ordinal in 0..<count {
      guard @decode.element_at(cursor, ordinal) is Some(body) &&
        @decode.text(body) is Ok(wire) &&
        !wire.is_empty() else {
        return Err(ClientCheckpointJournalIssue::InvalidMaterial)
      }
      bodies.push(wire)
    }
    Ok(bodies)
  }
  fn contracts(field, kind) {
    let texts = match texts(field) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let bodies = Array(capacity=count)
    for wire in texts {
      match read_client_effect_saved_contract(wire, kind, limits, fund) {
        Ok(value) => bodies.push(value)
        Err(issue) => return Err(issue)
      }
    }
    Ok(bodies)
  }
  guard fund(0, 39 + 14 * count, 1) &&
    single("invocation_wire", "run_invocation") is Ok(invocation) &&
    single("result_manifest_wire", "result_manifest") is Ok(manifest) &&
    single("computation_receipt_wire", "run_receipt") is Ok(receipt) &&
    read_client_effect_saved_contract(
      authenticated_capture, "captured_run", limits, fund,
    )
    is Ok(captured) &&
    @publication.publication_contract_identity(captured) == original.capture_cid &&
    @publication.publication_contract_json(captured) == authenticated_capture &&
    contracts("result_definition_wires", "result_definition") is Ok(definitions) &&
    contracts("result_artifact_wires", "result_artifact") is Ok(artifacts) &&
    contracts("result_derivation_wires", "derivation_evidence")
    is Ok(derivations) &&
    contracts("result_ordering_wires", "ordering_evidence") is Ok(orderings) &&
    contracts("result_retention_wires", "result_retention_policy")
    is Ok(retentions) &&
    texts("result_schema_wires") is Ok(schemas) &&
    texts("result_codec_cids") is Ok(codecs) &&
    codecs.all(valid_client_request_cid) else {
    return Err(ClientCheckpointJournalIssue::InvalidMaterial)
  }
  guard @publication.publication_contract_wire_usage(captured)
    is Some((bytes, nodes, depth)) &&
    fund(bytes, nodes, depth) &&
    @publication.prepare_recovered_captured_effect_run(
      captured,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      work,
    )
    is Ok(capture) &&
    @publication.admit_retained_effectful_computation(
      original.waiting.run.definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      captured,
      original.preview,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      prepared=Some(capture),
    )
    is Ok(retained) else {
    return Err(ClientCheckpointJournalIssue::InvalidMaterial)
  }
  Ok({
    preview: original,
    invocation,
    manifest,
    receipt,
    capture,
    retained,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    schemas,
    codecs,
  })
}
