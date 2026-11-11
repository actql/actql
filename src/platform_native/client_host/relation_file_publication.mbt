///|
/// Immutable bounds from this SAME checked physical Plan. Current/Source and
/// publication authority remain at the actual Work/service boundaries.
pub fn NativeClientRelationFileWork::publication_limits(
  self : NativeClientRelationFileWork,
  max_payload_bytes : Int,
) -> (@execution.RetainedRowDecodeLimits, @host.PublicationOutputExportLimits)? {
  match (self.plan, self.access.source) {
    (QueryFileExecution(requirements), _) =>
      requirements.publication_limits(self.prepared, max_payload_bytes)
    (WholeFileExecution(rows, _, _), WholeRelationFile(_, _, _, owner, _, _)) =>
      @local.installed_managed_publication_limits(
        owner,
        self.prepared,
        max_payload_bytes,
      ).map(limits => (rows, limits))
    _ => None
  }
}

///|
pub fn NativeClientRelationFileWork::publication_entry_limits(
  self : NativeClientRelationFileWork,
) -> (Int, Int)? {
  match self.plan {
    QueryFileExecution(requirements) =>
      requirements.publication_entry_limits(self.prepared)
    WholeFileExecution(_, bridge, evidence) => Some((bridge, evidence))
  }
}

///|
// Exact existing body extents plus this phase's quoted identity/metadata peak.
// A failed grow is sticky on this Work; neither retry nor retirement refunds it.
fn NativeClientRelationFileWork::grow_publication_identity(
  self : Self,
  metadata : Int64,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  if self.publication_growing ||
    self.stopping ||
    !self.entry.arena.matches_business_scope(false) {
    return Err(OriginalRunNotCurrent)
  }
  guard self.access.source is WholeRelationFile(_, _, _, owner, _, _) &&
    @local.installed_managed_preparation_admission_original(
      owner,
      self.prepared,
      self.start.request,
    )
    is Some(admission) else {
    return Err(OriginalRunNotCurrent)
  }
  let ledger = @strategy.captured_dag_ledger(self.run)
  let (r, e) = match self.publication_basis {
    Some(value) => value
    None => {
      let extents = match
        @resources.prepared_run_native_capacity(
          admission,
          self.prepared,
          ledger,
        ) {
        Err(issue) => return Err(InstalledRun(@local.Resource(issue)))
        Ok(value) => value
      }
      self.publication_basis = Some(extents)
      extents
    }
  }
  guard @execution.checked_preparation_add_product(r, metadata, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, metadata, 1L) is Some(e) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      e,
      @execution.execution_capacity_execution_bytes(capacity),
      1L,
    )
    is Some(e) else {
    return Err(Configuration)
  }
  let current = match
    @resources.prepared_run_native_capacity(admission, self.prepared, ledger) {
    Err(issue) => return Err(InstalledRun(@local.Resource(issue)))
    Ok(value) => value
  }
  self.publication_growing = true
  let result = @resources.grow_prepared_run_native_work_capacity(
    admission,
    self.prepared,
    ledger,
    Int64::max(r, current.0),
    Int64::max(e, current.1),
  )
  self.publication_growing = false
  match result {
    Err(issue) => Err(InstalledRun(@local.Resource(issue)))
    Ok(_) => self.require_current()
  }
}

///|
/// Evidence from the actual retained whole input and original source policy.
/// This issues once on the same Run and cannot substitute an empty audit.
pub fn NativeClientRelationFileWork::publication_invocation(
  self : NativeClientRelationFileWork,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    String,
    String,
  ),
  NativeClientSourceWorkIssue,
] {
  if self.publication_identity_issue is Some(issue) {
    return Err(issue)
  }
  if self.publication_growing {
    return Err(OriginalRunNotCurrent)
  }
  let result = self.publication_invocation_original(
    max_wire_bytes, max_nodes, max_depth,
  )
  if result is Err(issue) {
    self.publication_identity_issue = Some(issue)
  }
  result
}

