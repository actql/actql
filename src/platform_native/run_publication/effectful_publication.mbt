///|
/// SAME admitted Effectful completion and its original Result contracts.
/// This is DATA, not a new Client Request, execution, authority or payload ACK.
/// Caller arrays remain borrowed through the synchronous publication call.
pub(all) struct NativeEffectfulPublicationEvidence {
  final_evidence : @publication.EffectfulFinalRunEvidence
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  derivations : Array[@publication.PublicationContract]
  orderings : Array[@publication.PublicationContract]
  retentions : Array[@publication.PublicationContract]
  bindings : Array[@publication.PublicationContract]
  binding_schema_wires : Array[String]
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  captured_run : @publication.PublicationContract
}

///|
fn require_effectful_publication_materials(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
) -> Result[Unit, NativeRunPublicationIssue] {
  if evidence.bindings.length() != evidence.binding_schema_wires.length() {
    return Err(InvalidConfiguration)
  }
  @publication.validate_retained_effectful_publication_materials(
    evidence.final_evidence,
    evidence.run_definition,
    evidence.invocation,
    evidence.definitions,
    evidence.artifacts,
    evidence.derivations,
    evidence.orderings,
    evidence.retentions,
    evidence.manifest,
    evidence.receipt,
    evidence.captured_run,
    limits=Some((service.max_wire_bytes, service.max_nodes, service.max_depth)),
  ).map_err(issue => Commit(issue))
}

