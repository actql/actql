///|
/// Installed Provider policy and bounded evidence configuration. These are
/// typed existing-owner values, not a plan parsed by this connection. Current
/// credential authorization is supplied independently for each physical read.
pub(all) struct NativeResidentEffectReviewPolicy {
  stage : Int
  effect_id : String
  result_index : Int
  mapping : @catalog.ExecutionMapping
  projection : @catalog.WriteProjection
  catalog : @catalog.CatalogObservation
  api_version : String
  runtime_bundle_cid : String
  source_binding_cid : String
  store_authority_cid : String
  retention : @publication.PublicationContract
  retention_dependencies : Array[@publication.CapturedEffectDependencyBody]
  dependency_limits : @publication.CapturedEffectDependencyLimits
  preview_limits : @host.ClientCapturedEffectPreviewLimits
  export_limits : @host.PublicationOutputExportLimits
  dispatch_limits : NativeEffectDispatchKeyLimits
  body_limits : @catalog.WriteBodyLimits
  request_limits : @catalog.WriteRequestLimits
  observation_limits : @catalog.TargetObservationLimits
  max_rows : Int
  max_fields : Int
  // Whole evidence validation has its own caller-owned budget, independent
  // of the result-row export workspace.
  max_capture_workspace_entries : Int
  max_work : Int
  max_utf16_units : Int
}

///|
pub(all) enum NativeResidentEffectReviewIssue {
  Unavailable
  InvalidLimits
  Native(@resident.ResidentSourceComputeIssue)
  Export(@execution.CompletedExportIssue)
  Definition(@host.ClientEffectLocalResultDefinitionIssue)
  Artifact(@host.ClientEffectLocalResultArtifactIssue)
  Targets(NativeResidentEffectTargetIssue)
  Preview(NativeResidentEffectPreviewIssue)
  Contract(@publication.PublicationContractIssue)
  Source(@publication.CapturedRunIssuanceIssue)
  Dependency(@resident.ResidentEffectDependencyCaptureIssue)
  Manifest(@host.ClientEffectLocalManifestIssue)
  Inventory(@host.ClientEffectCaptureInventoryIssue)
  Capture(@resident.ResidentEffectRunCaptureIssue)
  Retention(@resident.ResidentEffectReviewRetentionIssue)
  Journal(@journal.NativeRemoteJournalIssue)
}

///|
pub(all) struct NativeResidentEffectReviewCapture {
  artifact : @host.ClientEffectLocalResultArtifact
  manifest : @host.ClientEffectLocalManifest
  preview : NativeResidentEffectPreview
  source : @publication.CapturedEffectSourceArtifact
  local_source : @publication.CapturedLocalEffectSourceEvidence
  inventory : @publication.CapturedEffectDependencyInventory
  dependencies : Array[@host.ClientEffectDependencyCapture]
  captured : @publication.PublicationContract
}

///|
/// Preparation for one original retained consumer, with its own child export.
/// Original producer, receiver, borrow and public Result custody stay with the
/// caller. This holds no scheduler, Run ledger, approval or execution permit.
struct NativeResidentEffectReview {
  holder : @resident.ResidentRetainedConsumer
  mut journal : @journal.Journal
  consumer : @resident.ResidentSourceCompute
  materials : @host.ClientEffectRunMaterials
  inputs : @strategy.CapturedEffectInputs
  producer : @resident.ResidentEffectProducerCapture
  receiver : @host.ClientEffectLocalResultArtifact
  imported : @host.ClientEffectImportedEvidence
  root_index : Int
  result : @resident.ResidentEffectResultCapture
  // Only the context-taking entry point owns these extra pins and the public
  // Result export. The older entry point continues to borrow caller custody.
  mut owned_inputs : @resident.ResidentEffectReviewInputContext?
  mut owned_result : Bool
  invocation : @publication.PublicationContract
  request : @host.ClientRequestIdentity
  policy : NativeResidentEffectReviewPolicy
  exported : @strategy.CapturedEffectLocalResultExport
  receipt : @execution.CompletedRelationExportReceipt
  artifact : @host.ClientEffectLocalResultArtifact
  uses : Array[NativeSalesforceTargetAccess]
  mut targets : Array[
    (
      @catalog.SingleWriteRequest,
      String,
      @catalog.TargetObservation,
      @catalog.TargetPreviewRow,
    ),
  ]?
  mut created_targets : NativeResidentEffectCreatedTargets?
  mut target_failure : NativeResidentEffectTargetIssue?
  mut observing : Bool
  mut completing : Bool
  mut captured : NativeResidentEffectReviewCapture?
  mut retention : @resident.ResidentEffectReviewRetention?
  mut retention_configuration : (
    @signature.Library,
    Bytes,
    String,
    String,
    String,
    @checkpoint.WireLimits,
  )?
  mut approved_row : NativeResidentEffectApprovedRow?
  mut row_custody_confirmed : Bool
  mut effect_pending : Bool
  mut retiring : Bool
  mut closed : Bool
}

