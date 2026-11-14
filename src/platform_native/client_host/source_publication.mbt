///|
pub(all) enum NativeClientSourcePublicationIssue {
  Work(NativeClientSourceWorkIssue)
  SourceBindingMismatch
  ModelEvidenceRequired
  Publication(@resident.ResidentSourceResultPublicationIssue)
  Service(@native_publication.NativeRunPublicationIssue)
  OriginalNormalizationMissing
  Normalization(@host.ClientLocalNormalizationIssue)
  CapturedPublication(
    @native_publication.NativeCapturedRunPublicationPreparationIssue
  )
  Policy(NativeClientRunJournalIssue)
}

///|
/// Publish the installed Local profile using its retained original audit.
/// Neither arbitrary journal bytes nor a journal from another preparation can
/// enter this boundary. Opening the profile already checked the audit before
/// Source I/O; publication rechecks its exact owner and current Run authority.
pub fn NativeClientSourceWork::prepare_local_publication(
  self : NativeClientSourceWork,
  service : @native_publication.NativeRunPublicationService,
  result : @native_publication.NativeCapturedResultPublicationContext,
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
    Err(issue) => return Err(Work(issue))
    Ok(_) => ()
  }
  guard self.local_normalization is Some((prepared, original)) else {
    return Err(OriginalNormalizationMissing)
  }
  if !@host.client_compiled_run_matches(self.compiled, prepared) {
    return Err(Normalization(@host.ForeignPreparation))
  }
  let evidence = match
    @host.prepared_client_local_normalization_evidence(prepared, original) {
    Err(issue) => return Err(Normalization(issue))
    Ok(value) => value
  }
  self.prepare_publication(
    service, result, evidence, authoring, intent, occurrence, limits, max_wire_bytes,
    max_nodes, max_depth,
  )
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
  request_authorize? : ((
    @publication.PublicationRequestContext,
    @native_publication.NativeRunPublicationAuthorization,
  ) -> Bool)? = None,
) -> Result[
  @native_publication.NativeRunPublicationService,
  NativeClientSourcePublicationIssue,
] {
  install_native_client_work_publication_service(
    self.journal,
    self.request,
    self.definition,
    self.current_authorization,
    () => self.require_current(),
    store,
    namespace_id,
    authorize,
    max_wire_bytes,
    max_nodes,
    max_depth,
    request_authorize~,
  ).map_err(issue => {
    match issue {
      Work(issue) => NativeClientSourcePublicationIssue::Work(issue)
      Journal(issue) => NativeClientSourcePublicationIssue::Work(Journal(issue))
      Service(issue) => NativeClientSourcePublicationIssue::Service(issue)
    }
  })
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
  match
    self.fence_publication_outcome(
      request, definition, binding, current, commit,
    ) {
    Ok(outcome) => outcome
    Err(_) => Err(@native_publication.CommitFenceUnavailable)
  }
}

///|
// Preserve the actual Journal transaction outcome until the selected original
// Read has processed its return. The legacy wrapper retains its same public
// publication error, while the original route can retain COMMIT Unknown too.
fn NativeClientRunJournal::fence_publication_outcome(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  binding : String,
  current : () -> Bool,
  commit : () -> Result[
    @native_publication.NativeRunPublicationResult,
    @native_publication.NativeRunPublicationIssue,
  ],
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[
  Result[
    @native_publication.NativeRunPublicationResult,
    @native_publication.NativeRunPublicationIssue,
  ],
  NativeClientRunJournalIssue,
] {
  if !current() {
    return Ok(Err(@native_publication.AccessDenied))
  }
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      guard self.retained(request, reads~) is Ok(Some(run)) &&
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
    },
    reads~,
  )
}

///|
/// Retain the original installed publication namespace and physical Store in
/// the same existing Run journal. Reinstallation cannot replace that binding.
fn NativeClientRunJournal::bind_publication(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  binding : String,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      let run = match self.retained(request, reads~) {
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
          self
          .save_with_operations(
            { ..run, publication_binding: Some(binding), },
            operations~,
          )
          .map(_ => ())
      }
    },
    reads~,
  )
}

///|
/// Host setup after trusted configuration adoption and original Run admission,
/// before any physical start. This installs no grant and cannot replace an
/// existing scope. Started unbound Runs require their original owner materials;
/// current configuration is not a recovery fallback.
pub fn NativeClientRunJournal::bind_installed_publication(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  publication : NativeClientCancellationPublication,
  current : () -> Bool,
) -> Result[Unit, NativeClientRunJournalIssue] {
  self.bind_installed_publication_with_operations(request, publication, current)
}

///|
fn NativeClientRunJournal::bind_installed_publication_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  publication : NativeClientCancellationPublication,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  guard publication.binding is Some(binding) else { return Err(Encoding) }
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      let run = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      match run.publication_binding {
        Some(original) if original == binding => Ok(())
        Some(_) => Err(ChangedIntent)
        None if !run.physical_start_claimed && !run.cancellation_requested =>
          self
          .save_with_operations(
            { ..run, publication_binding: Some(binding), },
            operations~,
          )
          .map(_ => ())
        None => Err(ChangedIntent)
      }
    },
    reads~,
  )
}
