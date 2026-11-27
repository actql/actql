///|
/// Admitted private continuation of the exact waiting Run. The adopted
/// read owner keeps this data before any review disclosure or decision.
pub struct ClientEffectSavedReviewReference {
  waiting : ClientEffectWaitingOriginal
  fields : @decode.ObjectView
  preview : @publication.EffectPreviewIdentity
  preview_original : @canonical.CanonicalValue
  preview_wire : String
  capture_cid : String
  unit_definition_cid : String?
  program_id : String?
}

///|
/// The exact authenticated private holdings and their admitted public Review.
pub struct ClientEffectSavedReviewConfirmation {
  reference : ClientEffectSavedReviewReference
  wire : String
  captured : String
}

///|
/// Restore authenticated continuation data from the selected waiting
/// Checkpoint. The caller funds the parser, both hashes and Preview decoder
/// in the same existing Read before passing the authenticated wire.
pub fn admit_client_effect_saved_review_reference(
  original : ClientEffectWaitingOriginal,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectSavedReviewReference, ClientCheckpointJournalIssue] {
  guard wire.length() > 0 && wire.length() <= max_bytes else {
    return Err(InvalidMaterial)
  }
  let bytes = @utf8.encode(wire)
  let checkpoint = original.checkpoint.artifact.checkpoint
  guard bytes.length() <= max_bytes &&
    "sha256:" + @sha.hex(bytes) == checkpoint.continuation_state_cid &&
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "version", "provider", "request_scope_cid", "authority_scope_cid", "request_id",
      "run_definition_wire", "invocation_wire", "result_manifest_wire", "computation_receipt_wire",
      "captured_run_cid", "preview_wire", "review_projection_cid", "authoring_context_cid",
      "unit_definition_cid", "program_id", "result_definition_wires", "result_artifact_wires",
      "result_derivation_wires", "result_ordering_wires", "result_retention_wires",
      "result_schema_wires", "result_codec_cids",
    ])
    is Ok(fields) else {
    return Err(InvalidMaterial)
  }
  let request = original.run.request
  let definition = original.run.definition
  let definition_cid = @publication.publication_contract_identity(definition)
  guard client_checkpoint_text(fields, "version") ==
    Some("actql-python-local-effect-review-reference/0.1") &&
    client_checkpoint_text(fields, "provider") ==
    Some("python-local-project-mock") &&
    client_checkpoint_text(fields, "request_scope_cid") ==
    Some(client_request_scope_cid(request)) &&
    client_checkpoint_text(fields, "authority_scope_cid") ==
    Some(client_request_authority_scope_cid(request)) &&
    client_checkpoint_text(fields, "request_id") ==
    Some(client_request_caller_id(request)) &&
    client_checkpoint_text(fields, "run_definition_wire") ==
    Some(@publication.publication_contract_json(definition)) &&
    client_checkpoint_text(fields, "authoring_context_cid") is Some(authoring) &&
    valid_client_request_cid(authoring) &&
    client_checkpoint_text(fields, "captured_run_cid") is Some(capture_cid) &&
    valid_client_request_cid(capture_cid) &&
    client_checkpoint_text(fields, "review_projection_cid") ==
    Some(checkpoint.review_projection_cid) &&
    client_checkpoint_text(fields, "preview_wire") is Some(preview_wire) &&
    @publication.admit_effect_preview_identity_with_original(
      preview_wire, definition_cid, authoring, max_bytes, max_nodes, max_depth,
    )
    is Ok((preview, preview_original)) &&
    @publication.effect_preview_semantic_identity(preview) ==
    checkpoint.required_artifact_cid else {
    return Err(InvalidMaterial)
  }
  let count = original.checkpoint.declared_results.length()
  for
    field in [
      "result_definition_wires", "result_artifact_wires", "result_derivation_wires",
      "result_ordering_wires", "result_retention_wires", "result_schema_wires", "result_codec_cids",
    ] {
    guard @decode.lookup(fields, field) is Some(cursor) &&
      @decode.array_length(cursor) == Some(count) else {
      return Err(InvalidMaterial)
    }
  }
  let unit_definition_cid = match @decode.field(fields, "unit_definition_cid") {
    Missing => None
    Present(value) =>
      match @decode.text(value) {
        Ok(cid) if valid_client_request_cid(cid) => Some(cid)
        _ => return Err(InvalidMaterial)
      }
    ExplicitNull => return Err(InvalidMaterial)
  }
  let program_id = match @decode.field(fields, "program_id") {
    Missing => None
    Present(value) => match @decode.text(value) {
      Ok(name) if !name.is_empty() && !name.contains("\u{0000}") &&
        @scalar.admit_utf8_length(name, 512) is Ok(_) => Some(name)
      _ => return Err(InvalidMaterial)
    }
    ExplicitNull => return Err(InvalidMaterial)
  }
  Ok({
    waiting: original,
    fields,
    preview,
    preview_original,
    preview_wire,
    capture_cid,
    unit_definition_cid, program_id,
  })
}

