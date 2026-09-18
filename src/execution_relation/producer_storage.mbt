///|
/// Read-only full retained output for an owned physical representation. This
/// handle cannot be bound as a consumer input or manufacture a completion.
struct ProducerStorage {
  output : CompletedOutput
  schema : @schema.Schema
  columns : Array[Int]
}

///|
pub fn prepare_producer_storage(
  output : CompletedOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ProducerStorage, ProducerReadIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !completed_output_available(output) {
    return Err(ProducerUnavailable)
  }
  let owner = @lower.sequence_owner(output.completion.sequence)
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      output.target,
    )
    is Some(schema) else {
    return Err(InvalidProjection)
  }
  let mut work = max_entries
  let mut bytes = max_name_bytes
  let columns = []
  for i in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
    let mut found = None
    for column in 0..<completed_column_count(output) {
      if work == 0 {
        return Err(Limit)
      }
      work -= 1
      if completed_column_name(output, column) == Some(name) {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) else { return Err(InvalidProjection) }
    columns.push(column)
  }
  Ok({ output, schema, columns, })
}

///|
pub fn producer_storage_schema(storage : ProducerStorage) -> @schema.Schema {
  storage.schema
}

///|
pub fn producer_storage_row_count(storage : ProducerStorage) -> Int {
  completed_row_count(storage.output)
}

///|
pub fn producer_storage_cell(
  storage : ProducerStorage,
  row : Int,
  column : Int,
) -> Value? {
  storage.columns
  .get(column)
  .bind(column => completed_cell(storage.output, row, column))
}

///|
pub fn producer_storage_available(storage : ProducerStorage) -> Bool {
  completed_output_available(storage.output)
}

///|
/// Installed representation-transfer access only, not a consumer permission.
pub fn producer_storage_retained_material(
  storage : ProducerStorage,
) -> RetainedOutputMaterial? {
  if producer_storage_available(storage) {
    storage.output.representation
  } else {
    None
  }
}

///|
/// Exact output supplied to storage preparation, not equality of its contents.
pub fn producer_storage_matches_output(
  storage : ProducerStorage,
  output : CompletedOutput,
) -> Bool {
  physical_equal(storage.output, output) && producer_storage_available(storage)
}

///|
fn same_completed_storage(
  left : CompletedTable,
  right : CompletedTable,
) -> Bool {
  match (left, right) {
    (RowTable(a), RowTable(b)) => physical_equal(a, b)
    (NumberTable(a), NumberTable(b)) => physical_equal(a, b)
    (AdmittedTable(a), AdmittedTable(b)) => physical_equal(a, b)
    (ColumnTable(a), ColumnTable(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// Resolve receiver columns against the exact retained producer allocation.
/// Equal values/CIDs, or a newly executed identical producer, are insufficient.
/// The returned indices are a copy; neither storage nor checked binding mutates.
pub fn producer_storage_projection(
  storage : ProducerStorage,
  receiver : ProducerRead,
  max_entries : Int,
) -> Result[Array[Int], ProducerReadIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if !producer_storage_available(storage) || !producer_read_available(receiver) {
    return Err(ProducerUnavailable)
  }
  let output = receiver.bound.output
  if output.target != storage.output.target ||
    !physical_equal(
      @lower.sequence_owner(output.completion.sequence),
      @lower.sequence_owner(storage.output.completion.sequence),
    ) ||
    !same_completed_output_storage(output, storage.output) {
    return Err(InvalidProjection)
  }
  let mut work = max_entries
  let result = []
  for source in receiver.columns {
    let mut found = None
    for i, column in storage.columns {
      if work == 0 {
        return Err(Limit)
      }
      work -= 1
      if column == source {
        found = Some(i)
        break
      }
    }
    guard found is Some(index) else { return Err(InvalidProjection) }
    result.push(index)
  }
  Ok(result)
}

///|
fn same_completed_output_storage(
  left : CompletedOutput,
  right : CompletedOutput,
) -> Bool {
  match (left.table, right.table) {
    (Some(a), Some(b)) => same_completed_storage(a, b)
    (None, None) =>
      match (left.representation, right.representation) {
        (Some(a), Some(b)) => physical_equal(a, b)
        _ => false
      }
    _ => false
  }
}
