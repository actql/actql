///|
// A query refusal is not absence. Only a completed original return permits an
// unknown observation; a pending physical scope remains a command failure.
fn run_availability_query_issue(
  operation : NativeLocalStoreOperation,
  issue : @publication_store.NativePublicationStoreIssue,
) -> Result[@publication.ResultAvailabilityReason, NativeClientRunJournalIssue] {
  match operation.pending_scope() {
    Ok(false) => ()
    _ => return Err(PublicationObservation(issue))
  }
  match issue {
    @publication_store.OperationRouting(_, _)
    | @publication_store.OperationCleanup(_, _)
    | @publication_store.CleanupPending
    | @publication_store.ReaderBusy
    | @publication_store.Closed => Err(PublicationObservation(issue))
    @publication_store.ClockRegression => Ok(@publication.ClockUncertain)
    _ => Ok(@publication.StoreQueryFailed)
  }
}

///|
fn observe_run_result_availability(
  journal : NativeClientRunJournal,
  authority : NativeLocalPolicyAuthority,
  original : NativeClientOriginalRunSelection,
  manifest : @publication.PublicationContract,
  store : @publication_store.Store,
  namespace_id : String,
  operation : NativeLocalStoreOperation,
  name : String,
  observed_at : String,
  reads : NativeClientJournalReadAccess,
) -> Result[@publication.ResultAvailability, NativeClientRunJournalIssue] {
  if !authority.current_for(journal, original.request) {
    return Err(AuthorizationDenied)
  }
  let resolved = match
    store.resolve_committed_result(
      namespace_id,
      original.scope,
      @publication.publication_contract_identity(original.definition),
      name,
      65536,
      8192,
      64,
    ) {
    Ok(Some(value)) => value
    Ok(None) =>
      return Ok({
        name,
        state: @publication.Unavailable,
        reason: @publication.NotPublished,
      })
    Err(issue) =>
      return run_availability_query_issue(operation, issue).map(reason => {
        name,
        state: @publication.Unknown,
        reason,
      })
  }
  if @publication.publication_contract_identity(resolved.result_manifest) !=
    @publication.publication_contract_identity(manifest) {
    return Err(CustodyLost)
  }
  // Retained Policy availability is metadata, not a new Policy evaluation or
  // named-Result Account grant. Payload reading remains separately authorized.
  match
    journal.lookup_publication_policy_original(
      original.request,
      resolved.read.effective_data_policy_cid,
      authority,
      reads=Some(reads),
    ) {
    Ok(_) => ()
    Err(PublicationPolicy(@checked.MissingDependency)) =>
      return Ok({
        name,
        state: @publication.Unavailable,
        reason: @publication.PolicyUnavailable,
      })
    Err(issue) => return Err(issue)
  }
  let schema = match store.read_result_schema(resolved.read.result_schema_cid) {
    Ok(value) => value
    Err(issue) =>
      return run_availability_query_issue(operation, issue).map(reason => {
        name,
        state: @publication.Unknown,
        reason,
      })
  }
  match
    store.observe_publication_payload_facts(
      [resolved.binding],
      [schema],
      65536,
      8192,
      64,
    ) {
    Ok(_) => ()
    Err(issue) =>
      return run_availability_query_issue(operation, issue).map(reason => {
        name,
        state: @publication.Unknown,
        reason,
      })
  }
  let clock = match
    @publication.result_retention_clock_contract_cid(resolved.retention) {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(DeliveryIssuance(issue)))
  }
  let trusted_at = match store.observe_trusted_clock(clock, observed_at) {
    Ok(value) => value
    Err(issue) =>
      return run_availability_query_issue(operation, issue).map(reason => {
        name,
        state: @publication.Unknown,
        reason,
      })
  }
  let retention = match
    @publication.result_read_availability(
      manifest,
      name,
      resolved.retention,
      trusted_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(DeliveryIssuance(issue)))
  }
  if !authority.current_for(journal, original.request) {
    return Err(AuthorizationDenied)
  }
  match retention {
    "available" =>
      Ok({
        name,
        state: @publication.Available,
        reason: @publication.ConfirmedPresent,
      })
    "retention_expired" | "delete_due" =>
      // A retention endpoint is not an observation that deletion occurred.
      Ok({
        name,
        state: @publication.Unavailable,
        reason: @publication.RetentionExpired,
      })
    _ => Err(CustodyLost)
  }
}

