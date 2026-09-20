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
/// Failures from binding one completed Result to durable native storage. A
/// cleanup variant preserves both the primary failure and the unresolved
/// physical cleanup observation.
pub(all) enum NativePublicationOutputIssue {
  InvalidOutputConfiguration
  Output(@publication_host.PublicationOutputExportIssue)
  Payload(@payload.PublicationPayloadIssue)
  Store(@store.NativePublicationStoreIssue)
  Binding(@publication.DurableResultBindingIssue)
  OutputCleanup(
    @publication_host.PublicationOutputExportIssue,
    @store.NativePublicationStoreIssue
  )
  StoreCleanup(
    @store.NativePublicationStoreIssue,
    @store.NativePublicationStoreIssue
  )
  BindingCleanup(
    @publication.DurableResultBindingIssue,
    @store.NativePublicationStoreIssue
  )
}

///|
/// Exact publication facts that exist before a completed Result is persisted.
/// The attempt must be the admitted occurrence issued by the standard
/// publication service; a raw attempt CID is deliberately not accepted.
pub(all) struct NativePublicationOutputContext {
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  retention : @publication.PublicationContract
  publication_attempt : @publication.PublicationContract
  computation_contract_cid : String
  input_relation_cids : Array[String]
  scope_cid : String
  effective_data_policy_cid : String
  authority_scope_cid : String
  store_authority_cid : String
  material_generation_cid : String
  max_payload_bytes : Int64
}

///|
/// One Result whose semantic evidence and durable representation were derived
/// from the same immutable completed-output traversal.
pub(all) struct NativePublishedOutput {
  definition : @publication.PublicationContract
  artifact : @publication.PublicationContract
  derivation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  retention : @publication.PublicationContract
  binding : @publication.PublicationContract
  binding_schema_wire : String
  snapshot : @publication.CapturedResultSnapshot
  payload : @store.NativePublicationPayloadInfo
}

///|
pub(all) enum NativeRunPublicationAssemblyIssue {
  InvalidAssembly
  Manifest(@publication.ResultManifestIssuanceIssue)
  Receipt(@publication.RunReceiptIssuanceIssue)
  Capture(@publication.CapturedRunIssuanceIssue)
}

