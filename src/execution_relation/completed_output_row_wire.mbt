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
  let names = RelationRows::field_names(table)
  let width = IndexedRows::column_count(table)
  if width > max_nodes || names.length() != width {
    return Err(Wire(InvalidLayout))
  }
  // A checked select retains an authored projection order independently of
  // the canonical output schema. The physical row transport preserves it.
  let selection = match output.target {
    @pipeline.Step(step) =>
      match @lower.sequence_step(output.completion.sequence, step) {
        Some(@lower.RowStep(kernel)) =>
          match @lower.kernel_body(kernel) {
            @lower.Select(fields) => Some(fields)
            _ => None
          }
        _ => None
      }
    _ => None
  }
  let positions : Map[String, Int] = Map([])
  if selection is Some(_) {
    for column, name in names {
      if positions.contains(name) {
        return Err(Wire(InvalidLayout))
      }
      positions[name] = column
    }
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    match selection {
      Some(fields) => {
        if fields.length() != width {
          return Err(Wire(InvalidLayout))
        }
        for field in fields {
          let name = @schema.reference_name(field.output)
          guard positions.get(name) is Some(column) else {
            return Err(Wire(InvalidLayout))
          }
          @encode.key(writer, name)
          emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
        }
      }
      None =>
        for column in 0..<width {
          @encode.key(writer, names[column])
          emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
        }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}
