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