///|
/// Admitted non-Result evidence retained by the standard Host for one exact
/// Effect-free Run. Result contracts and snapshots are accepted only from
/// successful `NativePublishedOutput` values.
pub(all) struct NativeEffectFreeRunContext {
  admission : @publication.RunPublicationAdmission
  run_definition : @publication.PublicationContract
  invocation : @publication.PublicationContract
  observation : @publication.RunEvidenceValue
  normalization_journal : @publication.RunEvidenceValue
  binding_names : Array[String]
  binding_digests : Array[String]
  source_evidence : Array[@publication.RunEvidenceValue]
  model_evidence : Array[@publication.RunEvidenceValue]
  barrier_attempt_receipt_cids : Array[String]
  source_advances : Array[@publication.PendingSourceStateAdvance]
  authoring : @publication.RunEvidenceValue
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
/// Admitted request and occurrence identity established before output bytes
/// are persisted. The contracts remain opaque and can only be consumed by the
/// matching standard publication service commit.
struct NativeRunPublicationPreparation {
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
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
fn cancel_writer_after_output_failure(
  writer : @store.PayloadWriter,
  issue : @publication_host.PublicationOutputExportIssue,
) -> NativePublicationOutputIssue {
  match writer.cancel() {
    Ok(_) => Output(issue)
    Err(cleanup) => OutputCleanup(issue, cleanup)
  }
}

///|
fn cancel_writer_after_store_failure(
  writer : @store.PayloadWriter,
  issue : @store.NativePublicationStoreIssue,
) -> NativePublicationOutputIssue {
  match writer.cancel() {
    Ok(_) => Store(issue)
    Err(cleanup) => StoreCleanup(issue, cleanup)
  }
}

///|
fn reclaim_after_binding_failure(
  store : @store.Store,
  material_generation_cid : String,
  issue : @publication.DurableResultBindingIssue,
) -> NativePublicationOutputIssue {
  match store.reclaim_payload(material_generation_cid) {
    Ok(_) => Binding(issue)
    Err(cleanup) => BindingCleanup(issue, cleanup)
  }
}

///|
fn reclaim_after_store_failure(
  store : @store.Store,
  material_generation_cid : String,
  issue : @store.NativePublicationStoreIssue,
) -> NativePublicationOutputIssue {
  match store.reclaim_payload(material_generation_cid) {
    Ok(_) => Store(issue)
    Err(cleanup) => StoreCleanup(issue, cleanup)
  }
}

///|
/// Persist one exact checked Result without routing its cells through an
/// environment-owned semantic implementation. The first bounded traversal
/// establishes identity. Only then does the Store receive a second bounded
/// traversal tied to the exact publication attempt and immutable generation.
pub fn persist_publication_output_native(
  store : @store.Store,
  output : @publication_host.PublicationOutputExport,
  context : NativePublicationOutputContext,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativePublishedOutput, NativePublicationOutputIssue] {
  if max_wire_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    context.max_payload_bytes < 1L ||
    @publication.publication_contract_name(context.run_definition) !=
    "run_definition" ||
    @publication.publication_contract_name(context.invocation) !=
    "run_invocation" ||
    @publication.publication_contract_name(context.retention) !=
    "result_retention_policy" ||
    @publication.publication_contract_name(context.publication_attempt) !=
    "publication_attempt" {
    output.cancel()
    return Err(InvalidOutputConfiguration)
  }
  let mut identified = false
  while !identified {
    match output.next() {
      Ok(Some(_)) => ()
      Ok(None) => identified = true
      Err(issue) => {
        output.cancel()
        return Err(Output(issue))
      }
    }
  }
  match output.finish() {
    Ok(_) => ()
    Err(issue) => {
      output.cancel()
      return Err(Output(issue))
    }
  }
  match
    output.issue_result_evidence(
      context.computation_contract_cid,
      context.input_relation_cids,
      context.scope_cid,
      context.effective_data_policy_cid,
      context.authority_scope_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => {
      output.cancel()
      return Err(Output(issue))
    }
  }
  let artifact = match
    output.issue_artifact(
      context.invocation,
      context.retention,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(Output(issue))
    }
  }
  let definition = output.definition().unwrap()
  let derivation = output.derivation().unwrap()
  let ordering = output.ordering().unwrap()
  let binding_schema_wire = output.result_schema_wire().unwrap()
  let fields = output.result_fields().unwrap()
  let row_count = output.row_count().unwrap()
  let content_bytes = output.content_bytes().unwrap().to_int64()
  if content_bytes < 1L || content_bytes > context.max_payload_bytes {
    output.cancel()
    return Err(InvalidOutputConfiguration)
  }
  let snapshot = match
    output.admit_captured_snapshot(max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(Output(issue))
    }
  }
  let payload_request = match
    @payload.prepare_publication_payload_request(
      context.store_authority_cid,
      @publication.publication_contract_identity(context.publication_attempt),
      context.material_generation_cid,
      @publication.publication_contract_identity(definition),
      output.logical_relation_cid().unwrap(),
      output.result_schema_cid().unwrap(),
      @publication.publication_contract_identity(ordering),
      output.codec_contract_cid().unwrap(),
      content_bytes,
      row_count.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(Payload(issue))
    }
  }
  let writer = match store.begin_payload(payload_request) {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(Store(issue))
    }
  }
  let replay = match output.replay() {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(cancel_writer_after_output_failure(writer, issue))
    }
  }
  let mut replayed = false
  while !replayed {
    match replay.next() {
      Ok(Some(chunk)) =>
        match writer.append(@utf8.encode(chunk)) {
          Ok(_) => ()
          Err(issue) => {
            replay.cancel()
            output.cancel()
            return Err(cancel_writer_after_store_failure(writer, issue))
          }
        }
      Ok(None) => replayed = true
      Err(issue) => {
        replay.cancel()
        output.cancel()
        return Err(cancel_writer_after_output_failure(writer, issue))
      }
    }
  }
  let tail = match replay.finish() {
    Ok(value) => value
    Err(issue) => {
      replay.cancel()
      output.cancel()
      return Err(cancel_writer_after_output_failure(writer, issue))
    }
  }
  match writer.append(@utf8.encode(tail)) {
    Ok(_) => ()
    Err(issue) => {
      output.cancel()
      return Err(cancel_writer_after_store_failure(writer, issue))
    }
  }
  let payload = match writer.seal() {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(cancel_writer_after_store_failure(writer, issue))
    }
  }
  if payload.generation.size != content_bytes {
    output.cancel()
    return Err(
      reclaim_after_store_failure(
        store,
        context.material_generation_cid,
        @store.DigestMismatch,
      ),
    )
  }
  let binding = match
    @publication.issue_durable_result_binding(
      context.run_definition,
      definition,
      context.invocation,
      artifact,
      ordering,
      context.retention,
      output.codec_contract_cid().unwrap(),
      fields,
      binding_schema_wire,
      payload.material_generation_cid,
      context.store_authority_cid,
      row_count,
      payload.generation.size.to_int(),
      payload.physical_digest[7:].to_owned(),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => {
      output.cancel()
      return Err(
        reclaim_after_binding_failure(
          store,
          context.material_generation_cid,
          issue,
        ),
      )
    }
  }
  output.cancel()
  Ok({
    definition,
    artifact,
    derivation,
    ordering,
    retention: context.retention,
    binding,
    binding_schema_wire,
    snapshot,
    payload,
  })
}