///|
fn NativeClientRelationFileWork::publication_invocation_original(
  self : NativeClientRelationFileWork,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
    String,
    String,
  ),
  NativeClientSourceWorkIssue,
] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.publication_original is Some(original) {
    return Ok(original)
  }
  guard self.access.source
    is WholeRelationFile(_, original, acquisition, owner, _, _) &&
    self.capture_times is Some((started, completed)) &&
    self.identity_scan is None else {
    return Err(Configuration)
  }
  let captured = match self.source.capture() {
    Err(issue) => return Err(RelationFile(issue))
    Ok(value) => value
  }
  let input = match @rows.row_capture_source(captured) {
    Err(issue) => return Err(CaptureIdentity(issue))
    Ok(value) => value
  }
  // Reuse the existing closed-protocol quote for four simultaneously retained
  // logical/Source/observation/invocation artifacts plus the caller's Result
  // retention envelope under the resolved policy. Inputs use their original
  // acquisition's limits, not the possibly smaller aggregate Result bounds.
  // The same original tuple/Some/Ok and final map closure: H4/R9/S2.
  // These borrow the actual input CID/policy strings; no wire is parsed again.
  guard @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 9L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @host.client_protocol_metadata_construction_bytes(
      max_wire_bytes,
      max_nodes.to_int64(),
      copies=5,
      extra_controls=controls,
    )
    is Some((metadata, _)) else {
    return Err(Configuration)
  }
  let bounds = @rows.row_input_acquisition_limits(acquisition)
  guard @execution_query.captured_source_cell_identity_start_capacity(input)
    is Some(initial) &&
    @execution_query.captured_source_cell_identity_workspace_slots(
      input,
      bounds.retention,
      bounds.wire,
      bounds.wire,
    )
    is Some(workspace_slots) else {
    return Err(Configuration)
  }
  match self.grow_publication_identity(metadata, initial) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let scan = match
    @execution_query.start_captured_source_cell_identity(
      input,
      bounds.max_rows,
      bounds.retention,
      bounds.wire,
      bounds.wire,
      {
        max_fields: bounds.wire.max_columns,
        max_bytes: bounds.wire.max_bytes,
        max_nodes: bounds.wire.max_nodes,
        max_depth: bounds.wire.max_depth,
      },
      bounds.retention.max_work,
      workspace_slots,
      bounds.wire.max_bytes,
    ) {
    Err(issue) => return Err(CaptureIdentity(issue))
    Ok(value) => value
  }
  self.identity_scan = Some(scan)
  while true {
    guard @execution_query.captured_source_cell_identity_next_capacity(scan)
      is Some(next) else {
      return Err(Configuration)
    }
    match self.grow_publication_identity(metadata, next) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    match
      @execution_query.advance_captured_source_cell_identity(scan, 31, next) {
      Err(issue) => return Err(CaptureIdentity(issue))
      Ok((true, _)) => break
      Ok((false, _)) => ()
    }
  }
  let identity = match
    @execution_query.finish_captured_source_cell_identity(scan) {
    Err(issue) => return Err(CaptureIdentity(issue))
    Ok(value) => value
  }
  self.identity_scan = None
  let logical = match
    @host.issue_captured_whole_source_input_logical(
      @strategy.captured_dag_graph(self.run),
      input,
      identity,
      original,
    ) {
    Err(issue) => return Err(InputLogical(issue))
    Ok(value) => value
  }
  let lookup = match self.access.lookup() {
    Err(issue) => return Err(OriginalOperation(issue))
    Ok(Retained(value)) => value
    Ok(_) => return Err(NeedsOriginalReconciliation)
  }
  let policy = match
    original_work_publication_policy(
      self.prepared,
      self.compiled,
      lookup,
      self.start.journal,
    ) {
    Err(issue) => return Err(Journal(issue))
    Ok(value) => value
  }
  let facts = @rows.row_input_acquisition_facts(acquisition)
  let scope = @host.client_request_authority_scope_cid(self.start.request)
  let evidence = match
    @rows.issue_row_input_source_evidence(
      acquisition,
      captured,
      identity,
      logical,
      scope,
      facts.source_data_policy_cid,
      completed,
    ) {
    Err(issue) => return Err(SourceEvidence(issue))
    Ok(value) => value
  }
  let (observation, invocation) = match
    @local.issue_program_whole_source_publication_invocation(
      owner,
      self.prepared,
      self.compiled,
      self.definition,
      captured,
      identity,
      evidence,
      logical,
      scope,
      policy,
      started,
      completed,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  let original = (
    evidence,
    logical,
    observation,
    invocation,
    @execution_query.captured_source_relation_logical_cid(identity),
    policy,
  )
  self.publication_original = Some(original)
  self.require_current().map(_ => original)
}

