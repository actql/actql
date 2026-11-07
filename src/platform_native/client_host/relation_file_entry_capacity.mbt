///|
// Original Read preparation, separate from the business bytes debited by the
// returned token. This closed non-Model/no-VM path sums all constructor products
// without assuming temporary reuse. H/R/S are the shared logical tariff units.
//
// * Business quote evaluation: H12/R2/S25 (one Native tariff, Common quote,
//   checked additions and final capacity DATA). The body of that evaluator
//   must be recensused if its constructor chain changes.
// * Canonical reserve/current frontier: H26/R20/S60. The token and new usage
//   remain Read-owned; this is not another reservation in the business Ledger.
// * Arena entry, self-marker Ref/Some and borrowed Ledger Some: H4/R11/S8.
// * Arena Ready/Pending, Result and Some: H3/R3/S3.
// * Client entry/access/source projections and inert refusals: H9/R27/S10.
//   Includes two preowned current/export scalar Errs and their entry fields.
// * Pending client failure, entry Some, Result and outer Some: H4/R7/S3.
//   This dominates the Ready return H2/R2/S2 without fabricating a grant.
// * Never-entered cancellation/current frontier: H22/R13/S59. It is retained
//   here as a distinct optional path, not charged to outer physical cleanup.
// * Exact selection snapshot: record H1/R6, canonical items collection
//   H3/R(13+3n)/S2, map function H1/R0; a present key path adds
//   canonical collection+Some H4/R(14+3k)/S3. The client entry
//   retains two additional references to this selection and immutable limits.
// * Source inventory-query evaluation uses its original Source-owned vector.
//   Converting that result to bytes adds five Some products H5/S10, and
//   composing fixed+Source adds one Some H1/S2 (192 bytes together).
// * One original-Read exchange wrapper peak H16/R25/S12 (552 bytes).
// * Conditional failed-return routing frontier H16/R12/S11/U237 (914 bytes).
//   Its actual allocation realm depends on C progress; each possible realm
//   has a distinct pre-admitted component, never a retroactive transfer.
// * Conditional outer Work outcome H9/R11/S6 (280 bytes), after a failed
//   original return. This is distinct from the access-level routing outcome.
// Caller out-slots and enclosing original-Read return carriers are separate.
pub fn native_relation_file_entry_read_capacity(
  selection : @row_file.NativeRelationFileSelection,
  limits : @row_file.NativeRelationFileLimits,
) -> @execution.ExecutionCapacity? {
  if !@row_file.native_relation_file_input_valid(selection, limits) {
    return None
  }
  let key_fields = match selection.key_path {
    None => 0L
    Some(path) => 14L + 3L * path.length().to_int64()
  }
  let key_records = if selection.key_path is Some(_) { 4L } else { 0L }
  let key_tag = if selection.key_path is Some(_) { 3L } else { 0L }
  let source = @row_file.native_relation_file_caller_preparation_evaluation_inventory(
    selection,
  )
  guard @execution.preparation_representation_cost({
      record_headers: 12L +
      26L +
      4L +
      3L +
      9L +
      4L +
      22L +
      5L +
      key_records +
      source.record_headers +
      6L +
      16L +
      16L +
      9L,
      reference_slots: 2L +
      20L +
      11L +
      3L +
      27L +
      7L +
      13L +
      2L +
      19L +
      3L * selection.items_path.length().to_int64() +
      key_fields +
      source.reference_slots +
      25L +
      12L +
      11L,
      scalar_words: 25L +
      60L +
      8L +
      3L +
      10L +
      3L +
      59L +
      2L +
      key_tag +
      source.scalar_words +
      12L +
      12L +
      11L +
      6L,
      owned_utf16_units: 237L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
/// New relation-entry outer cleanup and scope-return constructor component.
/// Existing actual relocation/report/parent-retirement inventories remain
/// owned by the original coordinator. This adds only the new exact-token
/// route and the explicitly named conditional return carriers.
pub fn native_relation_file_entry_outer_capacity() -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost({
      // New-only retirement/settlement H33/R14/S79. Business leave adds H2/S4;
      // Read leave handoff adds H6/S10. Failed Store return adds H16/R12/S11/U237.
      // Generic original-Read leave failure adds H4/R5/S4 (136 bytes).
      // Conditional Work outcome after failed return adds H9/R11/S6.
      record_headers: 33L + 2L + 6L + 16L + 4L + 9L,
      reference_slots: 14L + 12L + 5L + 11L,
      scalar_words: 79L + 4L + 10L + 11L + 4L + 6L,
      owned_utf16_units: 237L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}
