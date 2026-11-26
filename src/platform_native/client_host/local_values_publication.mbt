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
/// Adopt only the actual capture issuer for this Native Values Work. The
/// first Model remains responsible for the paired evidence and its funding.
pub fn NativeClientValuesWork::bind_model_publication(
  self : Self,
  leader : NativeClientMockModelWork,
) -> Result[Array[String], NativeClientValuesPublicationIssue] {
  guard self.managed is Some(owner) &&
    self.publication_invocation is None &&
    leader.publication_inputs is None &&
    leader.provider_role is PortableHttp(_) &&
    physical_equal(leader.request, self.start.request) &&
    physical_equal(leader.compiled, self.compiled) &&
    physical_equal(leader.definition, self.definition) &&
    leader.observation is Some(issued) else {
    return Err(BindingMismatch)
  }
  let policy = match local_values_publication_policy(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard leader.observation_original() is Some((observation, invocation) as pair) &&
    @infer.original_model_publication_inputs(
      issued,
      self.compiled,
      self.definition,
    )
    is Some((inputs, _) as material) else {
    return Err(BindingMismatch)
  }
  match
    @local.bind_program_model_publication_invocation(
      owner,
      self.prepared,
      self.compiled,
      self.definition,
      self.run,
      observation,
      invocation,
      inputs,
      policy,
    ) {
    Err(issue) => return Err(Preparation(issue))
    Ok(_) => ()
  }
  leader.publication_inputs = Some(material)
  self.publication_invocation = Some(pair)
  self
  .require_current()
  .map_err(issue => NativeClientValuesPublicationIssue::Work(issue))
  .map(_ => inputs)
}

///|
/// End semantic borrows after publication cleanup and before returning the
/// leader's Model reservation. Missing commit confirmation stays pending.
pub fn NativeClientValuesWork::retire_model_publication(self : Self) -> Bool {
  guard @host.client_compiled_run_has_infers(self.compiled) &&
    self.publication_invocation is Some((_, invocation)) else {
    return true
  }
  guard self.managed is Some(owner) &&
    @local.retire_program_model_publication_invocation(owner, invocation) else {
    return false
  }
  self.publication = None
  self.publication_invocation = None
  true
}

///|
fn local_values_publication_context_matches(
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  policy_cid : String,
  inputs : Array[String]?,
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
    (match inputs {
      None => result.input_relation_cids.is_empty()
      Some(original) => result.input_relation_cids == original
    }) &&
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
  model_leader? : NativeClientMockModelWork? = None,
) -> Result[
  @native_publication.NativePreparedCapturedRunPublication,
  NativeClientValuesPublicationIssue,
] {
  let policy_cid = match local_values_publication_policy(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (input_cids, model_evidence) = match model_leader {
    None => {
      guard !@host.client_compiled_run_has_infers(self.compiled) else {
        return Err(BindingMismatch)
      }
      (None, [])
    }
    Some(leader) => {
      guard self.publication_invocation is Some((observation, invocation)) &&
        physical_equal(leader.request, self.start.request) &&
        physical_equal(leader.compiled, self.compiled) &&
        physical_equal(leader.definition, self.definition) &&
        leader.observation_original()
        is Some((expected_observation, expected_invocation)) &&
        physical_equal(observation, expected_observation) &&
        physical_equal(invocation, expected_invocation) &&
        leader.publication_inputs is Some((inputs, evidence)) else {
        return Err(BindingMismatch)
      }
      (Some(inputs), evidence)
    }
  }
  if !local_values_publication_context_matches(
      self.compiled,
      self.definition,
      self.start.request,
      policy_cid,
      input_cids,
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
      model_evidence,
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
