///|
/// Failures reported by the standard native publication entry point. The
/// portable publication package owns every contract and chain decision; the
/// native Store owns only durable physical operations.
pub(all) enum NativeRunPublicationIssue {
  InvalidConfiguration
  AccessDenied
  CommitConflict
  Store(@store.NativePublicationStoreIssue)
  Issuance(@publication.PublicationCommitIssuanceIssue)
  Commit(@publication.PublicationCommitIssue)
  Projection(@publication.DeliveryIssuanceIssue)
}

///|
/// Complete Effect-free Run evidence produced by the checked execution path.
/// Publication request, attempt, and public-index contracts are deliberately
/// absent: the standard entry point issues them from the admitted intent.
pub(all) struct NativeEffectFreePublicationEvidence {
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
/// Immutable publication intent. A retry must reuse these values so it
/// resolves to the same canonical publication request.
pub(all) struct NativeRunPublicationIntent {
  tenant_id : String
  authority_scope_cid : String
  publication_policy_cid : String
  publication_target_cid : String
  requested_at : String
}

///|
/// One physical publication occurrence. If an equivalent intent is already
/// committed, the committed occurrence wins and no new attempt is installed.
pub(all) struct NativeRunPublicationOccurrence {
  attempt_id : String
  fence_cid : String
  external_idempotency_key : String?
  started_at : String
  committed_at : String
}

///|
/// Durable result of the standard publication entry point.
pub(all) struct NativeRunPublicationResult {
  public_index_entry_cid : String
  publication_request_cid : String
  publication_attempt_cid : String
  committed : Bool
  idempotent : Bool
}

///|
/// Exact facts presented to the Host publication authority. The first check
/// precedes Store lookup, so denial cannot reveal whether a scoped Run is
/// already published. The commit check binds the candidate index.
pub(all) struct NativeRunPublicationAuthorization {
  stage : String
  tenant_id : String
  authority_scope_cid : String
  run_definition_cid : String
  publication_request_cid : String
  public_index_entry_cid : String?
}

///|
struct NativeRunPublicationAuthority {
  authorize : (NativeRunPublicationAuthorization) -> Bool
}

///|
/// Standard native publication service. It contains only common limits and
/// the physical Store authority; callers cannot replace the portable contract
/// implementation with environment-specific callbacks.
struct NativeRunPublicationService {
  store : @store.Store
  authority : NativeRunPublicationAuthority
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub fn install_native_run_publication_authority(
  authorize : (NativeRunPublicationAuthorization) -> Bool,
) -> NativeRunPublicationAuthority {
  { authorize, }
}

///|
pub fn install_native_run_publication_service(
  store : @store.Store,
  authority : NativeRunPublicationAuthority,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativeRunPublicationService, NativeRunPublicationIssue] {
  if max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    Err(InvalidConfiguration)
  } else {
    Ok({ store, authority, max_wire_bytes, max_nodes, max_depth, })
  }
}

///|
fn authorize(
  service : NativeRunPublicationService,
  intent : NativeRunPublicationIntent,
  run_definition : @publication.PublicationContract,
  request : @publication.PublicationContract,
  stage : String,
  index : @publication.PublicationContract?,
) -> Result[Unit, NativeRunPublicationIssue] {
  let index_cid = match index {
    Some(value) => Some(@publication.publication_contract_identity(value))
    None => None
  }
  if (service.authority.authorize)({
      stage,
      tenant_id: intent.tenant_id,
      authority_scope_cid: intent.authority_scope_cid,
      run_definition_cid: @publication.publication_contract_identity(
        run_definition,
      ),
      publication_request_cid: @publication.publication_contract_identity(
        request,
      ),
      public_index_entry_cid: index_cid,
    }) {
    Ok(())
  } else {
    Err(AccessDenied)
  }
}

///|
fn[T] store_result(
  result : Result[T, @store.NativePublicationStoreIssue],
) -> Result[T, NativeRunPublicationIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Store(issue))
  }
}

///|
fn[T] issuance_result(
  result : Result[T, @publication.PublicationCommitIssuanceIssue],
) -> Result[T, NativeRunPublicationIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Issuance(issue))
  }
}

///|
fn[T] projection_result(
  result : Result[T, @publication.DeliveryIssuanceIssue],
) -> Result[T, NativeRunPublicationIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Projection(issue))
  }
}

///|
fn commit_result(
  result : Result[Unit, @publication.PublicationCommitIssue],
) -> Result[Unit, NativeRunPublicationIssue] {
  match result {
    Ok(_) => Ok(())
    Err(issue) => Err(Commit(issue))
  }
}

///|
fn issue_request(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  intent : NativeRunPublicationIntent,
) -> Result[@publication.PublicationContract, NativeRunPublicationIssue] {
  issuance_result(
    @publication.issue_publication_request(
      evidence.run_definition,
      evidence.definitions,
      intent.tenant_id,
      intent.authority_scope_cid,
      intent.publication_policy_cid,
      intent.publication_target_cid,
      intent.requested_at,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
    ),
  )
}

///|
fn validate_existing_commit(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  request : @publication.PublicationContract,
  index : @publication.PublicationContract,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
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
  match
    commit_result(
      @publication.validate_effect_free_publication_commit_with_result_evidence(
        evidence.run_definition,
        evidence.invocation,
        evidence.definitions,
        evidence.artifacts,
        evidence.derivations,
        evidence.orderings,
        evidence.retentions,
        evidence.bindings,
        evidence.manifest,
        evidence.receipt,
        evidence.captured_run,
        stored_request,
        stored_attempt,
        index,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
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
fn inspect_existing_commit(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  intent : NativeRunPublicationIntent,
  request : @publication.PublicationContract,
) -> Result[NativeRunPublicationResult?, NativeRunPublicationIssue] {
  let existing = match
    store_result(
      service.store.inspect_committed_publication(
        intent.tenant_id,
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
      match validate_existing_commit(service, evidence, request, index) {
        Ok(value) => Ok(Some(value))
        Err(issue) => Err(issue)
      }
    }
  }
}

///|
/// Publish one complete Effect-free Run. The method reconciles an existing
/// scoped commit before issuing a new occurrence. A concurrent winner is
/// re-read and validated instead of being replaced or silently retried.
pub fn publish_effect_free_run_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  if evidence.bindings.length() != evidence.binding_schema_wires.length() {
    return Err(InvalidConfiguration)
  }
  let request = match issue_request(service, evidence, intent) {
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
  match inspect_existing_commit(service, evidence, intent, request) {
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
        occurrence.committed_at,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
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
      match inspect_existing_commit(service, evidence, intent, request) {
        Ok(Some(value)) => Ok(value)
        Ok(None) => Err(CommitConflict)
        Err(issue) => Err(issue)
      }
    Err(issue) => Err(Store(issue))
  }
}
