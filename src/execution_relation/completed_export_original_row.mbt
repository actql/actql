///|
/// One row of the same immutable Result export. The canonical projection is
/// retained for the existing Preview path; typed cells remain with the exact
/// export view, including its original column projection and stable order.
/// This is neither a new captured Result nor an Effect dispatch permit.
struct CompletedOutputExportOriginalRow {
  mut stream : CompletedOutputExport?
  index : Int
  mut canonical : @identity.CanonicalValue?
}

///|
pub(all) enum CompletedExportOriginalRowIssue {
  InvalidLimits
  Unavailable
  FieldLimit
  WorkLimit
  MissingField
  InvalidValue
} derive(Eq, Debug)

///|
fn completed_export_original_row_retained(
  row : CompletedOutputExportOriginalRow,
) -> Bool {
  guard row.stream is Some(stream) else { return false }
  row.canonical is Some(_) &&
  row.index >= 0 &&
  stream.source is Some(_) &&
  !stream.reading &&
  stream.pending_row is None &&
  row.index < stream.row &&
  row.index == stream.row - 1
}

///|
/// Recheck the same export after its physical availability callback. A
/// callback that advances, closes or cancels this stream cannot leave the
/// previous row usable merely by returning true.
pub fn completed_output_export_original_row_available(
  row : CompletedOutputExportOriginalRow,
) -> Bool {
  if !completed_export_original_row_retained(row) {
    return false
  }
  guard row.stream is Some(stream) && stream.source is Some(source) else {
    return false
  }
  completed_output_available(source) &&
  completed_export_original_row_retained(row) &&
  row.stream.map(current => physical_equal(current, stream)) == Some(true) &&
  stream.source.map(current => physical_equal(current, source)) == Some(true)
}

