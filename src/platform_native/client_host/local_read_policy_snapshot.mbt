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
  if journal.transaction_active {
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
  let scope = match
    @host.client_local_adopted_authority_scope_body(
      material,
      self.host.database,
      self.principal,
      self.connection,
    ) {
    Ok(body) =>
      match local_adoption_digest(self.crypto, body) {
        Ok(value) => value
        Err(issue) => return Err(Adoption(issue))
      }
    Err(issue) => return Err(Adoption(local_current_material_issue(issue)))
  }
  self.require_current_with_facts(
    scope,
    self.file_from_snapshot(),
    reads=Some(reads),
  )
}

///|
// The selected Result-policy path has two pure Journal intervals separated
// by the actual Store call. Never hold a Journal transaction around Store work
// or reuse an Account decision across that callback/physical return boundary.
fn NativeLocalReadPolicyBinding::resolve_policy_from_snapshot(
  self : NativeLocalReadPolicyBinding,
  capture : NativeLocalJournalCapture,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
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
    let resolved = match
      store.resolve_committed_result(
        facts.request.namespace_id,
        self.scope,
        definition_cid,
        facts.request.result_name,
        65536,
        8192,
        64,
      ) {
      Ok(Some(value)) => value
      Ok(None) =>
        return Err(
          Journal(
            PublicationObservation(@publication_store.DeliveryAttemptUnresolved),
          ),
        )
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    // The Store may dispatch its real operation ports. Reobserve the full
    // original current fence before using another Journal snapshot or tuple.
    match capture.check_current_in_original_read() {
      Ok(_) => ()
      Err(issue) => return Err(Adoption(issue))
    }
    let body = read_binding_in_journal_snapshot(
      host.journal,
      operations.reads,
      () => {
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
        // Re-read the original target after Store return. A changed installation,
        // definition or Store binding cannot be repaired by the previous facts.
        let current = match
          host.journal.lookup_with_reads(
            original,
            true,
            reads=Some(operations.reads),
          ) {
          Ok(Retained(value)) => value
          Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
          Err(issue) => return Err(Journal(issue))
        }
        if current.publication_binding != Some(binding) ||
          @publication.publication_contract_identity(current.definition) !=
          definition_cid {
          return Err(Journal(ForeignRun))
        }
        if facts.public_index_entry_cid !=
          @publication.publication_contract_identity(
            resolved.public_index_entry,
          ) ||
          facts.result_manifest_cid !=
          @publication.publication_contract_identity(resolved.result_manifest) ||
          facts.result_artifact_cid != resolved.read.result_artifact_cid ||
          facts.result_definition_cid != resolved.read.result_definition_cid ||
          facts.material_generation_cid != resolved.read.material_generation_cid {
          return Err(Journal(ForeignRun))
        }
        let (wire, comparison) = match
          host.journal.retained_policy_wire(
            original,
            reads=Some(operations.reads),
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        let body = match
          select_run_policy_wire(
            wire,
            comparison,
            resolved.read.effective_data_policy_cid,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Journal(issue))
        }
        if !self.selection.data_policy_cids.contains(
            @publication.captured_effect_dependency_body_cid(body),
          ) {
          return Err(PolicyNotSelected)
        }
        Ok(body)
      },
    )
    match body {
      Err(issue) => Err(issue)
      Ok(body) =>
        match capture.check_current_in_original_read() {
          Ok(_) => Ok(body)
          Err(issue) => Err(Adoption(issue))
        }
    }
  })
}
