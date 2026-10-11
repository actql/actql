///|
pub(all) enum ResidentEffectOriginalReviewIssue {
  Unavailable
  InvalidLimits
  EvidenceDenied
  BindingMismatch
  MalformedContinuation
  Journal(@journal.NativeRemoteJournalIssue)
  RunBinding(@host.ClientEffectCheckpointBindingIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Capture(@publication.PublicationContractIssue)
  Preview(@publication.EffectPreviewIdentityIssue)
  Chain(@publication.RunEvidenceChainIssue)
}

///|
priv struct OriginalEffectReviewFields {
  captured_wire : String
  review_wire : String
  authoring_cid : String
  original_computation_wire : String?
}

///|
fn original_review_text(
  value : @canonical.CanonicalValue,
  key : String,
) -> String? {
  match @canonical.object_field(value, key) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}

///|
/// This codec joins saved bytes to independently selected original facts. It
/// cannot prove issuance: only the caller's journal and authenticated Store
/// readback supply that evidence. It preserves string values without NFC.
fn original_effect_review_fields(
  wire : String,
  run_cid : String,
  unit : String,
  binding_wire : String,
  authority : String,
  request : Array[(String, String)],
  checkpoint : @checkpoint.SealedCheckpoint,
  limits : @checkpoint.WireLimits,
) -> Result[OriginalEffectReviewFields, ResidentEffectOriginalReviewIssue] {
  if limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 262144 ||
    limits.max_nodes < 1 ||
    limits.max_nodes > 10000 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 {
    return Err(InvalidLimits)
  }
  if @utf8.encode(wire).length() > limits.max_wire_bytes {
    return Err(InvalidLimits)
  }
  let value = try {
    let value = @canonical.from_json(
      @json.parse(wire),
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    // Exact canonical readback also refuses duplicate keys collapsed by the
    // JSON parser. No normalization or replacement of the original is allowed.
    if @canonical.stringify_value(
        value,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) !=
      wire {
      return Err(MalformedContinuation)
    }
    value
  } catch {
    _ => return Err(MalformedContinuation)
  }
  guard @canonical.object_field_count(value) == Some(5) &&
    original_review_text(value, "version") ==
    Some("actql-installed-effect-continuation/0.1") &&
    original_review_text(value, "run_definition_cid") == Some(run_cid) &&
    original_review_text(value, "unit_id") == Some(unit) &&
    original_review_text(value, "preview_cid") ==
    Some(checkpoint.checkpoint.required_artifact_cid) &&
    @canonical.object_field(value, "provider") is Some(provider) &&
    (
      @canonical.object_field_count(provider) == Some(6) ||
      (
        @canonical.object_field_count(provider) == Some(7) &&
        original_review_text(provider, "original_computation_wire") is Some(_)
      )
    ) &&
    original_review_text(provider, "retained_input_binding") ==
    Some(binding_wire) &&
    original_review_text(provider, "store_authority_cid") == Some(authority) &&
    @canonical.object_field(provider, "request") is Some(saved_request) &&
    @canonical.object_field_count(saved_request) == Some(7) &&
    request.length() == 7 else {
    return Err(BindingMismatch)
  }
  for (name, expected) in request {
    if original_review_text(saved_request, name) != Some(expected) {
      return Err(BindingMismatch)
    }
  }
  guard original_review_text(provider, "captured_run_wire")
    is Some(captured_wire) &&
    original_review_text(provider, "review_wire") is Some(review_wire) &&
    original_review_text(provider, "authoring_context_cid")
    is Some(authoring_cid) else {
    return Err(MalformedContinuation)
  }
  if "sha256:" + @sha.hex(@utf8.encode(wire)) !=
    checkpoint.checkpoint.continuation_state_cid ||
    "sha256:" + @sha.hex(@utf8.encode(review_wire)) !=
    checkpoint.checkpoint.review_projection_cid {
    return Err(BindingMismatch)
  }
  Ok({
    captured_wire,
    review_wire,
    authoring_cid,
    original_computation_wire: original_review_text(
      provider, "original_computation_wire",
    ),
  })
}

///|
/// Parsing proves only contract shape. The caller must join this complete
/// original snapshot to authenticated Checkpoint bytes, independent original
/// context and the existing whole computation-chain Owner before using it.
fn original_computation_evidence_fields(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  OriginalResidentEffectComputationEvidence,
  ResidentEffectOriginalReviewIssue,
] {
  let value = try {
    let value = @canonical.from_json(
      @json.parse(wire),
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    if @canonical.stringify_value(
        value,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) !=
      wire {
      return Err(MalformedContinuation)
    }
    value
  } catch {
    _ => return Err(MalformedContinuation)
  }
  if @canonical.object_field_count(value) != Some(6) {
    return Err(BindingMismatch)
  }
  let contracts : Array[@publication.PublicationContract] = []
  for
    (field, kind) in [
      ("run_definition_wire", "run_definition"),
      ("invocation_wire", "run_invocation"),
      ("result_definition_wire", "result_definition"),
      ("result_artifact_wire", "result_artifact"),
      ("result_manifest_wire", "result_manifest"),
      ("computation_receipt_wire", "run_receipt"),
    ] {
    guard original_review_text(value, field) is Some(original) else {
      return Err(BindingMismatch)
    }
    match
      @publication.admit_publication_contract(
        kind,
        original,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => contracts.push(value)
      Err(issue) => return Err(Capture(issue))
    }
  }
  Ok({
    run: contracts[0],
    invocation: contracts[1],
    definition: contracts[2],
    artifact: contracts[3],
    manifest: contracts[4],
    receipt: contracts[5],
  })
}

///|
/// Read the original confirmed review through this genuine consumer context.
/// The journal selects the sealed Checkpoint; Store selects its original
/// continuation bytes. No candidate wire, new Preview, Provider read, Run,
/// reservation or approval is issued. Existing custody remains with its Owners.
/// This is not restoration of a physical Review/Effect execution handle.
pub fn ResidentEffectReviewInputContext::read_original_review_projection(
  self : ResidentEffectReviewInputContext,
  journal : @journal.Journal,
  store : @publication_store.Store,
  authority : String,
  crypto : @signature.Library,
  key : Bytes,
  limits : @checkpoint.WireLimits,
  authorize_evidence_read : () -> Bool,
) -> Result[
  (@remote.RemoteEffectCheckpointReport, String),
  ResidentEffectOriginalReviewIssue,
] {
  if key.length() != 32 ||
    limits.max_wire_bytes < 1 ||
    limits.max_wire_bytes > 262144 ||
    limits.max_nodes < 1 ||
    limits.max_nodes > 10000 ||
    limits.max_depth < 1 ||
    limits.max_depth > 64 {
    return Err(InvalidLimits)
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  guard self.facts(journal) is Some(facts) &&
    facts.materials.request == Some(self.request) else {
    return Err(Unavailable)
  }
  let report = match
    journal.effect_checkpoint_report(self.holder.request, limits) {
    Ok((report, _)) => report
    Err(issue) => return Err(Journal(issue))
  }
  let original = @remote.remote_effect_checkpoint_report_checkpoint(report)
  let checkpoint = match
    @host.admit_client_effect_review_checkpoint_binding(
      facts.materials.allowed,
      facts.materials.run_definition,
      original.wire,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RunBinding(issue))
  }
  let custody = match
    store.restore_confirmed_effect_checkpoint_custody(
      checkpoint, authority, crypto, key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  let continuation = match custody.confirm() {
    Ok((_, wire)) => wire
    Err(issue) => return Err(Store(issue))
  }
  let fields = match
    original_effect_review_fields(
      continuation,
      @publication.publication_contract_identity(facts.materials.run_definition),
      @host.client_effect_compilation_unit_id(facts.materials.compilation),
      @remote.remote_input_binding_body(self.holder.binding),
      authority,
      [
        (
          "authority_scope_cid",
          @host.client_request_authority_scope_cid(self.request),
        ),
        ("request_id", @host.client_request_caller_id(self.request)),
        (
          "logical_request_scope_cid",
          @host.client_request_scope_cid(self.request),
        ),
        (
          "intent_fingerprint_cid",
          @host.client_request_intent_cid(self.request),
        ),
        (
          "program_definition_cid",
          @host.client_request_program_cid(self.request),
        ),
        (
          "parameter_values_cid",
          @host.client_request_parameters_cid(self.request),
        ),
        (
          "caller_input_intent_cid",
          @host.client_request_input_cid(self.request),
        ),
      ],
      checkpoint,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    @publication.admit_publication_contract(
      "captured_run",
      fields.captured_wire,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let identity = match
    @publication.admit_effect_preview_identity(
      fields.review_wire,
      @publication.publication_contract_identity(facts.materials.run_definition),
      fields.authoring_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preview(issue))
  }
  if @publication.effect_preview_semantic_identity(identity) !=
    checkpoint.checkpoint.required_artifact_cid {
    return Err(BindingMismatch)
  }
  if fields.original_computation_wire is Some(original_wire) {
    let original = match
      original_computation_evidence_fields(original_wire, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_json(original.run) !=
      @publication.publication_contract_json(facts.materials.run_definition) ||
      @publication.publication_contract_json(original.invocation) !=
      @publication.publication_contract_json(facts.producer.invocation) {
      return Err(BindingMismatch)
    }
    match
      @publication.validate_effectful_computation_evidence_chain(
        original.run,
        original.invocation,
        [original.definition],
        [original.artifact],
        original.manifest,
        original.receipt,
        captured,
        identity,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Chain(issue))
    }
  }
  // A projection from an older record remains historical disclosure evidence,
  // not a full restored computation. Missing originals are never reconstructed
  // from current values or treated as authority to execute another Effect.
  let preview = match
    store.restore_effect_preview_custody(
      identity,
      fields.review_wire,
      fields.authoring_cid,
      authority,
      crypto,
      key,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Store(issue))
  }
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.facts(journal) is None {
    return Err(Unavailable)
  }
  // Recheck the original immutable report and both physical readbacks after
  // the callback. Authorization may have closed or retired those Owners.
  match journal.effect_checkpoint_report(self.holder.request, limits) {
    Ok((current, _)) if @remote.remote_effect_checkpoint_report_json(current) ==
      @remote.remote_effect_checkpoint_report_json(report) => ()
    Ok(_) => return Err(BindingMismatch)
    Err(issue) => return Err(Journal(issue))
  }
  match custody.confirm() {
    Ok((_, wire)) if wire == continuation => ()
    Ok(_) => return Err(BindingMismatch)
    Err(issue) => return Err(Store(issue))
  }
  let original_review = match preview.confirm() {
    Ok((_, wire)) if wire == fields.review_wire => wire
    Ok(_) => return Err(BindingMismatch)
    Err(issue) => return Err(Store(issue))
  }
  // The final Store confirmation can outlive its preceding permission read.
  // Revalidate before disclosing the original bytes and retain custody on deny.
  if !authorize_evidence_read() {
    return Err(EvidenceDenied)
  }
  if self.facts(journal) is None {
    return Err(Unavailable)
  }
  Ok((report, original_review))
}
