///|
// Only the closed current/selection/target-read predicates below join a live
// Journal snapshot. The Store is called after this snapshot has returned;
// disclosure, delivery and mutation retain their own operation boundaries.
fn[T] read_binding_in_journal_snapshot(
  journal : NativeClientRunJournal,
  reads : NativeClientJournalReadAccess,
  call : () -> Result[T, NativeLocalReadBindingIssue],
) -> Result[T, NativeLocalReadBindingIssue] {
  if journal.fenced ||
    client_journal_transaction_fenced(journal.database, Some(reads)) {
    return Err(Journal(Fenced))
  }
  if journal.transaction_active || journal.operation_active {
    return call()
  }
  let output : Ref[Result[T, NativeLocalReadBindingIssue]?] = Ref(None)
  let result = journal.transaction_with_reads(
    () => {
      let result = call()
      output.val = Some(result)
      match result {
        Ok(value) => Ok(value)
        Err(Journal(issue)) => Err(issue)
        Err(_) => Err(AuthorizationDenied)
      }
    },
    reads=Some(reads),
  )
  match (result, output.val) {
    (Err(TransactionUnknown), original) =>
      Err(
        OriginalRead(
          match original {
            Some(Err(issue)) => Some(issue)
            _ => None
          },
          TransactionUnknown,
        ),
      )
    (Err(_), Some(Err(issue))) => Err(issue)
    (Err(issue), _) => Err(Journal(issue))
    (Ok(value), _) => Ok(value)
  }
}

///|
// The surrounding original current admission checked this immutable selected
// list. Selecting it again does not reopen its file or bind another capture.
fn NativeLocalReadPolicyBinding::file_from_snapshot(
  self : NativeLocalReadPolicyBinding,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  match
    self.host.session.settings.files
    .iter()
    .find_first(file => file.name == self.file.name) {
    Some(file) => Ok(file.body)
    None => Err(CustodyLost)
  }
}

///|
// Both Account tuples are evaluated independently from the same admitted
// material, once per pure interval. This is not an operation-spanning Allow.
fn NativeLocalReadPolicyBinding::require_request_in_snapshot(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  match self.require_current_in_snapshot(material, reads) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.require_request_constraints(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.capture {
    None =>
      if native_local_policy_account_allowed(
          material,
          self.host.database,
          self.principal,
          self.connection,
          ReadResultPolicy(facts.request.result_name),
        ) {
        Ok(())
      } else {
        Err(Journal(AuthorizationDenied))
      }
    Some(capture) => {
      for resource in ["run", "result/" + facts.request.result_name] {
        match
          capture.operation_account(self.host, material, {
            principal: self.principal,
            connection: self.connection,
            resource,
            operation: "read",
          }) {
          Ok(@authorization.Allow(_)) => ()
          Ok(_) => return Err(Journal(AuthorizationDenied))
          Err(issue) => return Err(Adoption(issue))
        }
      }
      Ok(())
    }
  }
}

///|
fn NativeLocalReadPolicyBinding::require_current_in_snapshot(
  self : NativeLocalReadPolicyBinding,
  material : @host.ClientLocalAdoptedHostMaterial[
    @sqlite.Database,
    NativeLocalAdoptionIssue,
  ],
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  match self.current_operation_fact() {
    Ok(true) => return Ok(())
    Ok(false) => ()
    Err(issue) => return Err(issue)
  }
  let scope = match self.capture {
    Some(capture) =>
      capture.operation_scope(
        self.host,
        material,
        self.principal,
        self.connection,
      )
    None =>
      match
        @host.client_local_adopted_authority_scope_body(
          material,
          self.host.database,
          self.principal,
          self.connection,
        ) {
        Ok(body) => local_adoption_digest(self.crypto, body)
        Err(issue) => Err(local_current_material_issue(issue))
      }
  }
  let scope = match scope {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  let result = self.require_current_with_facts(
    scope,
    self.file_from_snapshot(),
    reads=Some(reads),
  )
  if result is Ok(_) {
    self.retain_current_operation_fact()
  }
  result
}

///|
// The existing command retains one set of exact facts across trusted Store
// metadata work. The Store never runs inside the Journal transaction. Its
// physical return/cleanup is still actual; it is not a new permission frame.
fn NativeLocalReadPolicyBinding::resolve_policy_from_snapshot(
  self : NativeLocalReadPolicyBinding,
  capture : NativeLocalJournalCapture,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
  committed_result? : @publication_store.NativeCommittedResult? = None,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeLocalReadBindingIssue,
] {
  read_binding_with_material_in_original_read(capture, (
    host,
    material,
    operations,
  ) => {
    if !physical_equal(host, self.host) {
      return Err(SelectionMismatch)
    }
    let record = match
      read_binding_in_journal_snapshot(host.journal, operations.reads, () => {
        match self.require_receiver(facts) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        match
          self.require_request_in_snapshot(
            original,
            facts,
            material,
            operations.reads,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        match
          host.journal.lookup_with_reads(
            original,
            true,
            reads=Some(operations.reads),
          ) {
          Ok(Retained(value)) => Ok(value)
          Ok(UnresolvedHistory) => Err(Journal(CustodyLost))
          Err(issue) => Err(Journal(issue))
        }
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let definition_cid = @publication.publication_contract_identity(
      record.definition,
    )
    if facts.request.run_definition_cid != definition_cid {
      return Err(Journal(ForeignRun))
    }
    let (store_authority, device, inode) = match store.custody_location() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    let binding = match
      installed_publication_binding(
        facts.request.namespace_id,
        store_authority,
        device,
        inode,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    if record.publication_binding != Some(binding) {
      return Err(Journal(ForeignRun))
    }
    let resolved = match committed_result {
      Some(value) => value
      None =>
        match
          local_committed_result_observation(
            store,
            facts.request.namespace_id,
            self.scope,
            definition_cid,
            facts.request.result_name,
            capture=Some(capture),
          ) {
          Ok(Some(value)) => value
          Ok(None) =>
            return Err(
              Journal(
                PublicationObservation(
                  @publication_store.DeliveryAttemptUnresolved,
                ),
              ),
            )
          Err(issue) => return Err(Journal(issue))
        }
    }
    // This synchronous trusted Store metadata read changes no Host, Account,
    // Run or selected configuration fact. Select the observed Policy from the
    // same admitted original; actual disclosure remains separately authorized.
    let body = {
      if facts.public_index_entry_cid !=
        @publication.publication_contract_identity(resolved.public_index_entry) ||
        facts.result_manifest_cid !=
        @publication.publication_contract_identity(resolved.result_manifest) ||
        facts.result_artifact_cid != resolved.read.result_artifact_cid ||
        facts.result_definition_cid != resolved.read.result_definition_cid ||
        facts.material_generation_cid != resolved.read.material_generation_cid {
        return Err(Journal(ForeignRun))
      }
      let (wire, comparison) = match
        extract_admitted_run_policy_wire(record, original) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      let body = match
        host.journal.select_publication_policy(
          wire,
          comparison,
          resolved.read.effective_data_policy_cid,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      match self.retain_result_policy_original(original, facts, body) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      Ok(body)
    }
    body
  })
}
