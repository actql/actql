///|
fn NativeClientEffectResponseRecord::row_receipt(
  self : Self,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  dispatch_cid : String,
  outcome_wire : String,
  max_response_bytes : Int,
  bounds : @checkpoint.WireLimits,
) -> Result[
  @publication.PublicationContract,
  @publication.EffectRowOutcomeIssue,
] {
  match self.protocol {
    HttpOriginal(credential_use, status) =>
      @publication.issue_effect_row_outcome_receipt(
        preview,
        member_index,
        row_index,
        dispatch_cid,
        credential_use,
        self.body,
        status,
        outcome_wire,
        max_response_bytes,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      )
    FileOriginal(response) => {
      if response.typed_outcome_wire != outcome_wire {
        return Err(ForeignResponse)
      }
      @publication.issue_effect_row_outcome_receipt_from_file(
        preview,
        member_index,
        row_index,
        dispatch_cid,
        response,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      )
    }
  }
}

///|
fn NativeClientEffectResponseRecord::terminal_entry(
  self : Self,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  scope : @scope.LogicalRequestScope,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  canonical_request_cid : String,
  head : @effect.EffectLedgerEntry,
  history : Array[@effect.EffectLedgerEntry],
  dispatch_cid : String,
  receipt_wire : String,
  max_response_bytes : Int,
  bounds : @checkpoint.WireLimits,
) -> Result[@effect.EffectLedgerEntry, @effect.EffectRowReceiptCommitIssue] {
  match self.protocol {
    HttpOriginal(credential_use, status) =>
      @effect.issue_effect_row_receipt_terminal_entry(
        preview,
        member_index,
        row_index,
        scope,
        locator,
        key,
        canonical_request_cid,
        head,
        history,
        dispatch_cid,
        credential_use,
        self.body,
        status,
        receipt_wire,
        max_response_bytes,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      )
    FileOriginal(response) =>
      @effect.issue_effect_row_receipt_terminal_entry_from_file(
        preview,
        member_index,
        row_index,
        scope,
        locator,
        key,
        canonical_request_cid,
        head,
        history,
        dispatch_cid,
        response,
        receipt_wire,
        bounds.max_wire_bytes,
        bounds.max_nodes,
        bounds.max_depth,
      )
  }
}

///|
/// Retain only the SAME actual file owner's ACK and bytes under this original
/// dispatch. The file mutation and this Journal transaction are not atomic.
/// A lost/uncertain append preserves the original ACK and never permits IO.
/// Current evidence-read authority, not renewed approval, governs settlement.
pub fn NativeClientRunJournal::record_effect_file_response(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  operation : @publication.EffectFileOperation,
  ack : @row_file.NativeRelationFileReplacementAck,
  outcome_wire : String,
  current : () -> Bool,
  max_response_bytes : Int,
) -> Result[Unit, NativeClientRunJournalIssue] {
  self.record_effect_file_response_with_operations(
    dispatch,
    preview,
    member_index,
    row_index,
    locator,
    key,
    operation,
    ack,
    outcome_wire,
    current,
    max_response_bytes,
    None,
  )
}

