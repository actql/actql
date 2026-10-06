///|
/// Borrow one exact Relation cell, leaving its potentially long contract
/// recheck to the caller's existing bounded Session. No checked field is
/// issued here; only the completed common cursor may authorize its use.
fn relation_cell_recheck(
  read : @execution.ProducerRead,
  row : Int,
  column : Int,
  limits : @value.Limits,
) -> (@schema.FieldName, @value.RecheckCursor)? {
  guard @schema.field_at(@execution.producer_read_schema(read), column)
    is Some(field) &&
    @execution.producer_read_cell(read, row, column) is Some(cell) else {
    return None
  }
  let cursor = if cell is @execution.Text(text) {
    @value.start_recheck_runtime_text(text, field.contract, limits)
  } else {
    let raw = match cell {
      @execution.Null => Some(@value.null_value())
      @execution.Boolean(boolean) => Some(@value.boolean_value(boolean))
      @execution.Number(number) => @value.number_value(number)
      @execution.Captured(raw) => Some(raw)
      @execution.Text(_) => None
    }
    guard raw is Some(raw) else { return None }
    @value.start_recheck_runtime_value(raw, field.contract, limits)
  }
  cursor.map(cursor => (field.name, cursor))
}