///|
/// Assemble the complete Run-bound chain from admitted Run evidence and the
/// exact Results already persisted by the standard native output path.
pub fn assemble_native_effect_free_publication(
  context : NativeEffectFreeRunContext,
  outputs : Array[NativePublishedOutput],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  NativeEffectFreePublicationEvidence,
  NativeRunPublicationAssemblyIssue,
] {
  if outputs.is_empty() || max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidAssembly)
  }
  let definitions = outputs.map(output => output.definition)
  let artifacts = outputs.map(output => output.artifact)
  let derivations = outputs.map(output => output.derivation)
  let orderings = outputs.map(output => output.ordering)
  let retentions = outputs.map(output => output.retention)
  let bindings = outputs.map(output => output.binding)
  let binding_schema_wires = outputs.map(output => output.binding_schema_wire)
  let snapshots = outputs.map(output => output.snapshot)
  let manifest = match
    @publication.issue_result_manifest(
      context.run_definition,
      context.invocation,
      definitions,
      artifacts,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Manifest(issue))
  }
  let receipt = match
    @publication.issue_effect_free_run_receipt(
      context.admission,
      context.run_definition,
      context.invocation,
      context.observation,
      definitions,
      artifacts,
      manifest,
      context.normalization_journal,
      context.binding_names,
      context.binding_digests,
      context.source_evidence,
      context.model_evidence,
      context.barrier_attempt_receipt_cids,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  let captured_run = match
    @publication.issue_effect_free_captured_run(
      context.run_definition,
      context.invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      snapshots,
      context.source_advances,
      context.authoring,
      context.model_evidence,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  Ok({
    run_definition: context.run_definition,
    invocation: context.invocation,
    definitions,
    artifacts,
    derivations,
    orderings,
    retentions,
    bindings,
    binding_schema_wires,
    manifest,
    receipt,
    captured_run,
  })
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
  run_definition : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  intent : NativeRunPublicationIntent,
) -> Result[@publication.PublicationContract, NativeRunPublicationIssue] {
  issuance_result(
    @publication.issue_publication_request(
      run_definition,
      definitions,
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
pub fn NativeRunPublicationPreparation::publication_attempt(
  self : NativeRunPublicationPreparation,
) -> @publication.PublicationContract {
  self.attempt
}

///|
/// Admit the exact publication occurrence before output persistence. This
/// establishes the real attempt identity used by every payload request; it
/// does not claim that payloads, evidence, or a public index already exist.
pub fn prepare_effect_free_run_publication_native(
  service : NativeRunPublicationService,
  run_definition : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
) -> Result[NativeRunPublicationPreparation, NativeRunPublicationIssue] {
  let request = match
    issue_request(service, run_definition, definitions, intent) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match authorize(service, intent, run_definition, request, "request", None) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let attempt = match
    issuance_result(
      @publication.issue_publication_attempt(
        request,
        run_definition,
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
fn commit_new_effect_free_run_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  intent : NativeRunPublicationIntent,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  committed_at : String,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
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

///|
/// Commit a prepared occurrence after every Result payload and Run-bound
/// evidence contract exists. The preparation is re-derived and compared, so
/// a foreign request or attempt cannot be substituted between the two phases.
pub fn commit_prepared_effect_free_run_publication_native(
  service : NativeRunPublicationService,
  evidence : NativeEffectFreePublicationEvidence,
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  preparation : NativeRunPublicationPreparation,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  if evidence.bindings.length() != evidence.binding_schema_wires.length() {
    return Err(InvalidConfiguration)
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
    inspect_existing_commit(service, evidence, intent, preparation.request) {
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
  commit_new_effect_free_run_native(
    service,
    evidence,
    intent,
    preparation.request,
    preparation.attempt,
    occurrence.committed_at,
  )
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
  commit_new_effect_free_run_native(
    service,
    evidence,
    intent,
    request,
    attempt,
    occurrence.committed_at,
  )
}
