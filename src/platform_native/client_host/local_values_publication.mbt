///|
// Both fixed Work families read the exact retained policy once. This pure
// interpretation creates no current observation, authority or new policy.
fn original_work_publication_policy(
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  record : NativeClientRunRecord,
  journal : NativeClientRunJournal,
) -> Result[String, NativeClientRunJournalIssue] {
  let expected = match run_policy_originals_wire(prepared, compiled~) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard record.publication_policy_originals is Some(original) else {
    return Err(PublicationPolicy(@checked.MissingDependency))
  }
  if original != expected {
    return Err(CustodyLost)
  }
  let bodies = match journal.publication_originals(original) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok(@publication.captured_effect_dependency_body_cid(bodies[0]))
}

///|
pub(all) enum NativeClientValuesPublicationIssue {
  Work(NativeClientValuesWorkIssue)
  Policy(NativeClientRunJournalIssue)
  BindingMismatch
  Invocation(@publication.RunEvidenceValueIssue)
  Preparation(@local.ClientClosedValuesPreparationIssue)
  Service(@native_publication.NativeRunPublicationIssue)
  Publication(@native_publication.NativeCapturedRunPublicationPreparationIssue)
}

///|
// Publication can only use policy originals already retained before the start
// claim. Missing custody is not repaired from a new configuration or preparation.
fn local_values_publication_policy(
  work : NativeClientValuesWork,
) -> Result[String, NativeClientValuesPublicationIssue] {
  match work.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let lookup = match work.original_access {
    None =>
      work.start.journal
      .lookup(work.start.request, (work.current)())
      .map_err(issue => NativeClientValuesPublicationIssue::Policy(issue))
    Some(access) =>
      access
      .lookup()
      .map_err(issue => NativeClientValuesPublicationIssue::Work(issue))
  }
  let record = match lookup {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(Policy(CustodyLost))
    Err(issue) => return Err(issue)
  }
  let policy = match
    original_work_publication_policy(
      work.prepared,
      work.compiled,
      record,
      work.start.journal,
    ) {
    Err(issue) => return Err(Policy(issue))
    Ok(value) => value
  }
  work
  .require_current()
  .map_err(issue => NativeClientValuesPublicationIssue::Work(issue))
  .map(_ => policy)
}

