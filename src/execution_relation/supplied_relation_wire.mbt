///|
/// Canonical private transport of an already admitted input row. Value and
/// omission semantics reuse the common row identity writer; this is neither
/// a producer completion nor a new acquisition observation.
pub fn supplied_relation_read_row_wire(
  read : SuppliedRelationRead,
  row : Int,
  limits : RowWireLimits,
) -> Result[String, RowWireIssue] {
  if !supplied_relation_read_available(read) ||
    !row_wire_valid_limits(limits) ||
    row < 0 ||
    row >= captured_row_count(read.rows) {
    return Err(InvalidLayout)
  }
  let schema = captured_schema(read.rows)
  let width = @schema.field_count(schema)
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let names = Array::makei(width, i => {
    @schema.field_reference_name(@schema.field_at(schema, i).unwrap())
  })
  let order = match
    prepare_row_wire_order(
      names,
      limits.max_columns,
      limits.max_order_work - width,
    ) {
    Ok(order) => order
    Err(issue) => return Err(issue)
  }
  let table = CapturedWireRows::{ rows: read.rows, }
  try {
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    for (name, column) in order.columns {
      if !IndexedRows::cell_present(table, row, column) {
        continue
      }
      @encode.key(writer, name)
      emit_runtime_value(IndexedRows::read_cell(table, row, column), writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn supplied_relation_read_rows_identity(
  read : SuppliedRelationRead,
  limits : RowWireLimits,
) -> Result[RowWireIdentity, RowWireIssue] {
  if !supplied_relation_read_available(read) {
    return Err(InvalidLayout)
  }
  identify_captured_rows(read.rows, limits)
}