///|
/// Coordinates of the exact waiting Checkpoint. Only an already admitted
/// same-Store Read can obtain the private evidence key's preimage.
pub fn ClientEffectWaitingOriginal::review_opening(
  self : ClientEffectWaitingOriginal,
  adoption : String,
  binding : String,
) -> Result[(String, String, String, Bytes), ClientCheckpointJournalIssue] {
  if self.run.publication_binding != Some(binding) {
    return Err(InvalidMaterial)
  }
  let checkpoint = self.checkpoint.artifact
  client_local_private_evidence_key_preimage(adoption, binding, EffectReviewKey)
  .map(preimage => {
    (
      checkpoint.checkpoint_cid,
      checkpoint.checkpoint.continuation_state_cid,
      checkpoint.checkpoint.review_projection_cid,
      preimage,
    )
  })
  .map_err(_ => InvalidMaterial)
}

///|
/// A public reader authenticates only the selected public holding. The
/// Checkpoint already binds the original Preview/Review identity. Opening
/// execution continuation, capture and private Preview is a separate use.
pub fn ClientEffectWaitingOriginal::confirm_public_review(
  self : ClientEffectWaitingOriginal,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientCheckpointJournalIssue] {
  let checkpoint = self.checkpoint.artifact.checkpoint
  guard @publication.admit_run_evidence_value(
      "review_projection", wire, max_bytes, max_nodes, max_depth,
    )
    is Ok(review) &&
    @publication.run_evidence_value_identity(review) ==
    checkpoint.review_projection_cid &&
    @publication.effect_review_projection_binding_facts(review)
    is Some((preview, _, authority, claims)) &&
    preview == checkpoint.required_artifact_cid &&
    authority == client_request_authority_scope_cid(self.run.request) &&
    claims == ["effect_scope_approved"] else {
    return Err(InvalidMaterial)
  }
  Ok(wire)
}

///|
/// The retained continuation already binds the admitted Preview to the
/// Checkpoint/Run. Select separate encrypted cells for the same Store.
pub fn ClientEffectSavedReviewReference::holding_coordinates(
  self : ClientEffectSavedReviewReference,
  authority : String,
  namespace_id : String,
  device : UInt64,
  inode : UInt64,
) -> Result[(String, String, String, String), ClientCheckpointJournalIssue] {
  guard client_publication_store_binding_body(
      namespace_id, authority, device, inode,
    )
    is Ok(binding) &&
    self.waiting.run.publication_binding == Some(binding) &&
    @publication.effect_computation_record_holding_cid(
      self.waiting.run.definition,
      authority,
    )
    is Some(capture_key) &&
    @publication.effect_preview_private_holding_cid(self.preview, authority)
    is Some(preview_key) else {
    return Err(InvalidMaterial)
  }
  Ok(
    (
      capture_key,
      self.capture_cid,
      preview_key,
      @publication.effect_preview_semantic_identity(self.preview),
    ),
  )
}

///|
/// Complete the exact authenticated cells before returning Review bytes.
/// Signature, resolution/claim and ordinary Result delivery are independent.
pub fn ClientEffectSavedReviewReference::confirm_review_original(
  self : ClientEffectSavedReviewReference,
  checkpoint : String,
  preview : String,
  capture : String,
  review : String,
  max_review_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectSavedReviewConfirmation, ClientCheckpointJournalIssue] {
  guard preview == self.preview_wire &&
    @scalar.admit_utf8_length(review, max_review_bytes) is Ok(_) &&
    @checkpoint.confirm_checkpoint_persisted(
      self.waiting.checkpoint.artifact,
      checkpoint,
    )
    is Ok(_) &&
    @publication.admit_publication_contract(
      "captured_run", capture, max_bytes, max_nodes, max_depth,
    )
    is Ok(captured) &&
    @publication.publication_contract_identity(captured) == self.capture_cid else {
    return Err(InvalidMaterial)
  }
  let request = self.waiting.run.request
  let checkpoint = self.waiting.checkpoint.artifact.checkpoint
  guard @publication.admit_effect_review_projection(
      self.preview,
      self.preview_wire,
      review,
      client_request_authority_scope_cid(request),
      ["effect_scope_approved"],
      client_local_effect_review_redaction_policy_cid(),
      max_review_bytes,
      max_nodes,
      max_depth,
      preview_limits=Some((max_bytes, max_nodes, max_depth)),
    )
    is Ok(admitted) &&
    @publication.run_evidence_value_identity(admitted) ==
    checkpoint.review_projection_cid else {
    return Err(InvalidMaterial)
  }
  Ok({ reference: self, wire: review, captured: capture, })
}

///|
/// Public Review bytes return only after the complete original confirmation.
pub fn ClientEffectSavedReviewReference::confirm_review(
  self : ClientEffectSavedReviewReference,
  checkpoint : String,
  preview : String,
  capture : String,
  review : String,
  max_review_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientCheckpointJournalIssue] {
  self
  .confirm_review_original(
    checkpoint, preview, capture, review, max_review_bytes, max_bytes, max_nodes,
    max_depth,
  )
  .map(original => original.wire)
}
