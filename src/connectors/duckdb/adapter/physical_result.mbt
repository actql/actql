///|
pub(all) struct PhysicalResultLimits {
  max_rows : Int
  max_cells : Int
  max_nodes : Int
  max_text_bytes : Int
}

///|
pub(all) enum PhysicalResultIssue {
  InvalidLimits
  MetadataLimit
  SchemaMismatch
  ShapeMismatch
  RowLimit
  CellLimit
  Terminal
  FieldType(Int, ValueIssue)
  Cell(Int, Int, ValueIssue)
}

///|
/// Physical input validation only: neither native semantics nor completion
/// evidence. The owner must retain this exact receiver across all result chunks.
struct PhysicalResult {
  schema : @schema.Schema
  mappings : Array[(Int, ValueMapping)]
  limits : PhysicalResultLimits
  mut rows : Int
  mut cells : Int
  mut nodes : Int
  mut text_bytes : Int
  mut terminal : Bool
}

///|
struct PhysicalBatch {
  owner : PhysicalResult
  rows : Int
  values : Array[@admitted.CheckedValue]
}

///|
pub fn prepare_physical_result(
  schema : @schema.Schema,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[PhysicalResult, PhysicalResultIssue] {
  if limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    max_metadata_work < 0 {
    return Err(InvalidLimits)
  }
  let count = @schema.field_count(schema)
  if count != fields.length() {
    return Err(SchemaMismatch)
  }
  if count > max_metadata_work {
    return Err(MetadataLimit)
  }
  let mut work = max_metadata_work - count
  let mappings = []
  for column in 0..<count {
    let field = @schema.field_at(schema, column).unwrap()
    let expected = @schema.reference_name(field.name)
    let mut matched = None
    for index, (name, physical) in fields {
      if work == 0 {
        return Err(MetadataLimit)
      }
      work -= 1
      for text in [expected, name] {
        match @scalar.admit_utf8_length(text, work) {
          Ok(bytes) => work -= bytes
          Err(_) => return Err(MetadataLimit)
        }
      }
      if name == expected {
        if matched is Some(_) {
          return Err(SchemaMismatch)
        }
        let mapping = match prepare_value_mapping(physical, field.contract) {
          Ok(value) => value
          Err(issue) => return Err(FieldType(column, issue))
        }
        matched = Some((index, mapping))
      }
    }
    guard matched is Some(mapping) else { return Err(SchemaMismatch) }
    mappings.push(mapping)
  }
  Ok({
    schema,
    mappings,
    limits,
    rows: 0,
    cells: 0,
    nodes: 0,
    text_bytes: 0,
    terminal: false,
  })
}

///|
/// Columns are bounded decoded transport arrays in the prepared field order.
/// A rejected chunk makes this receiving attempt terminal, even if caught.
/// Successful batches remain provisional and cannot alone issue completion.
pub fn admit_physical_chunk(
  result : PhysicalResult,
  row_count : Int,
  columns : Array[@decode.Cursor],
) -> Result[PhysicalBatch, PhysicalResultIssue] {
  if result.terminal {
    return Err(Terminal)
  }
  result.terminal = true
  let count = result.mappings.length()
  if row_count < 0 || columns.length() != count {
    return Err(ShapeMismatch)
  }
  if row_count > result.limits.max_rows - result.rows {
    return Err(RowLimit)
  }
  if count > 0 && row_count > (result.limits.max_cells - result.cells) / count {
    return Err(CellLimit)
  }
  for column in columns {
    if @decode.array_length(column) != Some(row_count) {
      return Err(ShapeMismatch)
    }
  }
  let values = []
  for row in 0..<row_count {
    for column, (source, mapping) in result.mappings {
      let payload = @decode.element_at(columns[source], row).unwrap()
      let (value, nodes, bytes) = match
        admit_physical_usage(mapping, payload, {
          max_nodes: result.limits.max_nodes - result.nodes,
          max_text_bytes: result.limits.max_text_bytes - result.text_bytes,
          max_depth: 0,
        }) {
        Ok(value) => value
        Err(issue) => return Err(Cell(result.rows + row, column, issue))
      }
      result.nodes += nodes
      result.text_bytes += bytes
      values.push(value)
    }
  }
  result.rows += row_count
  result.cells += row_count * count
  result.terminal = false
  Ok({ owner: result, rows: row_count, values, })
}

///|
pub fn physical_batch_cell(
  batch : PhysicalBatch,
  row : Int,
  column : Int,
) -> @admitted.CheckedValue? {
  let count = batch.owner.mappings.length()
  if row < 0 || row >= batch.rows || column < 0 || column >= count {
    return None
  }
  batch.values.get(row * count + column)
}

///|
pub fn physical_batch_rows(batch : PhysicalBatch) -> Int {
  batch.rows
}

///|
pub fn physical_batch_owner(batch : PhysicalBatch) -> PhysicalResult {
  batch.owner
}

///|
pub fn physical_result_schema(result : PhysicalResult) -> @schema.Schema {
  result.schema
}

///|
pub fn physical_result_usage(result : PhysicalResult) -> (Int, Int, Int, Int) {
  (result.rows, result.cells, result.nodes, result.text_bytes)
}

///|
pub fn cancel_physical_result(result : PhysicalResult) -> Unit {
  result.terminal = true
}