///|
fn NativeResidentEffectReview::current(
  self : NativeResidentEffectReview,
) -> Bool {
  !self.retiring &&
  self.holder.effect_computation(self.journal) is Some(owner) &&
  physical_equal(owner, self.consumer) &&
  self.consumer.request_for_effect_review(self.inputs) == Some(self.request) &&
  self.holder.effect_source_binding_cid(self.journal, self.inputs) ==
  Some(self.policy.source_binding_cid)
}

///|
/// Validate the retained edge and original request before any Provider access.
/// The bounded child export reads completed consumer rows only; it cannot
/// acquire a Source, execute Compute or transfer physical input ownership.
pub fn prepare_native_resident_effect_review(
  holder : @resident.ResidentRetainedConsumer,
  journal : @journal.Journal,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  producer : @resident.ResidentEffectProducerCapture,
  receiver : @host.ClientEffectLocalResultArtifact,
  imported : @host.ClientEffectImportedEvidence,
  root_index : Int,
  result : @resident.ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  policy : NativeResidentEffectReviewPolicy,
) -> Result[NativeResidentEffectReview, NativeResidentEffectReviewIssue] {
  let consumer = match holder.effect_computation(journal) {
    Some(value) => value
    None => return Err(Unavailable)
  }
  if holder.effect_source_binding_cid(journal, inputs) !=
    Some(policy.source_binding_cid) {
    return Err(Unavailable)
  }
  let dispatch = @resident.resident_retained_consumer_request(holder)
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  if execution[2] != policy.runtime_bundle_cid ||
    !native_review_catalog_matches_original(
      policy.catalog,
      execution[0],
      execution[1],
      @publication.publication_contract_identity(invocation),
      @remote.dispatch_request_identity(dispatch),
    ) {
    return Err(Unavailable)
  }
  let request = match consumer.request_for_effect_review(inputs) {
    Some(value) if materials.request == Some(value) => value
    _ => return Err(Unavailable)
  }
  if policy.max_work < 1 ||
    policy.max_work > 1000000 ||
    policy.max_rows < 1 ||
    policy.max_capture_workspace_entries < 1 {
    return Err(InvalidLimits)
  }
  if !@host.client_effect_dependency_capture_matches(
      materials, inputs, receiver, root_index,
    ) ||
    @publication.publication_contract_identity(producer.invocation) !=
    @publication.publication_contract_identity(invocation) ||
    @publication.run_evidence_value_identity(producer.observation) !=
    @publication.run_evidence_value_identity(observation) {
    return Err(Unavailable)
  }
  let descriptor = match
    @host.client_effect_member_descriptor(
      materials.prepared,
      policy.stage,
      policy.effect_id,
      policy.max_work,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  // This first connection is one checked Effect member. Its result and
  // mapping are selected by the existing checked computation Owner.
  if descriptor.0 != 0 ||
    (descriptor.2 != "update" && descriptor.2 != "create") ||
    descriptor.4 != policy.mapping.mapping_ref ||
    descriptor.5 != policy.mapping.mapping_cid ||
    !@strategy.captured_effect_local_result_matches_member(
      inputs,
      policy.result_index,
      descriptor.0,
    ) {
    return Err(Unavailable)
  }
  let exported = match
    consumer.prepare_effect_result_export(
      inputs,
      policy.result_index,
      policy.export_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Native(issue))
  }
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let child : Ref[@execution.CompletedOutputExport?] = Ref(None)
  let reject = (issue : NativeResidentEffectReviewIssue) => {
    if child.val is Some(output) {
      @execution.cancel_completed_output_export(output)
    }
    @execution.cancel_completed_result_relation_export(preparation) |> ignore
    Err(issue)
  }
  let mut ready = false
  for _ in 0..<policy.max_work {
    if consumer.request_for_effect_review(inputs) != Some(request) {
      return reject(Unavailable)
    }
    match @execution.advance_completed_result_relation_export(preparation, 16) {
      Ok((true, _)) => {
        ready = true
        break
      }
      Ok(_) => ()
      Err(issue) => return reject(Export(issue))
    }
  }
  if !ready {
    return reject(InvalidLimits)
  }
  let output = match
    @execution.finish_completed_result_relation_export_preparation(preparation) {
    Ok(value) => value
    Err(issue) => return reject(Export(issue))
  }
  child.val = Some(output)
  let mut ended = false
  for _ in 0..<policy.max_work {
    if consumer.request_for_effect_review(inputs) != Some(request) {
      return reject(Unavailable)
    }
    match @execution.next_completed_output_export(output) {
      Ok(Some(_)) => ()
      Ok(None) => {
        ended = true
        break
      }
      Err(issue) => return reject(Export(issue))
    }
  }
  if !ended {
    return reject(InvalidLimits)
  }
  let receipt = match @execution.finish_completed_relation_export(output) {
    Ok((value, _)) => value
    Err(issue) => return reject(Export(issue))
  }
  let reject = (issue : NativeResidentEffectReviewIssue) => {
    @execution.cancel_completed_relation_export_receipt(receipt)
    reject(issue)
  }
  let local_result = @strategy.captured_effect_local_result_at(
    inputs,
    policy.result_index,
  ).unwrap()
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(local_result),
    ),
  )
  let bounds = policy.preview_limits
  let definition = match
    @host.issue_client_effect_local_result_definition(
      materials.prepared,
      policy.stage,
      name,
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Definition(issue))
  }
  let artifact = match
    @host.issue_imported_client_effect_local_result_artifact(
      materials.prepared,
      inputs,
      exported,
      imported,
      definition,
      receipt,
      policy.retention,
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      invocation,
      observation,
      bounds.max_wire_bytes,
      bounds.max_nodes,
      bounds.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Artifact(issue))
  }
  Ok({
    holder,
    journal,
    consumer,
    materials,
    inputs,
    producer,
    receiver,
    imported,
    root_index,
    result,
    owned_inputs: None,
    owned_result: false,
    invocation,
    request,
    policy: {
      ..policy,
      retention_dependencies: policy.retention_dependencies.copy(),
    },
    exported,
    receipt,
    artifact,
    uses: [],
    targets: None,
    created_targets: None,
    target_failure: None,
    observing: false,
    completing: false,
    captured: None,
    retention: None,
    retention_configuration: None,
    approved_row: None,
    row_custody_confirmed: false,
    effect_pending: false,
    retiring: false,
    closed: false,
  })
}