///|
pub fn NativeClientRelationFileWork::install_publication_service(
  self : NativeClientRelationFileWork,
  store : @publication_store.Store,
  namespace_id : String,
  authorize : (@native_publication.NativeRunPublicationAuthorization) -> Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  request_authorize? : ((
    @publication.PublicationRequestContext,
    @native_publication.NativeRunPublicationAuthorization,
  ) -> Bool)? = None,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeClientSourcePublicationIssue,
] {
  install_native_client_work_publication_service(
    self.start.journal,
    self.start.request,
    self.definition,
    () => self.access.current(),
    () => self.require_current(),
    store,
    namespace_id,
    authorize,
    max_wire_bytes,
    max_nodes,
    max_depth,
    request_authorize~,
    bind_original=Some(binding => {
      self.access.base
      .bind_publication(binding)
      .map_err(issue => NativeClientSourceWorkIssue::OriginalOperation(issue))
    }),
    fence_original=Some((binding, commit) => {
      self.access.base.fence_publication(self.definition, binding, commit)
    }),
  ).map_err(issue => {
    match issue {
      Work(issue) => NativeClientSourcePublicationIssue::Work(issue)
      Journal(issue) => NativeClientSourcePublicationIssue::Policy(issue)
      Service(issue) => NativeClientSourcePublicationIssue::Service(issue)
    }
  })
}

///|
pub fn NativeClientRelationFileWork::prepare_local_publication(
  self : NativeClientRelationFileWork,
  service : @native_publication.NativeRunPublicationService,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  original_normalization : @host.ClientLocalNormalization,
  authoring : @publication.RunEvidenceValue,
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
  limits : @host.PublicationOutputExportLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @native_publication.NativePreparedCapturedRunPublication,
  NativeClientSourcePublicationIssue,
] {
  let (source, _logical, observation, invocation, input_cid, policy) = match
    self.publication_invocation(max_wire_bytes, max_nodes, max_depth) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  guard results.length() == 1 &&
    self.access.source is WholeRelationFile(_, _, _, owner, _, _) &&
    results[0].input_relation_cids == [input_cid] &&
    results[0].effective_data_policy_cid == policy &&
    results[0].scope_cid ==
    @publication.publication_contract_identity(self.definition) &&
    results[0].computation_contract_cid ==
    @publication.publication_contract_identity(
      @host.client_compiled_run_plan(self.compiled),
    ) &&
    intent.authority_scope_cid ==
    @host.client_request_authority_scope_cid(self.start.request) else {
    return Err(SourceBindingMismatch)
  }
  if self.publication is None {
    match @local.reserve_program_publication(owner, self.prepared) {
      Err(issue) => return Err(Work(Preparation(issue)))
      Ok(value) => self.publication = Some(value)
    }
  }
  let normalization = match
    @host.prepared_client_local_normalization_evidence(
      self.prepared,
      original_normalization,
    ) {
    Err(issue) => return Err(Normalization(issue))
    Ok(value) => value
  }
  let output = match self.prepare_result_export(limits) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  match self.require_current() {
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  let prepared = @native_publication.prepare_exported_effect_free_run_publication_native(
    service,
    self.run,
    {
      admission: @host.client_compiled_run_admission(self.compiled),
      run_definition: self.definition,
      invocation,
      observation,
      normalization_journal: normalization,
      binding_names: [],
      binding_digests: [],
      source_evidence: [source],
      model_evidence: [],
      barrier_attempt_receipt_cids: [],
      source_advances: [],
      authoring,
    },
    [output],
    results,
    intent,
    occurrence,
    publication=self.publication,
  ).map_err(issue => CapturedPublication(issue))
  self.close_export()
  prepared
}