///|
fn NativeClientRunJournal::record_effect_file_response_with_operations(
  self : NativeClientRunJournal,
  dispatch : NativeClientEffectDispatchClaim,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  operation : @publication.EffectFileOperation,
  ack : @row_file.NativeRelationFileReplacementAck,
  outcome_wire : String,
  current : () -> Bool,
  max_response_bytes : Int,
  operations : NativeClientJournalOperationAccess?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if operations is Some(original) &&
    !physical_equal(self.database, original.reads.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(original => original.reads)

  if !physical_equal(self, dispatch.journal) || !current() {
    return Err(AuthorizationDenied)
  }
  if max_response_bytes < 1 ||
    max_response_bytes > native_client_effect_storage_profile.response_bytes {
    return Err(CapacityExceeded)
  }
  if ack.is_insert() {
    return Err(Checkpoint(InvalidMaterial))
  }
  let limits = native_client_effect_storage_profile.receipt
  // The actual file caller already checked the same original Account tuple
  // before dispatch/IO. Context is its binding, not a newly issued grant.
  let expected = match
    @publication.prepare_effect_file_operation(
      preview,
      member_index,
      row_index,
      operation.installation_cid,
      operation.target_cid,
      operation.canonical_request_cid,
      dispatch.dispatching.cid,
      operation.authorization_context_cid,
      operation.resolution_cid,
      operation.target_version_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(Checkpoint(InvalidMaterial))
  }
  let acknowledged_intent = if ack.is_delete() {
    None
  } else {
    Some(ack.changes_wire())
  }
  if operation.deleting != expected.deleting ||
    operation.effect_preview_cid != expected.effect_preview_cid ||
    operation.member_preview_cid != expected.member_preview_cid ||
    operation.row_preview_cid != expected.row_preview_cid ||
    operation.dispatch_entry_cid != expected.dispatch_entry_cid ||
    ack.is_delete() != expected.deleting ||
    ack.expected_version() != operation.target_version_cid ||
    @publication.effect_preview_ordered_row_intended_value_wire(
      preview, member_index, row_index,
    ) !=
    acknowledged_intent {
    return Err(Checkpoint(InvalidMaterial))
  }
  let selector = try {
    let writer = @encode.writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.string_value(writer, ack.identity())
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let selected = ack.selection()
  let target_matches = match
    @publication.effect_file_target_cid(
      operation.installation_cid,
      selected.directory,
      selected.name,
      selected.resource,
      selector,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(cid) => cid == operation.target_cid
    Err(_) => false
  }
  if @publication.effect_preview_ordered_row_correlation_wire(
      preview, member_index, row_index,
    ) !=
    Some(selector) ||
    !target_matches {
    return Err(Checkpoint(InvalidMaterial))
  }
  let body = ack.replacement()
  let generation = ack.generation()
  let evidence = match
    @publication.admit_effect_file_replacement_evidence(
      body,
      generation.device.to_string(),
      generation.inode.to_string(),
      generation.size,
      max_response_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(Checkpoint(InvalidMaterial))
  }
  let response = match
    @publication.prepare_effect_file_operation_receipt(
      operation,
      evidence,
      outcome_wire,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Checkpoint(InvalidMaterial))
  }
  if native_acceptance_enabled() {
    native_acceptance_identity(
      10,
      row_index,
      @publication.effect_file_operation_receipt_cid(response),
    )
  }
  let metadata = @utf8.encode(
    @publication.effect_file_operation_receipt_wire(response),
  )
  let stored : NativeClientEffectResponseRecord = {
    metadata,
    body,
    protocol: FileOriginal(response),
  }
  self.transaction_with_reads(
    () => {
      let record = match self.require_effect_dispatch_locked(dispatch, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      // Semantic Preview identity alone intentionally excludes the Run. Reuse
      // the original receipt binding before even reading/inserting the immutable
      // pair: nominal Run, ordered row, locator, key and dispatch all stay exact.
      match
        require_client_effect_receipt_binding(
          record,
          dispatch,
          preview,
          member_index,
          row_index,
          locator,
          key,
          operation.canonical_request_cid,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match
        require_client_file_response_binding(
          record,
          dispatch.dispatching,
          stored,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let cid = dispatch.dispatching.cid
      match read_client_effect_response_record(self.database, cid, reads~) {
        Ok(Some(prior)) if prior.protocol is FileOriginal(_) &&
          prior.metadata == metadata &&
          prior.body == body => return Ok(())
        Ok(Some(_)) => return Err(Checkpoint(InvalidMaterial))
        Err(issue) => return Err(issue)
        Ok(None) => ()
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      let key = @host.client_request_scope_cid(record.request)
      let prior = match
        read_client_journal_value(
          self.database,
          "client_effect_custody",
          key,
          reads,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
      let before = match self.read_run_before_save(record, reads) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      for
        (table, bytes) in [
          ("client_effect_response_meta", metadata),
          ("client_effect_response_bytes", body),
        ] {
        match
          insert_client_journal_value(
            self.database,
            table,
            cid,
            bytes,
            operations,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      let (witness, _) = match
        effect_ledger_custody_with_responses(self.database, record, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        compare_exchange_client_journal_value(
          self.database,
          "client_effect_custody",
          key,
          prior.revision,
          witness,
          operations,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
      self.save_observed_run(record, before, operations).map(_ => ())
    },
    reads~,
  )
}