///|
/// Both compilation representations use the exact original checked policy.
/// An empty external-input list is a formal observation, never a fake Source.
pub fn NativeClientValuesWork::publication_invocation(
  self : NativeClientValuesWork,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  NativeClientValuesPublicationIssue,
] {
  let policy = match local_values_publication_policy(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.managed is Some(owner) {
    if self.publication_invocation is Some(original) {
      return Ok(original)
    }
    let invocation = match
      @local.issue_program_publication_invocation(
        owner,
        self.prepared,
        self.compiled,
        self.definition,
        policy,
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Preparation(issue))
    }
    // Retain the original issued pair before another fallible current check.
    self.publication_invocation = Some(invocation)
    return self
      .require_current()
      .map_err(issue => NativeClientValuesPublicationIssue::Work(issue))
      .map(_ => invocation)
  }
  let invocation = match
    @host.issue_client_compiled_local_values_invocation(
      self.compiled,
      self.definition,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  self
  .require_current()
  .map_err(issue => NativeClientValuesPublicationIssue::Work(issue))
  .map(_ => invocation)
}

///|
pub fn NativeClientValuesWork::install_publication_service(
  self : NativeClientValuesWork,
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
  NativeClientValuesPublicationIssue,
] {
  let bind_original : ((String) -> Result[Unit, NativeClientValuesWorkIssue])? = match
    self.original_access {
    None => None
    Some(access) => Some(binding => access.bind_publication(binding))
  }
  let fence_original : ((
    String,
    () -> Result[
      @native_publication.NativeRunPublicationResult,
      @native_publication.NativeRunPublicationIssue,
    ],
  ) -> Result[
    @native_publication.NativeRunPublicationResult,
    @native_publication.NativeRunPublicationIssue,
  ])? = match self.original_access {
    None => None
    Some(access) =>
      Some((binding, commit) => {
        access.fence_publication(self.definition, binding, commit)
      })
  }
  install_native_client_work_publication_service(
    self.start.journal,
    self.start.request,
    self.definition,
    self.current,
    () => self.require_current(),
    store,
    namespace_id,
    authorize,
    max_wire_bytes,
    max_nodes,
    max_depth,
    request_authorize~,
    bind_original~,
    fence_original~,
  ).map_err(issue => {
    match issue {
      Work(issue) => NativeClientValuesPublicationIssue::Work(issue)
      Journal(issue) => NativeClientValuesPublicationIssue::Policy(issue)
      Service(issue) => NativeClientValuesPublicationIssue::Service(issue)
    }
  })
}

///|
fn local_values_publication_context_matches(
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  policy_cid : String,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  intent : @native_publication.NativeRunPublicationIntent,
) -> Bool {
  results.length() == @host.client_compiled_run_result_names(compiled).length() &&
  results.length() > 0 &&
  intent.authority_scope_cid ==
  @host.client_request_authority_scope_cid(request) &&
  results
  .iter()
  .all(result => {
    result.scope_cid == @publication.publication_contract_identity(definition) &&
    result.computation_contract_cid ==
    @publication.publication_contract_identity(
      @host.client_compiled_run_plan(compiled),
    ) &&
    result.input_relation_cids.is_empty() &&
    result.effective_data_policy_cid == policy_cid
  })
}

///|
/// Persist every declared Named Result from the original managed Values
/// occurrence. The checked bridge owns row/type/order validation; the existing
/// Native publication Owner owns payload custody, commit and cleanup retries.
/// No Run success, delivery grant or read permission is issued by preparation.
pub fn NativeClientValuesWork::prepare_local_publication(
  self : NativeClientValuesWork,
  service : @native_publication.NativeRunPublicationService,
  results : Array[@native_publication.NativeCapturedResultPublicationContext],
  authoring : @publication.RunEvidenceValue,
  intent : @native_publication.NativeRunPublicationIntent,
  occurrence : @native_publication.NativeRunPublicationOccurrence,
  row_limits : @execution.RetainedRowDecodeLimits,
  max_entries : Int,
  max_name_bytes : Int,
  limits : @host.PublicationOutputExportLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @native_publication.NativePreparedCapturedRunPublication,
  NativeClientValuesPublicationIssue,
] {
  let policy_cid = match local_values_publication_policy(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !local_values_publication_context_matches(
      self.compiled,
      self.definition,
      self.start.request,
      policy_cid,
      results,
      intent,
    ) {
    return Err(BindingMismatch)
  }
  let (observation, invocation) = match
    self.publication_invocation(max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.managed is Some(owner) && self.publication is None {
    match @local.reserve_program_publication(owner, self.prepared) {
      Ok(value) => self.publication = Some(value)
      Err(issue) => return Err(Preparation(issue))
    }
  }
  let normalization_journal = match self.normalization_evidence() {
    Ok(value) => value
    Err(issue) => return Err(Work(issue))
  }
  let bridges : Array[@local.LocalValuesResultExport] = []
  for index in 0..<results.length() {
    match
      self.prepare_result_export(
        index, row_limits, max_entries, max_name_bytes, limits,
      ) {
      Ok(value) => bridges.push(value)
      Err(issue) => {
        for bridge in bridges {
          bridge.close()
        }
        return Err(Work(issue))
      }
    }
  }
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => {
      for bridge in bridges {
        bridge.close()
      }
      return Err(Work(issue))
    }
  }
  let prepared = @native_publication.prepare_exported_effect_free_run_publication_native(
    service,
    self.run,
    {
      admission: @host.client_compiled_run_admission(self.compiled),
      run_definition: self.definition,
      invocation,
      observation,
      normalization_journal,
      binding_names: [],
      binding_digests: [],
      source_evidence: [],
      model_evidence: [],
      barrier_attempt_receipt_cids: [],
      source_advances: [],
      authoring,
    },
    bridges.map(bridge => bridge.output_export()),
    results,
    intent,
    occurrence,
    publication=self.publication,
  ).map_err(issue => NativeClientValuesPublicationIssue::Publication(issue))
  // The synchronous persistence traversal and its receipt replay have ended.
  // Pending Store cleanup remains inside the original preparation result.
  for bridge in bridges {
    bridge.close()
  }
  prepared
}