///|
/// Prepare target facts once. Updates observe through the existing Credential
/// Resource Service; mapped create projects the actual retained Result without
/// a target read. Completed observations are immutable Preview facts. A failed/uncertain use is never
/// retried here; its exact credential owners remain available for inspection.
pub fn NativeResidentEffectReview::observe(
  self : NativeResidentEffectReview,
  access : (Int, @catalog.SingleWriteRequest) -> Result[
    NativeSalesforceTargetAccess,
    NativeSalesforcePreviewIssue,
  ],
) -> Result[
  Array[
    (
      @catalog.SingleWriteRequest,
      String,
      @catalog.TargetObservation,
      @catalog.TargetPreviewRow,
    ),
  ],
  NativeResidentEffectTargetIssue,
] {
  if self.observing || !self.current() {
    return Err(Proposal(Unavailable))
  }
  if self.target_failure is Some(issue) {
    return Err(issue)
  }
  if self.targets is Some(rows) {
    return Ok(rows.copy())
  }
  let policy = self.policy
  if policy.mapping.operation is @catalog.WriteCreate {
    self.observing = true
    let outcome = match
      prepare_native_resident_effect_created_targets(
        self.consumer,
        self.materials,
        self.inputs,
        policy.stage,
        policy.effect_id,
        policy.result_index,
        policy.mapping,
        policy.projection,
        policy.api_version,
        policy.export_limits,
        policy.body_limits,
        policy.request_limits,
        policy.max_rows,
        policy.max_fields,
        policy.max_work,
        policy.max_utf16_units,
        policy.preview_limits.max_wire_bytes,
      ) {
      Ok(created) =>
        if self.current() {
          self.created_targets = Some(created)
          self.targets = Some([])
          Ok([])
        } else {
          Err(Proposal(Unavailable))
        }
      Err(issue) => {
        self.target_failure = Some(issue)
        Err(issue)
      }
    }
    self.observing = false
    return outcome
  }
  let dispatch = @resident.resident_retained_consumer_request(self.holder)
  let execution = @remote.dispatch_request_execution_scope(dispatch)
  let route = @remote.dispatch_request_journal_key(dispatch)
  let acquire = (index, request) => {
    match access(index, request) {
      Ok(value) => {
        if !self.current() ||
          value.scope.site_key != execution[0] ||
          value.scope.site_generation.to_string() != execution[1] ||
          value.scope.runtime_bundle_cid != execution[2] ||
          value.scope.dispatch_request_cid !=
          @remote.dispatch_request_identity(dispatch) ||
          value.scope.task_attempt.to_string() != route[6] ||
          value.scope.run_invocation_cid !=
          @publication.publication_contract_identity(self.invocation) {
          return Err(NativeSalesforcePreviewIssue::ForeignScope)
        }
        self.uses.push(value)
        Ok(value)
      }
      Err(issue) => Err(issue)
    }
  }
  self.observing = true
  let outcome = match
    observe_native_resident_effect_targets(
      self.consumer,
      self.materials,
      self.inputs,
      policy.stage,
      policy.effect_id,
      policy.result_index,
      policy.mapping,
      policy.projection,
      policy.catalog,
      policy.api_version,
      policy.export_limits,
      policy.body_limits,
      policy.request_limits,
      policy.observation_limits,
      policy.max_rows,
      policy.max_fields,
      policy.max_work,
      policy.max_utf16_units,
      acquire,
    ) {
    Ok(rows) => {
      self.targets = Some(rows.copy())
      if self.current() {
        Ok(rows)
      } else {
        Err(Proposal(Unavailable))
      }
    }
    Err(issue) => {
      self.target_failure = Some(issue)
      Err(issue)
    }
  }
  self.observing = false
  outcome
}

