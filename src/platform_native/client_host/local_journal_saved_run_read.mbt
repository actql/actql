///|
/// Select only a retained original through this capture's current Read and
/// actual Database operations. The inner Result preserves the saved-state
/// Owner's refusal; the outer Result preserves original scope/return failure.
/// Neither result issues a Run, permission or a replacement observation.
pub fn NativeLocalJournalCapture::lookup_submitted_run_original_by_id_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  run_id : String,
) -> Result[
  Result[NativeClientOriginalRunSelection, NativeClientSavedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    Ok(
      host.lookup_submitted_run_original_by_id_with_operations(
        self.crypto,
        principal,
        connection,
        run_id,
        operations=Some(operations),
        capture=Some(self),
      ),
    )
  })
}

///|
/// Authenticate the supplied Submission in the same bounded RunRead route as
/// selection by ID. The resulting identity does not supply a saved state or
/// authorize disclosure of that state before the caller checks its RunRef.
pub fn NativeLocalJournalCapture::lookup_submitted_run_original_by_reference_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  scope : String,
  reference : NativeClientSubmissionReference,
) -> Result[
  Result[NativeClientOriginalRunSelection, NativeClientSavedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let allowed = () => {
      self.original_run_operation_allowed(
        host, material, principal, connection, scope, "read",
      )
      is Ok(true)
    }
    let reads = Some(operations.reads)
    let selected = host.journal.transaction_with_reads(
      () => {
        if !allowed() {
          return Err(AuthorizationDenied)
        }
        let selected = host.journal.run_reference_original_locked(
          host.epoch,
          reference,
          scope,
          reads~,
        )
        if !allowed() {
          return Err(AuthorizationDenied)
        }
        selected
      },
      reads~,
    )
    Ok(
      match selected {
        Ok(Some((reference, request, definition))) =>
          Ok({ reference, request, definition, scope, })
        Ok(None) => Err(Unavailable)
        Err(issue) => Err(Journal(issue))
      },
    )
  })
}

///|
/// Restore the exact saved observation under independently current RunRead.
/// Full retained-row and effect-ledger custody, ambiguity refusal and the
/// original transaction fence remain mandatory. Missing state stays missing.
pub fn NativeLocalJournalCapture::lookup_submitted_run_state_by_id_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  run_id : String,
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
    Ok(
      host.lookup_submitted_run_state_by_id_with_operations(
        self.crypto,
        principal,
        connection,
        run_id,
        now,
        operations=Some(operations),
        capture=Some(self),
      ),
    )
  })
}

///|
/// Read saved state for this already authenticated original without resolving
/// its Run ID again. State is read afresh under current RunRead and the same
/// original Database operations; the selection is neither permission nor a
/// substitute for the saved-state custody, epoch, revision and return checks.
pub fn NativeLocalJournalCapture::lookup_submitted_run_state_for_original_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  now : Double,
) -> Result[
  Result[NativeClientSavedRunState, NativeClientSavedRunStateIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    Ok(
      host.lookup_submitted_run_state_with_operations(
        self.crypto,
        principal,
        connection,
        original.reference,
        original.request,
        now,
        operations=Some(operations),
        capture=Some(self),
      ),
    )
  })
}

///|
/// Observe committed names from the same original Store. Store custody and
/// Run binding are compared by their original Owners; SQL metadata, a scope
/// CID and these names grant no payload read or delivery permission.
pub fn NativeLocalJournalCapture::lookup_original_result_names_json_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  original : NativeClientOriginalRunSelection,
  store : @publication_store.Store,
  namespace_id : String,
) -> Result[
  Result[String?, NativeClientRunJournalIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    Ok(
      host.lookup_original_result_names_json_with_operations(
        self.crypto,
        principal,
        connection,
        original,
        store,
        namespace_id,
        operations=Some(operations),
        capture=Some(self),
      ),
    )
  })
}

///|
/// Exact checkpoint selection through the same adopted Host's current Read and
/// original SQL route. The ID selects retained metadata, never a signing use,
/// approval, Run creation, scan fallback or continuation.
pub fn NativeLocalJournalCapture::lookup_original_checkpoint_by_id_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  id : String,
  now : Double,
) -> Result[
  Result[NativeLocalCheckpointSelection?, NativeClientRunJournalIssue],
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    let result = host.lookup_original_checkpoint_by_id_with_operations(
      self.crypto,
      principal,
      connection,
      id,
      now,
      operations=Some(operations),
      capture=Some(self),
    )
    match result {
      Err(issue) if issue.requires_transaction_reconciliation() =>
        Err(Journal(issue))
      _ => Ok(result)
    }
  })
}
