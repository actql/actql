///|
pub(all) enum NativeClientSourcePublicationIssue {
  Work(NativeClientSourceWorkIssue)
  SourceBindingMismatch
  ModelEvidenceRequired
  Publication(@resident.ResidentSourceResultPublicationIssue)
  Service(@native_publication.NativeRunPublicationIssue)
}

///|
/// Install the existing publication service with both original-Run fencing
/// and current Host publication authority. Recheck after the Host callback;
/// a callback may itself accept cancellation or observe authority changes.
/// This grants neither delivery authority nor permission to replay execution.
pub fn NativeClientSourceWork::install_publication_service(
  self : NativeClientSourceWork,
  store : @publication_store.Store,
  namespace_id : String,
  authorize : (@native_publication.NativeRunPublicationAuthorization) -> Bool,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeClientSourcePublicationIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let observation = match
    install_native_client_cancellation_publication(
      store, namespace_id, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Work(Journal(issue)))
  }
  let binding = observation.binding.unwrap()
  match
    self.journal.bind_publication(
      self.request,
      binding,
      self.current_authorization,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Work(Journal(issue)))
  }
  let authority = @native_publication.install_native_run_publication_authority(fact => {
    if fact.namespace_id != namespace_id ||
      fact.authority_scope_cid !=
      @host.client_request_authority_scope_cid(self.request) ||
      fact.run_definition_cid !=
      @publication.publication_contract_identity(self.definition) ||
      self.require_current() is Err(_) {
      false
    } else {
      authorize(fact) && self.require_current() is Ok(_)
    }
  })
  @native_publication.install_native_run_publication_service(
    store,
    authority,
    max_wire_bytes,
    max_nodes,
    max_depth,
    commit_guard=commit => {
      self.journal.fence_publication(
        self.request,
        self.definition,
        binding,
        self.current_authorization,
        commit,
      )
    },
  ).map_err(issue => Service(issue))
}

///|
/// Prepare the actual retained Named Result through the existing publication
/// owner. The supplied Host retention/storage occurrence cannot replace the
/// original Run, checked plan, observed input or Source Policy. Normalization
/// and authoring facts remain explicit Host-issued evidence, not invented here.
/// Commit rechecks authority through the installed publication service; this
/// preparation does not mark a Run succeeded or confer a Result read grant.
pub fn NativeClientSourceWork::prepare_publication(
  self : NativeClientSourceWork,
  service : @native_publication.NativeRunPublicationService,
  result : @native_publication.NativeCapturedResultPublicationContext,
  normalization : @publication.RunEvidenceValue,
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
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  if !@host.client_compiled_run_infers(self.compiled).is_empty() {
    return Err(ModelEvidenceRequired)
  }
  if intent.authority_scope_cid !=
    @host.client_request_authority_scope_cid(self.request) ||
    result.scope_cid !=
    @publication.publication_contract_identity(self.definition) ||
    result.computation_contract_cid !=
    @publication.publication_contract_identity(
      @host.client_compiled_run_plan(self.compiled),
    ) {
    return Err(SourceBindingMismatch)
  }
  let (source_evidence, logical, observation, invocation) = match
    self.publication_invocation(limits, max_wire_bytes, max_nodes, max_depth) {
    Ok(values) => values
    Err(issue) => return Err(Work(issue))
  }
  // Both values were issued by the retained acquisition and admitted against
  // its checked Source above. Read only those existing facts; do not derive a
  // replacement input identity or weaken Policy from configuration.
  guard source_publication_text(
      logical, "logical_relation_cid", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(input_cid) &&
    source_publication_text(
      observation, "data_policy_cid", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(policy_cid) &&
    result.input_relation_cids == [input_cid] &&
    result.effective_data_policy_cid == policy_cid else {
    return Err(SourceBindingMismatch)
  }
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  self.owner
  .prepare_result_publication(
    service,
    {
      admission: @host.client_compiled_run_admission(self.compiled),
      run_definition: self.definition,
      invocation,
      observation,
      normalization_journal: normalization,
      binding_names: [],
      binding_digests: [],
      source_evidence: [source_evidence],
      model_evidence: [],
      barrier_attempt_receipt_cids: [],
      source_advances: [],
      authoring,
    },
    [result],
    intent,
    occurrence,
    limits,
  )
  .map_err(issue => Publication(issue))
}

///|
fn source_publication_text(
  value : @publication.RunEvidenceValue,
  field : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  let source = @source.parse_json_bytes_preserving(
    @utf8.encode(@publication.run_evidence_value_json(value)),
    { max_input_bytes: max_bytes, max_nodes, max_depth, },
  ).to_option()
  source
  .bind(source => {
    @decode.admit(source, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }).to_option()
  })
  .bind(cursor => @decode.open_object(cursor).to_option())
  .bind(object => epoch_text(object, field))
}

///|
/// Serialize the actual Store index commit with original cancellation admission.
/// This is a physical fence over existing Owners, not an atomic two-Store commit.
/// If journal confirmation is lost after the Store wins, the caller must inspect
/// that original Store; an error never proves that publication did not happen.
fn NativeClientRunJournal::fence_publication(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  binding : String,
  current : () -> Bool,
  commit : () -> Result[
    @native_publication.NativeRunPublicationResult,
    @native_publication.NativeRunPublicationIssue,
  ],
) -> Result[
  @native_publication.NativeRunPublicationResult,
  @native_publication.NativeRunPublicationIssue,
] {
  if !current() {
    return Err(@native_publication.AccessDenied)
  }
  match
    self.transaction(() => {
      guard self.retained(request) is Ok(Some(run)) &&
        @publication.publication_contract_identity(run.definition) ==
        @publication.publication_contract_identity(definition) &&
        run.publication_binding == Some(binding) &&
        run.physical_start_claimed &&
        !run.cancellation_requested else {
        return Err(CustodyLost)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      self.publication_read_locked = true
      let outcome = commit()
      self.publication_read_locked = false
      Ok(outcome)
    }) {
    Ok(outcome) => outcome
    Err(_) => Err(@native_publication.CommitFenceUnavailable)
  }
}

///|
/// Retain the original installed publication namespace and physical Store in
/// the same existing Run journal. Reinstallation cannot replace that binding.
fn NativeClientRunJournal::bind_publication(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  binding : String,
  current : () -> Bool,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let run = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    if run.cancellation_requested {
      return Err(ChangedIntent)
    }
    match run.publication_binding {
      Some(original) if original == binding => Ok(())
      Some(_) => Err(ChangedIntent)
      None =>
        self.save({ ..run, publication_binding: Some(binding), }).map(_ => ())
    }
  })
}