///|
/// Issue only the original Run's publication-operation request/attempt before
/// payload persistence. Business Request/Model/Source originals are unchanged.
pub fn prepare_effectful_run_publication_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
) -> Result[NativeRunPublicationPreparation, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let request = match
    issue_request(
      service,
      evidence.run_definition,
      evidence.definitions,
      intent,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    authorize(
      service,
      intent,
      evidence.run_definition,
      request,
      "request",
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let attempt = match
    issuance_result(
      @publication.issue_publication_attempt(
        request,
        evidence.run_definition,
        occurrence.attempt_id,
        occurrence.fence_cid,
        occurrence.external_idempotency_key,
        occurrence.started_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ request, attempt, })
}

///|
fn validate_existing_effectful_commit(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  request : @publication.PublicationContract,
  index : @publication.PublicationContract,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let projected = match
    projection_result(@publication.project_public_index_read(index)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let stored_request = match
    store_result(
      service.store.read_publication_contract(
        "publication_request",
        projected.publication_request_cid,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_identity(stored_request) !=
    @publication.publication_contract_identity(request) {
    return Err(CommitConflict)
  }
  let stored_attempt = match
    store_result(
      service.store.read_publication_contract(
        "publication_attempt",
        projected.publication_attempt_cid,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let checked = @publication.validate_retained_effectful_publication_commit(
    evidence.final_evidence,
    evidence.bindings,
    stored_request,
    stored_attempt,
    index,
  ).map_err(issue => {
    NativeRunPublicationIssue::Store(@store.EffectfulPublication(issue))
  })
  match checked {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok({
    public_index_entry_cid: @publication.publication_contract_identity(index),
    publication_request_cid: projected.publication_request_cid,
    publication_attempt_cid: projected.publication_attempt_cid,
    committed: false,
    idempotent: true,
  })
}

///|
fn inspect_existing_effectful_commit(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  request : @publication.PublicationContract,
) -> Result[NativeRunPublicationResult?, NativeRunPublicationIssue] {
  let existing = match
    store_result(
      service.store.inspect_committed_publication(
        intent.namespace_id,
        intent.authority_scope_cid,
        @publication.publication_contract_identity(evidence.run_definition),
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match existing {
    None => Ok(None)
    Some(index) => {
      // This is a stored validator-admitted index, including a legitimate
      // earlier attempt of this original request. Do not expose unvalidated
      // retained references to the Host publication callback.
      let validated = match
        validate_existing_effectful_commit(service, evidence, request, index) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        authorize(
          service,
          intent,
          evidence.run_definition,
          request,
          "return_committed",
          Some(index),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      Ok(Some(validated))
    }
  }
}

///|
fn commit_new_effectful_run_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  committed_at : String,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let index = match
    issuance_result(
      @publication.issue_public_index_entry(
        evidence.run_definition,
        evidence.invocation,
        evidence.manifest,
        evidence.receipt,
        evidence.captured_run,
        evidence.bindings,
        request,
        attempt,
        committed_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  (service.commit_guard)(() => {
    match
      authorize(
        service,
        intent,
        evidence.run_definition,
        request,
        "commit",
        Some(index),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let committed = service.store.commit_publication(
      evidence.run_definition,
      evidence.invocation,
      evidence.definitions,
      evidence.artifacts,
      evidence.derivations,
      evidence.orderings,
      evidence.retentions,
      evidence.bindings,
      evidence.binding_schema_wires,
      evidence.manifest,
      evidence.receipt,
      evidence.captured_run,
      request,
      attempt,
      index,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
      effectful=Some(evidence.final_evidence),
    )
    match committed {
      Ok(value) =>
        Ok({
          public_index_entry_cid: value.public_index_entry_cid,
          publication_request_cid: @publication.publication_contract_identity(
            request,
          ),
          publication_attempt_cid: @publication.publication_contract_identity(
            attempt,
          ),
          committed: value.committed,
          idempotent: value.idempotent,
        })
      Err(@store.PublicationCommitConflict) =>
        match
          inspect_existing_effectful_commit(service, evidence, intent, request) {
          Ok(Some(value)) => Ok(value)
          Ok(None) => Err(CommitConflict)
          Err(issue) => Err(issue)
        }
      Err(issue) => Err(Store(issue))
    }
  })
}

///|
/// Commit a prepared occurrence after every Result payload and Run-bound
/// evidence contract exists. The preparation is re-derived and compared, so
/// a foreign request or attempt cannot be substituted between the two phases.
pub fn commit_prepared_effectful_run_publication_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  preparation : NativeRunPublicationPreparation,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let expected_request = match
    issue_request(
      service,
      evidence.run_definition,
      evidence.definitions,
      intent,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_identity(expected_request) !=
    @publication.publication_contract_identity(preparation.request) {
    return Err(CommitConflict)
  }
  match
    authorize(
      service,
      intent,
      evidence.run_definition,
      preparation.request,
      "request",
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    inspect_existing_effectful_commit(
      service,
      evidence,
      intent,
      preparation.request,
    ) {
    Ok(Some(value)) => return Ok(value)
    Ok(None) => ()
    Err(issue) => return Err(issue)
  }
  let expected_attempt = match
    issuance_result(
      @publication.issue_publication_attempt(
        preparation.request,
        evidence.run_definition,
        occurrence.attempt_id,
        occurrence.fence_cid,
        occurrence.external_idempotency_key,
        occurrence.started_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_identity(expected_attempt) !=
    @publication.publication_contract_identity(preparation.attempt) {
    return Err(CommitConflict)
  }
  commit_new_effectful_run_native(
    service,
    evidence,
    intent,
    preparation.request,
    preparation.attempt,
    occurrence.committed_at,
  )
}

///|
/// Publish one complete Effectful Run. The method reconciles an existing
/// scoped commit before issuing a new occurrence. A concurrent winner is
/// re-read and validated instead of being replaced or silently retried.
pub fn publish_effectful_run_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  match require_effectful_publication_materials(service, evidence) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let request = match
    issue_request(
      service,
      evidence.run_definition,
      evidence.definitions,
      intent,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    authorize(
      service,
      intent,
      evidence.run_definition,
      request,
      "request",
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match inspect_existing_effectful_commit(service, evidence, intent, request) {
    Ok(Some(value)) => return Ok(value)
    Ok(None) => ()
    Err(issue) => return Err(issue)
  }
  let attempt = match
    issuance_result(
      @publication.issue_publication_attempt(
        request,
        evidence.run_definition,
        occurrence.attempt_id,
        occurrence.fence_cid,
        occurrence.external_idempotency_key,
        occurrence.started_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  commit_new_effectful_run_native(
    service,
    evidence,
    intent,
    request,
    attempt,
    occurrence.committed_at,
  )
}