///|
/// Traverse and hash exactly the existing row bytes once. Only this function
/// can issue the private row token; caller-supplied JSON cannot issue one.
pub fn next_completed_output_export_original_row(
  stream : CompletedOutputExport,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[(String, CompletedOutputExportOriginalRow)?, CompletedExportIssue] {
  match
    next_completed_output_export_canonical_row(
      stream, max_nodes, max_depth, max_utf16_units,
    ) {
    Err(issue) => Err(issue)
    Ok(None) => Ok(None)
    Ok(Some((index, wire, canonical))) => {
      let row = { stream: Some(stream), index, canonical: Some(canonical), }
      if completed_output_export_original_row_available(row) {
        Ok(Some((wire, row)))
      } else {
        cancel_completed_output_export(stream)
        Err(Unavailable)
      }
    }
  }
}

///|
pub fn completed_output_export_original_row_index(
  row : CompletedOutputExportOriginalRow,
) -> Int {
  row.index
}

///|
pub fn completed_output_export_original_row_canonical(
  row : CompletedOutputExportOriginalRow,
) -> @identity.CanonicalValue? {
  if completed_output_export_original_row_available(row) {
    row.canonical
  } else {
    None
  }
}

///|
/// An equal completion or separately prepared export is not the original
/// traversal selected by a Captured/Mapping owner.
pub fn completed_result_export_preparation_matches_original_row(
  preparation : CompletedResultRelationExportPreparation,
  row : CompletedOutputExportOriginalRow,
) -> Bool {
  completed_result_export_preparation_retains_original_row(preparation, row) &&
  completed_output_export_original_row_available(row) &&
  completed_result_export_preparation_retains_original_row(preparation, row)
}

///|
/// Callback-free final fence after the physical and derived availability
/// callbacks. Retention alone never supplies availability or authorization.
pub fn completed_result_export_preparation_retains_original_row(
  preparation : CompletedResultRelationExportPreparation,
  row : CompletedOutputExportOriginalRow,
) -> Bool {
  guard row.stream is Some(original) else { return false }
  preparation.closed &&
  preparation.stream.map(stream => physical_equal(stream, original)) ==
  Some(true) &&
  completed_export_original_row_retained(row)
}

///|
/// Recheck an immutable runtime cell under its original Result field contract,
/// without serializing or re-admitting its canonical JSON projection. In
/// particular, a Text cell never becomes Date, Decimal or Signed64 by spelling.
pub fn completed_output_export_original_row_checked_field_usage(
  row : CompletedOutputExportOriginalRow,
  name : String,
  max_fields : Int,
  max_work : Int,
  limits : @admitted.Limits,
) -> Result[
  (@admitted.CheckedValue, Int, Int, Int),
  CompletedExportOriginalRowIssue,
] {
  if max_fields < 0 ||
    max_work < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !completed_output_export_original_row_available(row) {
    return Err(Unavailable)
  }
  guard row.stream is Some(stream) else { return Err(Unavailable) }
  let rows = stream.rows
  let width = rows.names.length()
  if width > max_fields {
    return Err(FieldLimit)
  }
  // Reserve both metadata scans, then charge every compared name before
  // lookup. Repeated calls do not acquire or widen the caller's phase budget.
  if width > max_work || width > max_work - width {
    return Err(WorkLimit)
  }
  let mut remaining = max_work - width - width
  let mut column : Int? = None
  for index, candidate in rows.names {
    if candidate.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= candidate.length()
    if name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= name.length()
    if candidate == name {
      column = Some(index)
    }
  }
  guard column is Some(column) else { return Err(MissingField) }
  let comparisons = @schema.field_count(rows.schema)
  let name_bytes = @schema.field_reference_name_bytes(rows.schema)
  if comparisons > remaining {
    return Err(WorkLimit)
  }
  remaining -= comparisons
  if name.length() > remaining || name_bytes > remaining - name.length() {
    return Err(WorkLimit)
  }
  remaining -= name.length() + name_bytes
  if comparisons > 0 &&
    (
      name.length() > remaining / comparisons ||
      name_bytes > remaining / comparisons - name.length()
    ) {
    return Err(WorkLimit)
  }
  remaining -= comparisons * (name.length() + name_bytes)
  guard @schema.lookup_reference(rows.schema, name) is Some(field) else {
    return Err(MissingField)
  }
  if !IndexedRows::cell_present(rows, row.index, column) {
    return Err(MissingField)
  }
  // Both independent value ceilings must fit before rechecking. The returned
  // usage lets the enclosing Mapping share this same finite budget across
  // all fields rather than resetting it for each cell.
  if limits.max_nodes > remaining ||
    limits.max_text_bytes > remaining - limits.max_nodes {
    return Err(WorkLimit)
  }
  let value = match IndexedRows::read_cell(rows, row.index, column) {
    Null => Some(@admitted.null_value())
    Number(number) => @admitted.number_value(number)
    Boolean(boolean) => Some(@admitted.boolean_value(boolean))
    Text(text) => @admitted.text_value(text, limits.max_text_bytes)
    Captured(value) => Some(value)
  }
  guard value is Some(value) else { return Err(InvalidValue) }
  guard @admitted.recheck_runtime_value_usage(value, field.contract, limits)
    is Some((checked, nodes, text)) else {
    return Err(InvalidValue)
  }
  if !completed_export_original_row_retained(row) {
    return Err(Unavailable)
  }
  Ok((checked, max_work - remaining + nodes + text, nodes, text))
}

///|
/// The convenience projection retains exactly the same checks and budget as
/// the measured reader; it introduces no separate value admission path.
pub fn completed_output_export_original_row_checked_field(
  row : CompletedOutputExportOriginalRow,
  name : String,
  max_fields : Int,
  max_work : Int,
  limits : @admitted.Limits,
) -> Result[@admitted.CheckedValue, CompletedExportOriginalRowIssue] {
  completed_output_export_original_row_checked_field_usage(
    row, name, max_fields, max_work, limits,
  ).map(result => result.0)
}

///|
/// Drop this token's own references. Escaped values and the enclosing export
/// retain their independent lifetimes; this is no Store or physical ACK.
pub fn retire_completed_output_export_original_row(
  row : CompletedOutputExportOriginalRow,
) -> Unit {
  row.stream = None
  row.canonical = None
}
