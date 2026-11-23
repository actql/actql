///|
// Confirm actual terminal rows on the original Journal before exposing even
// an observation. Neither a Dispatching row nor a missing receipt is unsent.
fn NativeClientRunJournal::recover_file_effect_members_locked(
  self : Self,
  record : NativeClientRunRecord,
  preview : @publication.EffectPreviewIdentity,
  limits : @checkpoint.WireLimits,
  reads : NativeClientJournalReadAccess,
) -> Result[
  Array[@publication.PublicationContract],
  NativeClientRunJournalIssue,
] {
  guard self.transaction_active &&
    record.checkpoint is Some(checkpoint) &&
    checkpoint.state.status == @publication.Resuming &&
    !checkpoint.settlement_only &&
    !record.cancellation_requested &&
    checkpoint.unknown_effects.is_empty() &&
    @publication.effect_preview_run_identity(preview) ==
    @publication.publication_contract_identity(record.definition) &&
    @publication.effect_preview_semantic_identity(preview) ==
    checkpoint.artifact.checkpoint.required_artifact_cid else {
    return Err(Checkpoint(InvalidMaterial))
  }
  let rows : Array[
    (
      String,
      String,
      @effect.EffectLedgerEntry,
      @publication.PublicationContract,
    ),
  ] = []
  for head in checkpoint.effect_ledger {
    if effect_ledger_head(
        checkpoint.effect_ledger,
        head.logical_item_locator_cid,
      ).map(entry => entry.cid) !=
      Some(head.cid) {
      continue
    }
    if @effect.effect_ledger_entry_state_code(head) != 2 {
      return Err(Checkpoint(NeedsOriginalContinuation))
    }
    let receipt = match
      read_client_effect_receipt(self.database, head, reads=Some(reads)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @publication.effect_row_outcome_receipt_member_identity(receipt)
      is Some(member_cid) &&
      @publication.effect_row_outcome_receipt_row_identity(receipt)
      is Some(row_cid) &&
      @publication.effect_row_outcome_receipt_dispatch_identity(receipt)
      is Some(dispatch_cid) &&
      checkpoint.effect_ledger
      .iter()
      .find_first(entry => {
        entry.cid == dispatch_cid &&
        @effect.effect_ledger_entry_state_code(entry) == 1 &&
        entry.logical_item_locator_cid == head.logical_item_locator_cid &&
        entry.attempt_sequence == head.attempt_sequence
      })
      is Some(dispatch) else {
      return Err(CustodyLost)
    }
    let response = match
      read_client_effect_response_record(
        self.database,
        dispatch_cid,
        reads=Some(reads),
      ) {
      Ok(Some(value)) if value.protocol is FileOriginal(_) => value
      Err(issue) => return Err(issue)
      _ => return Err(CustodyLost)
    }
    match require_client_file_response_binding(record, dispatch, response) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    rows.push((member_cid, row_cid, head, receipt))
  }
  let members : Array[@publication.PublicationContract] = []
  let mut matched = 0
  for member_index in 0..<@publication.effect_preview_member_count(preview) {
    guard @publication.effect_preview_member_identity(preview, member_index)
      is Some(member_cid) &&
      @publication.effect_preview_row_count(preview, member_index)
      is Some(count) else {
      return Err(CustodyLost)
    }
    let heads = []
    let receipts = []
    for ordinal in 0..<count {
      guard @publication.effect_preview_ordered_row_identity(
          preview, member_index, ordinal,
        )
        is Some(row_cid) &&
        rows
        .iter()
        .find_first(item => item.0 == member_cid && item.1 == row_cid)
        is Some((_, _, head, receipt)) else {
        return Err(Checkpoint(NeedsOriginalContinuation))
      }
      heads.push(Some(head))
      receipts.push(Some(receipt))
      matched += 1
    }
    match
      @effect.issue_effect_member_receipt_from_recovered_rows(
        preview,
        member_index,
        heads,
        receipts,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => members.push(value)
      Err(_) => return Err(Checkpoint(InvalidMaterial))
    }
  }
  if matched != rows.length() {
    return Err(CustodyLost)
  }
  Ok(members)
}

///|
/// Settle only the original already committed File publication. The cold
/// continuation confirms the durable dispatches and responses, then the exact
/// stored publication Request/attempt and Results, before taking a lease.
pub fn NativeLocalEffectResumeOriginal::settle_recovered_file_effect_in_original_read(
  self : Self,
  publisher : NativeLocalPublisherBinding,
  observed_at : String,
) -> Result[NativeClientSavedRunState, NativeLocalSavedEffectPublicationIssue] {
  guard self.settlement_only &&
    !self.attempted &&
    !self.retired &&
    self.subject is Some(SavedSigningSubject(read)) &&
    physical_equal(publisher.store, read.owner.store) &&
    publisher.request == self.request &&
    publisher.current() else {
    return Err(Construction)
  }
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let service = match
    self.saved_publication_service(
      publisher,
      publisher.store,
      publisher.namespace_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.prepare_saved_publication_construction_in_original_read() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let limits = original.wire_limits
  let members = match
    publisher.with_original_journal_read((host, operations) => {
      if !physical_equal(host, self.host) {
        return Err(SelectionMismatch)
      }
      let reads = operations.reads
      host.journal
      .transaction_with_reads(
        () => {
          if !self.authority_current(publication=Some(publisher)) {
            return Err(AuthorizationDenied)
          }
          let record = match
            host.journal.retained(self.request, reads=Some(reads)) {
            Ok(Some(value)) if value.revision == self.record.revision => value
            Ok(_) => return Err(Checkpoint(StaleRevision))
            Err(issue) => return Err(issue)
          }
          host.journal.recover_file_effect_members_locked(
            record,
            original.preview,
            limits,
            reads,
          )
        },
        reads=Some(reads),
      )
      .map_err(issue => Journal(issue))
    }) {
    Ok(value) => value
    Err(issue) => return Err(Publisher(issue))
  }
  let set = match
    @publication.issue_effect_set_apply_receipt_from_members(
      original.preview,
      members,
      Array::make(members.length(), false),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Construction)
  }
  let store = publisher.store
  let definition = original.materials.run_definition
  let definition_cid = @publication.publication_contract_identity(definition)
  let scope = @host.client_request_authority_scope_cid(self.request)
  let index = match
    store.inspect_committed_publication(
      publisher.namespace_id,
      scope,
      definition_cid,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Construction)
    Err(issue) => return Err(Service(@native_publication.Store(issue)))
  }
  guard @publication.project_public_index_read(index) is Ok(projected) &&
    projected.namespace_id == publisher.namespace_id &&
    projected.authority_scope_cid == scope &&
    projected.run_definition_cid == definition_cid &&
    @publication.public_index_run_observation_cids(index)
    is Ok((receipt_cid, captured_cid)) &&
    captured_cid ==
    @publication.publication_contract_identity(original.captured) else {
    return Err(Construction)
  }
  let receipt = match
    store.read_publication_contract("run_receipt", receipt_cid) {
    Ok(value) => value
    Err(issue) => return Err(Service(@native_publication.Store(issue)))
  }
  let request = match
    store.read_publication_contract(
      "publication_request",
      projected.publication_request_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Service(@native_publication.Store(issue)))
  }
  guard @publication.project_publication_request_context(request) is Ok(context) &&
    context.namespace_id == publisher.namespace_id &&
    context.authority_scope_cid == scope &&
    context.run_definition_cid == definition_cid &&
    context.publication_policy_cid == publisher.policy_cid &&
    context.publication_target_cid == publisher.target_cid &&
    @publication.publication_request_requested_at(request) is Some(requested_at) else {
    return Err(Construction)
  }
  let bindings : Array[@publication.PublicationContract] = []
  let schemas : Array[String] = []
  for cid in projected.durable_result_binding_cids {
    match store.read_publication_contract("durable_result_binding", cid) {
      Ok(value) => {
        guard @publication.project_durable_result_binding_read(value)
          is Ok(facts) else {
          return Err(Construction)
        }
        let schema = for ordinal in 0..<original.schema_originals.length() {
          if @publication.captured_effect_dependency_body_cid(
              original.schema_originals[ordinal],
            ) ==
            facts.result_schema_cid {
            break Some(original.schema_wires[ordinal])
          }
        } nobreak {
          None
        }
        guard schema is Some(wire) else { return Err(Construction) }
        bindings.push(value)
        schemas.push(wire)
      }
      Err(issue) => return Err(Service(@native_publication.Store(issue)))
    }
  }
  let final_evidence = match
    @publication.admit_retained_effectful_final_run_evidence(
      definition,
      original.invocation,
      original.definitions,
      original.artifacts,
      original.derivations,
      original.orderings,
      original.retentions,
      original.manifest,
      original.receipt,
      original.captured,
      original.preview,
      @publication.publication_contract_json(set),
      members.map(@publication.publication_contract_json),
      @publication.publication_contract_json(receipt),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
      computation=Some(original.computation),
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        Service(
          @native_publication.Store(
            @publication_store.EffectfulPublication(issue),
          ),
        ),
      )
  }
  let authority = match
    self.host.prepare_publication_observation_authority(publisher) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let candidate = match
    @native_publication.prepare_recovered_effectful_run_state_candidate(
      service,
      {
        final_evidence,
        run_definition: definition,
        invocation: original.invocation,
        definitions: original.definitions,
        artifacts: original.artifacts,
        derivations: original.derivations,
        orderings: original.orderings,
        retentions: original.retentions,
        bindings,
        binding_schema_wires: schemas,
        manifest: original.manifest,
        receipt,
        captured_run: original.captured,
      },
      {
        namespace_id: publisher.namespace_id,
        authority_scope_cid: scope,
        publication_policy_cid: publisher.policy_cid,
        publication_target_cid: publisher.target_cid,
        requested_at,
      },
      request,
      observed_at,
      limits.max_nodes,
      16,
      1000,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(Candidate(issue)))
  }
  let observed = self.host.finalize_observed_run_state_candidate(
    publisher, authority, candidate,
  )
  let returned = candidate.release()
  let observed = match (observed, returned) {
    (Err(issue), _) => return Err(Observation(issue))
    (Ok(_), Err(issue)) => return Err(Observation(Candidate(issue)))
    (Ok(value), Ok(_)) => value
  }
  let claimed = publisher.with_original_journal_read((host, _) => {
    if !physical_equal(host, self.host) {
      return Err(SelectionMismatch)
    }
    Ok(self.claim_original_resume(30000L))
  })
  match claimed {
    Ok(Ok(Claimed(_))) =>
      self.settle_saved_publication_in_original_read(
        observed,
        members,
        @env.now().to_double(),
      )
    Ok(Ok(_)) => Err(Construction)
    Ok(Err(issue)) => Err(Original(issue))
    Err(issue) => Err(Publisher(issue))
  }
}
