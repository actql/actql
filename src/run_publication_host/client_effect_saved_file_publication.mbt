///|
/// Publication occurrence for the admitted saved Effect completion. The
/// physical publisher independently checks the original request and index.
pub struct ClientEffectSavedFilePublication {
  completion : ClientEffectSavedFileCompletion
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
  target : String
  limits : @checkpoint.WireLimits
}

///|
pub fn ClientEffectSavedFileCompletion::prepare_publication(
  self : ClientEffectSavedFileCompletion,
  account : @authorization.AdmittedAccountConfiguration,
  control : @authorization.AccessTuple,
  run_namespace : String,
  target : String,
  binding : String,
  attempt_id : String,
  fence : String,
  idempotency : String?,
  at : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  ClientEffectSavedFilePublication,
  ClientEffectResolutionOriginalIssue,
] {
  let application = self.application
  let computation = application.computation
  let run = computation.preview.waiting.run
  let scope = client_request_authority_scope_cid(run.request)
  guard application.principal == control.principal &&
    account.configuration_cid() == application.account_cid &&
    @authorization.evaluate_account(account, {
      ..control,
      resource: "run",
      operation: "publish",
    })
    is @authorization.Allow(_) &&
    @publication.run_definition_namespace(run.definition) == Some(run_namespace) &&
    run.publication_binding == Some(binding) &&
    @publication.issue_publication_request(
      run.definition,
      computation.definitions,
      run_namespace,
      scope,
      account.configuration_cid(),
      target,
      at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok(request) &&
    @publication.issue_publication_attempt(
      request,
      run.definition,
      attempt_id,
      fence,
      idempotency,
      at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok(attempt) else {
    return Err(InvalidOriginal)
  }
  Ok({ completion: self, request, attempt, target, limits, })
}

///|
pub fn ClientEffectSavedFilePublication::contracts(
  self : ClientEffectSavedFilePublication,
) -> (
  @publication.PublicationContract,
  @publication.PublicationContract,
  String,
) {
  (self.request, self.attempt, self.target)
}

///|
pub fn ClientEffectSavedFilePublication::payload_intent(
  self : ClientEffectSavedFilePublication,
  ordinal : Int,
  store : String,
  material : String,
  maximum : Int64,
) -> Result[
  @payload.PublicationPayloadRequest,
  ClientEffectResolutionOriginalIssue,
] {
  let computation = self.completion.application.computation
  guard store == self.target &&
    @publication.retained_effectful_computation_result_at(
      computation.retained,
      ordinal,
    )
    is Some(snapshot) &&
    computation.orderings.get(ordinal) is Some(ordering) &&
    computation.codecs.get(ordinal) is Some(codec) else {
    return Err(InvalidOriginal)
  }
  let (definition, logical, schema, rows, bytes) = @publication.captured_result_snapshot_payload_identity(
    snapshot,
  )
  guard bytes > 0 &&
    bytes.to_int64() <= maximum &&
    @payload.prepare_publication_payload_request(
      store,
      @publication.publication_contract_identity(self.attempt),
      material,
      definition,
      logical,
      schema,
      @publication.publication_contract_identity(ordering),
      codec,
      bytes.to_int64(),
      rows.to_int64(),
    )
    is Ok(request) else {
    return Err(InvalidOriginal)
  }
  Ok(request)
}

///|
pub fn ClientEffectSavedFilePublication::snapshot(
  self : ClientEffectSavedFilePublication,
  ordinal : Int,
) -> @publication.CapturedResultSnapshot? {
  @publication.retained_effectful_computation_result_at(
    self.completion.application.computation.retained,
    ordinal,
  )
}

///|
pub fn ClientEffectSavedFilePublication::prepare_commit(
  self : ClientEffectSavedFilePublication,
  bindings : Array[@publication.PublicationContract],
  committed_at : String,
  max_workspace : Int,
) -> Result[
  (@publication.PublicationContract, @publication.PublicationCommitPreparation),
  ClientEffectResolutionOriginalIssue,
] {
  let completion = self.completion
  let computation = completion.application.computation
  let limits = self.limits
  guard bindings.length() == completion.result_count() &&
    @publication.issue_public_index_entry(
      computation.preview.waiting.run.definition,
      computation.invocation,
      computation.manifest,
      completion.final_receipt,
      @publication.prepared_captured_effect_run_contract(computation.capture),
      bindings,
      self.request,
      self.attempt,
      committed_at,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok(index) &&
    @publication.prepare_retained_effectful_publication_commit_check(
      completion.evidence,
      bindings,
      self.request,
      self.attempt,
      index,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      max_workspace,
    )
    is Ok(commit) else {
    return Err(InvalidOriginal)
  }
  Ok((index, commit))
}

///|
pub fn ClientEffectSavedFilePublication::result_count(
  self : ClientEffectSavedFilePublication,
) -> Int {
  self.completion.result_count()
}

///|
pub fn ClientEffectSavedFilePublication::original_evidence(
  self : ClientEffectSavedFilePublication,
) -> (
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.PublicationContract,
) {
  let original = self.completion.application.computation
  (
    original.manifest,
    self.completion.final_receipt,
    @publication.prepared_captured_effect_run_contract(original.capture),
  )
}

///|
pub fn ClientEffectSavedFilePublication::bind_sealed_payload(
  self : ClientEffectSavedFilePublication,
  ordinal : Int,
  payload : @payload.PublicationPayloadRecord,
) -> Result[
  @publication.PublicationContract,
  ClientEffectResolutionOriginalIssue,
] {
  let computation = self.completion.application.computation
  let run = computation.preview.waiting.run
  let request = @payload.publication_payload_record_request(payload)
  let material = @payload.publication_payload_material_identity(request)
  guard self.snapshot(ordinal) is Some(snapshot) &&
    computation.orderings.get(ordinal) is Some(ordering) &&
    computation.retentions.get(ordinal) is Some(retention) &&
    computation.codecs.get(ordinal) is Some(codec) &&
    computation.schemas.get(ordinal) is Some(schema) &&
    @payload.publication_payload_record_state(payload) is @payload.Sealed &&
    @payload.publication_payload_record_generation(payload) is Some(generation) &&
    self.payload_intent(ordinal, self.target, material, generation.size)
    is Ok(expected) &&
    @payload.publication_payload_request_identity(request) ==
    @payload.publication_payload_request_identity(expected) &&
    @payload.publication_payload_record_actual_bytes(payload) == generation.size else {
    return Err(InvalidOriginal)
  }
  let digest = @payload.publication_payload_record_digest(payload)
  guard digest.has_prefix("sha256:") &&
    digest.length() == 71 &&
    generation.size > 0L &&
    generation.size <= 2147483647L else {
    return Err(InvalidOriginal)
  }
  @publication.issue_durable_result_binding_from_snapshot(
    snapshot,
    run.definition,
    computation.invocation,
    ordering,
    retention,
    codec,
    schema,
    material,
    self.target,
    generation.size.to_int(),
    digest[7:].to_owned(),
    65536,
    4096,
    64,
  ).map_err(_ => InvalidOriginal)
}

///|
/// The wire is the same retained schema already selected by payload binding.
pub fn ClientEffectSavedFilePublication::result_schema(
  self : ClientEffectSavedFilePublication,
  ordinal : Int,
  wire : Bool,
) -> String? {
  guard self.snapshot(ordinal) is Some(snapshot) &&
    self.completion.application.computation.schemas.get(ordinal) is Some(schema) else {
    return None
  }
  let (_, _, identity, _, _) = @publication.captured_result_snapshot_payload_identity(
    snapshot,
  )
  Some(if wire { schema } else { identity })
}