///|
fn run_observation_store_binding(
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[String, NativeClientRunJournalIssue] {
  let (authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  installed_publication_binding(namespace_id, authority, device, inode)
}

///|
// This CAS updates only the existing observation on the authenticated original
// Submission. It never saves/advances the Run, starts Work or creates a receipt.
fn NativeClientRunJournal::retain_run_availability_observation(
  self : NativeClientRunJournal,
  original : NativeClientOriginalRunSelection,
  prior : NativeClientSavedRunState,
  manifest : @publication.PublicationContract,
  observed_wire : String,
  store : @publication_store.Store,
  namespace_id : String,
  binding : String,
  authority : NativeLocalPolicyAuthority,
  operations : NativeClientJournalOperationAccess,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  guard prior.original is Some(prior_original) else { return Err(CustodyLost) }
  self.transaction_with_reads(
    () => {
      if !authority.current_for(self, original.request) {
        return Err(AuthorizationDenied)
      }
      let (submission, run) = match
        self.saved_run_state_locked(
          original.reference,
          original.request,
          reads=Some(operations.reads),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @publication.publication_contract_identity(run.definition) !=
        @publication.publication_contract_identity(original.definition) ||
        run.run_observation_originals is None ||
        run.publication_binding != Some(binding) ||
        submission.run_state_original != Some(prior_original.wire()) {
        return Err(CustodyLost)
      }
      guard submission.run_state_observation is Some((revision, Some(key))) else {
        return Err(CustodyLost)
      }
      let prior_observation = match
        native_saved_state_observation(run, prior_original, revision) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if prior_observation.key() != key {
        return Err(CustodyLost)
      }
      let run_id = match @publication.run_definition_run_id(run.definition) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let observation = match
        @publication.prepare_run_state_observation(
          observed_wire, run_id, revision, 65536, 8192, 64,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      // Timestamps are not new logical availability facts. Keep the exact
      // admitted original and its revision when the observation key is equal;
      // do not reserialize or durably write an unchanged status read.
      if observation.key() == key {
        if !authority.current_for(self, original.request) {
          return Err(AuthorizationDenied)
        }
        match run_observation_store_binding(store, namespace_id) {
          Ok(current) if current == binding => ()
          Ok(_) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        return Ok({
          original: prior.original,
          state_wire: prior.wire(),
          control_revision: run.revision,
        })
      }
      let next = match observation.next_revision(Some(key), revision) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let state_wire = match observation.wire(next) {
        Ok(value) => value
        Err(_) => return Err(CapacityExceeded)
      }
      let state = match
        @host.prepare_client_run_state_original(
          run.definition,
          manifest,
          state_wire,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let body = match
        submitted_intent_body(
          before_construction=submitted_encode_construction(
            self.database,
            Some(operations),
          ),
          submission.reference,
          submission.intent,
          run_admission=submission.run_admission,
          run_state_original=Some(state.wire()),
          run_state_observation=Some((next, Some(observation.key()))),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !authority.current_for(self, original.request) {
        return Err(AuthorizationDenied)
      }
      match run_observation_store_binding(store, namespace_id) {
        Ok(current) if current == binding => ()
        Ok(_) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if submission.run_state_original != Some(state.wire()) {
        self.invalidate_operation_submission()
        match
          compare_exchange_client_journal_value(
            self.database,
            "client_submitted_intents",
            original.reference.request_id,
            submission.revision,
            body,
            Some(operations),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      if !authority.current_for(self, original.request) {
        return Err(AuthorizationDenied)
      }
      match run_observation_store_binding(store, namespace_id) {
        Ok(current) if current == binding => ()
        Ok(_) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      Ok({
        original: Some(state),
        state_wire: state.state_wire(),
        control_revision: run.revision,
      })
    },
    reads=Some(operations.reads),
  )
}

///|
/// Reobserve only this saved original Run under current RunRead. The Store,
/// original operation and installed namespace must match its retained binding.
/// No Result read authority, grant, attempt, payload stream or execution starts.
pub fn NativeLocalJournalCapture::refresh_original_run_availability_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  operation : NativeLocalStoreOperation,
  observed_at : String,
  now : Double,
) -> Result[
  Result[NativeClientSavedRunStateSelection, NativeClientSavedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    let result = host.refresh_original_run_availability(
      self, principal, connection, original, store, namespace_id, operation, observed_at,
      now, operations,
    )
    match result {
      Err(Journal(TransactionUnknown)) => Err(Journal(TransactionUnknown))
      Err(Journal(Epoch(TransactionUnknown))) =>
        Err(Journal(Epoch(TransactionUnknown)))
      _ => Ok(result.map(state => { original, state, }))
    }
  })
}

///|
fn NativeLocalHostConnection::refresh_original_run_availability(
  self : NativeLocalHostConnection,
  capture : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
  operation : NativeLocalStoreOperation,
  observed_at : String,
  now : Double,
  operations : NativeClientJournalOperationAccess,
) -> Result[NativeClientSavedRunState, NativeClientSavedRunStateIssue] {
  let authority = match
    native_local_policy_authority_for(
      self,
      capture.crypto,
      principal,
      connection,
      original.request,
      ReadRunMaterials,
      capture=Some(capture),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if original.scope != authority.scope ||
    namespace_id.is_empty() ||
    !physical_equal(operation.receiver.capture, capture) ||
    !(operation.receiver.domain is StoreRunObservationDomain) {
    return Err(Journal(ForeignRun))
  }
  let bridge = match operation.sqlite_original() {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  if !store.matches_original_operation(bridge) {
    return Err(Journal(ForeignRun))
  }
  let prior = match
    self.lookup_submitted_run_state_with_operations(
      capture.crypto,
      principal,
      connection,
      original.reference,
      original.request,
      now,
      operations=Some(operations),
      capture=Some(capture),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Pending Checkpoint lifecycle has no published Result Manifest. Its exact
  // authenticated state already says not_published; do not turn this into a
  // Store observation, grant Result access, or advance an observation counter.
  guard prior.original is Some(prior_original) else { return Ok(prior) }
  let manifest = prior_original.original_manifest()
  let binding = match run_observation_store_binding(store, namespace_id) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  // Authenticate the namespace/physical Store before any Result lookup.
  let retained_binding = match
    self.journal.transaction_with_reads(
      () => {
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        let (_, run) = match
          self.journal.saved_run_state_locked(
            original.reference,
            original.request,
            reads=Some(operations.reads),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if @publication.publication_contract_identity(run.definition) !=
          @publication.publication_contract_identity(original.definition) {
          return Err(ForeignRun)
        }
        if !authority.current_for(self.journal, original.request) {
          return Err(AuthorizationDenied)
        }
        Ok(run.publication_binding)
      },
      reads=Some(operations.reads),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if retained_binding != Some(binding) {
    return Err(Journal(ForeignRun))
  }
  let names = match @publication.manifest_result_names(manifest) {
    Ok(value) => value
    Err(issue) =>
      return Err(Journal(PublicationObservation(DeliveryIssuance(issue))))
  }
  let observations : Array[@publication.ResultAvailability] = []
  for name in names {
    let observed = match
      observe_run_result_availability(
        self.journal,
        authority,
        original,
        manifest,
        store,
        namespace_id,
        operation,
        name,
        observed_at,
        operations.reads,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    observations.push(observed)
  }
  let run_id = match @publication.run_definition_run_id(original.definition) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  let wire = match
    @publication.issue_succeeded_run_state(
      run_id,
      observed_at,
      names,
      observations,
      names.map(_ => observed_at),
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  self.journal
  .retain_run_availability_observation(
    original, prior, manifest, wire, store, namespace_id, binding, authority, operations,
  )
  .map_err(issue => Journal(issue))
}
