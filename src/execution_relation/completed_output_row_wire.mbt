///|
/// Encode one already-admitted immutable Local row for a registered physical
/// representation provider. This performs no hashing and creates no logical
/// identity; it is only a bounded transport into another checked admission.
pub fn completed_output_row_wire(
  output : CompletedOutput,
  row : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, CompletedExportIssue] {
  if !completed_output_available(output) {
    return Err(Unavailable)
  }
  guard output.table is Some(table) else { return Err(NotCellRepresentation) }
  if row < 0 ||
    row >= IndexedRows::row_count(table) ||
    IndexedRows::row_width(table, row) != IndexedRows::column_count(table) {
    return Err(Wire(InvalidLayout))
  }
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(Wire(InvalidLimits))
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    let names = RelationRows::field_names(table)
    for column in 0..<IndexedRows::column_count(table) {
      @encode.key(writer, names[column])
      emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}
