///|
/// Receiver-side logical admission, before projection and independent of the
/// producer's storage. A shared buffer is not a discount on logical input.
/// Ownership and contract checks remain in prepare_sequence_with_importers.
fn[T : RelationRows] charge_completed_rows(
  source : T,
  remaining_rows : Int,
  control : ControlBudget,
  budget : ValueBudget,
) -> Bool {
  let count = IndexedRows::row_count(source)
  if count < 0 || count > remaining_rows {
    return false
  }
  let names = source.field_names()
  for row = 0; row < count; row = row + 1 {
    if !spend_control(control, 1) ||
      !retain_row(IndexedRow::{ table: source, row, }, names, budget) {
      return false
    }
  }
  true
}