///|
/// Exact original resource-use owners, including a use whose result is unknown.
/// Querying them is separate from repeating the physical Provider read.
pub fn NativeResidentEffectReview::target_uses(
  self : NativeResidentEffectReview,
) -> Array[NativeSalesforceTargetAccess] {
  self.uses.copy()
}

///|
/// Complete the checked Preview and closed Captured Run from retained physical
/// facts. This performs no Provider I/O, Source acquisition, Compute or write.
pub fn NativeResidentEffectReview::complete(
  self : NativeResidentEffectReview,
  phase_observe? : (String) -> Unit = _ => (),
  capture_progress? : (@resident.ResidentEffectRunCapturePhase, Int64, Int64) -> Unit = (
    _,
    _,
    _,
  ) => (),
) -> Result[NativeResidentEffectReviewCapture, NativeResidentEffectReviewIssue] {
  if self.completing {
    return Err(Unavailable)
  }
  self.completing = true
  let result = (fn() -> Result[
    NativeResidentEffectReviewCapture,
    NativeResidentEffectReviewIssue,
  ] {
    let phase = (name : String) => {
      phase_observe(name)
      self.current()
    }
    if !self.current() {
      return Err(Unavailable)
    }
    if self.captured is Some(value) {
      return Ok(value)
    }
    let targets = match self.targets {
      Some(rows) => rows
      None => return Err(Unavailable)
    }
    let policy = self.policy
    let bounds = policy.preview_limits
    if !phase("preview") {
      return Err(Unavailable)
    }
    let preview = match
      prepare_native_resident_effect_preview(
        self.consumer,
        self.materials,
        self.inputs,
        self.request,
        policy.stage,
        policy.effect_id,
        policy.result_index,
        self.artifact,
        self.invocation,
        policy.retention,
        policy.source_binding_cid,
        policy.store_authority_cid,
        policy.mapping,
        policy.runtime_bundle_cid,
        policy.catalog,
        targets,
        bounds,
        policy.export_limits,
        policy.dispatch_limits,
        created_targets=self.created_targets,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Preview(issue))
    }
    if !phase("artifact") {
      return Err(Unavailable)
    }
    let contract = match
      @publication.admit_publication_contract(
        "result_artifact",
        @host.client_effect_local_result_artifact_json(self.artifact),
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Contract(issue))
    }
    if !phase("source") {
      return Err(Unavailable)
    }
    let source = match
      @publication.admit_captured_effect_source_from_result(
        @strategy.captured_effect_preview_ledger_identity(preview.preview),
        0,
        self.invocation,
        preview.source,
        contract,
        policy.store_authority_cid,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Source(issue))
    }
    if !phase("dependencies") {
      return Err(Unavailable)
    }
    let dependencies = []
    for
      (artifact, index) in [
        (self.receiver, self.root_index),
        (self.artifact, policy.result_index),
      ] {
      match
        self.consumer.capture_effect_dependency(
          self.materials,
          self.inputs,
          artifact,
          index,
          policy.export_limits,
          bounds.max_wire_bytes,
          bounds.max_nodes,
          bounds.max_depth,
        ) {
        Ok(value) => dependencies.push(value)
        Err(issue) => return Err(Dependency(issue))
      }
    }
    if !phase("manifest") {
      return Err(Unavailable)
    }
    let manifest = match
      @host.issue_client_effect_local_manifest(
        self.materials.prepared,
        @host.client_effect_imported_invocation(self.imported),
        [self.artifact],
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Manifest(issue))
    }
    if !phase("inventory") {
      return Err(Unavailable)
    }
    let (local_source, inventory) = match
      @host.issue_client_effect_capture_inventory(
        self.materials,
        self.inputs,
        0,
        source,
        manifest,
        self.artifact,
        self.imported,
        self.producer.acquired,
        self.producer.acquired_bodies.0,
        self.producer.acquired_bodies.1,
        dependencies,
        policy.retention_dependencies,
        policy.dependency_limits,
        bounds.max_nodes,
        bounds.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Inventory(issue))
    }
    if !phase("captured-run") {
      return Err(Unavailable)
    }
    let captured = match
      self.consumer.capture_effect_run(
        self.materials,
        self.inputs,
        self.result,
        self.invocation,
        preview.preview,
        match preview.proof {
          Some(proof) => [proof]
          None => []
        },
        [source],
        [local_source],
        inventory,
        preview.authoring,
        policy.max_fields,
        policy.max_work,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
        policy.max_capture_workspace_entries,
        progress=capture_progress,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Capture(issue))
    }
    let complete : NativeResidentEffectReviewCapture = {
      artifact: self.artifact,
      manifest,
      preview,
      source,
      local_source,
      inventory,
      dependencies,
      captured,
    }
    self.captured = Some(complete)
    Ok(complete)
  })()
  self.completing = false
  result
}

///|
/// Keep the persistence connection before the first physical write. A retry
/// cannot replace crypto custody, the original Checkpoint or its review window.
pub fn NativeResidentEffectReview::prepare_retention(
  self : NativeResidentEffectReview,
  crypto : @signature.Library,
  key : Bytes,
  checkpoint_id : String,
  created_at : String,
  expires_at : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  @resident.ResidentEffectReviewRetention,
  NativeResidentEffectReviewIssue,
] {
  if !self.current() {
    return Err(Unavailable)
  }
  if self.retention is Some(retention) {
    let saved = self.retention_configuration.unwrap()
    if !physical_equal(saved.0, crypto) ||
      saved.1 != key ||
      saved.2 != checkpoint_id ||
      saved.3 != created_at ||
      saved.4 != expires_at ||
      saved.5.max_wire_bytes != limits.max_wire_bytes ||
      saved.5.max_nodes != limits.max_nodes ||
      saved.5.max_depth != limits.max_depth {
      return Err(Unavailable)
    }
    return Ok(retention)
  }
  let complete = match self.complete() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let retention = match
    self.consumer.prepare_effect_review_retention(
      self.materials,
      self.inputs,
      self.result,
      self.invocation,
      complete.preview.preview,
      complete.captured,
      complete.preview.wire,
      @publication.run_evidence_value_identity(complete.preview.authoring),
      self.policy.store_authority_cid,
      crypto,
      key,
      checkpoint_id,
      created_at,
      expires_at,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  self.retention = Some(retention)
  self.retention_configuration = Some(
    (crypto, key[:].to_owned(), checkpoint_id, created_at, expires_at, limits),
  )
  Ok(retention)
}

///|
/// Save the exact report into the existing Site journal only after confirming
/// all three evidence owners. A failed/uncertain journal commit returns no
/// report for sending; retry retains the same Checkpoint and reservations.
pub fn NativeResidentEffectReview::persist_and_retain_report(
  self : NativeResidentEffectReview,
  store : @store.Store,
  crypto : @signature.Library,
  key : Bytes,
  checkpoint_id : String,
  created_at : String,
  expires_at : String,
  limits : @checkpoint.WireLimits,
  computation_capacity? : @resident.ResidentEffectComputationCapacity? = None,
) -> Result[
  @remote.RemoteEffectCheckpointReport,
  NativeResidentEffectReviewIssue,
] {
  let retention = match
    self.prepare_retention(
      crypto, key, checkpoint_id, created_at, expires_at, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let report = match retention.persist(store, computation_capacity~) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  if !self.current() {
    return Err(Unavailable)
  }
  match self.journal.retain_effect_checkpoint_report(report) {
    Ok(_) => Ok(report)
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Read the original confirmed review projection for authorized transport.
/// The returned report names the original dispatch and Checkpoint; no JSON,
/// Preview, approval or Run is regenerated. Input and review custody stay owned.
pub fn NativeResidentEffectReview::review_projection(
  self : NativeResidentEffectReview,
  authorize_evidence_read : () -> Bool,
  max_bytes : Int,
) -> Result[
  (@remote.RemoteEffectCheckpointReport, String),
  NativeResidentEffectReviewIssue,
] {
  if self.closed || self.retiring || !self.current() {
    return Err(Unavailable)
  }
  guard self.retention is Some(retention) else { return Err(Unavailable) }
  let projection = match
    retention.review_projection(authorize_evidence_read, max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  if self.closed || self.retiring || !self.current() {
    return Err(Unavailable)
  }
  Ok(projection)
}

///|
/// Reopen the journal only for this original live holder and its authenticated
/// completion/borrow. This restores no process, Ledger, approval or generation.
pub fn NativeResidentEffectReview::restore_journal(
  self : NativeResidentEffectReview,
  journal : @journal.Journal,
) -> Result[Unit, NativeResidentEffectReviewIssue] {
  if self.retiring {
    return Err(Unavailable)
  }
  guard self.holder.effect_computation(journal) is Some(owner) &&
    physical_equal(owner, self.consumer) else {
    return Err(Unavailable)
  }
  self.journal = journal
  self.row_custody_confirmed = false
  Ok(())
}

///|
/// Retire this connection only after its caller discharges review obligations.
/// Pending evidence retirement keeps the child export and all original inputs;
/// successful retirement cancels only this connection's child export/receipt.
pub fn NativeResidentEffectReview::retry_cleanup(
  self : NativeResidentEffectReview,
) -> Result[Bool, NativeResidentEffectReviewIssue] {
  if self.closed {
    return Ok(false)
  }
  // Read durable responsibility before starting retirement. This synchronous
  // journal read invokes no caller callback; uncertain custody remains pending
  // without prematurely retiring the original holder.
  if !self.row_custody_confirmed &&
    self.retention_configuration is Some((_, _, _, _, _, limits)) &&
    self.captured is Some(capture) &&
    self.targets is Some(targets) &&
    (
      targets.length() == 1 ||
      (self.created_targets is Some(created) && created.requests.length() == 1)
    ) &&
    capture.preview.keys.length() == 1 {
    // Checkpoint budgets may exceed the common Ledger contract's ceilings.
    // Narrow this read's budget; never relax the Ledger Owner's admission.
    let ledger_limits : @checkpoint.WireLimits = {
      max_wire_bytes: Int::min(limits.max_wire_bytes, 1000000),
      max_nodes: Int::min(limits.max_nodes, 1000),
      max_depth: Int::min(limits.max_depth, 32),
    }
    match self.restore_row_custody(ledger_limits) {
      Ok(_) => ()
      Err(Journal(issue)) => return Err(Journal(issue))
      Err(_) => return Err(Unavailable)
    }
  }
  if self.effect_pending {
    return Err(Unavailable)
  }
  self.retiring = true
  if self.retention is Some(retention) {
    match retention.retry_cleanup() {
      Ok(_) => ()
      Err(issue) => return Err(Retention(issue))
    }
  }
  @execution.cancel_completed_relation_export_receipt(self.receipt)
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(self.exported),
  )
  |> ignore
  if self.owned_result {
    self.result.output.cancel()
    self.owned_result = false
  }
  if self.owned_inputs is Some(inputs) {
    if !inputs.close() {
      return Err(Unavailable)
    }
    self.owned_inputs = None
  }
  self.created_targets = None
  self.closed = true
  Ok(true)
}
