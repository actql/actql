///|
/// Bounded metadata for one exact checked Named Result view. The retained row
/// and column maps do not copy cells or weaken the completed producer's life.
pub(all) struct CompletedResultViewLimits {
  max_fields : Int
  max_mapping_work : Int
  max_order_work : Int
  max_workspace_entries : Int
}

///|
pub(all) enum CompletedResultViewIssue {
  InvalidLimits
  Unavailable
  ForeignOccurrence
  InvalidProjection
  Limit
  Comparison(ScalarIssue)
}

///|
/// Physical coordinates for an exact completed Result occurrence. None means
/// the original identity mapping and avoids allocating a redundant index.
priv struct CompletedExportRows {
  table : CompletedTable
  schema : @schema.Schema
  names : Array[String]
  columns : Array[Int]?
  rows : Array[Int]?
}

///|
impl IndexedRows for CompletedExportRows with fn row_count(self) {
  match self.rows {
    Some(rows) => rows.length()
    None => IndexedRows::row_count(self.table)
  }
}

///|
impl IndexedRows for CompletedExportRows with fn column_count(self) {
  self.names.length()
}

///|
impl IndexedRows for CompletedExportRows with fn row_width(self, row) {
  let source = match self.rows {
    Some(rows) => rows[row]
    None => row
  }
  if IndexedRows::row_width(self.table, source) !=
    IndexedRows::column_count(self.table) {
    -1
  } else {
    IndexedRows::column_count(self)
  }
}

///|
impl IndexedRows for CompletedExportRows with fn read_cell(self, row, column) {
  let source_row = match self.rows {
    Some(rows) => rows[row]
    None => row
  }
  let source_column = match self.columns {
    Some(columns) => columns[column]
    None => column
  }
  IndexedRows::read_cell(self.table, source_row, source_column)
}

///|
fn completed_output_export_rows(
  source : CompletedOutput,
) -> CompletedExportRows {
  let owner = @lower.sequence_owner(source.completion.sequence)
  {
    table: source.table.unwrap(),
    schema: @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      source.target,
    ).unwrap(),
    names: RelationRows::field_names(source.table.unwrap()).copy(),
    columns: None,
    rows: None,
  }
}

///|
fn spend_result_mapping(work : Ref[Int], amount : Int) -> Bool {
  if amount < 0 || amount > work.val {
    false
  } else {
    work.val -= amount
    true
  }
}

///|
fn result_source_column(
  table : CompletedTable,
  name : @schema.FieldName,
  work : Ref[Int],
) -> Result[Int, CompletedResultViewIssue] {
  let spelling = @schema.reference_name(name)
  for column = 0; column < IndexedRows::column_count(table); column = column + 1 {
    if !spend_result_mapping(work, 1) {
      return Err(Limit)
    }
    if RelationRows::field_names(table)[column] == spelling {
      return Ok(column)
    }
  }
  Err(InvalidProjection)
}

///|
fn completed_result_export_rows(
  source : CompletedOutput,
  occurrence : ManagedResultOccurrence,
  limits : CompletedResultViewLimits,
) -> Result[CompletedExportRows, CompletedResultViewIssue] {
  if limits.max_fields < 0 ||
    limits.max_mapping_work < 0 ||
    limits.max_order_work < 0 ||
    limits.max_workspace_entries < 0 {
    return Err(InvalidLimits)
  }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(Unavailable) }
  let owner = managed_result_occurrence_owner(occurrence)
  let actual_owner = @lower.sequence_owner(source.completion.sequence)
  let port = managed_result_occurrence_port(occurrence)
  if !physical_equal(owner, actual_owner) ||
    @results.port_target(port) != source.target {
    return Err(ForeignOccurrence)
  }
  let schema = @results.port_schema(port)
  let count = @schema.field_count(schema)
  if count > limits.max_fields {
    return Err(Limit)
  }
  let work = Ref(limits.max_mapping_work)
  let columns : Array[Int] = []
  let names : Array[String] = []
  for index = 0; index < count; index = index + 1 {
    if !spend_result_mapping(work, @results.port_projection_count(port)) {
      return Err(Limit)
    }
    let output = @schema.field_at(schema, index).unwrap().name
    guard @results.port_projection_input_at(port, index) is Some(input) else {
      return Err(InvalidProjection)
    }
    if !spend_result_mapping(work, 1) {
      return Err(Limit)
    }
    let column = match result_source_column(table, input, work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    names.push(@schema.reference_name(output))
    columns.push(column)
  }
  let terms : Array[ColumnOrder] = []
  for index = 0; index < @results.port_order_term_count(port); index = index + 1 {
    if !spend_result_mapping(work, 1) {
      return Err(Limit)
    }
    let term = @results.port_order_term_at(port, index).unwrap()
    let column = match result_source_column(table, term.field, work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    terms.push({
      column,
      descending: term.direction == @order.Desc,
      nulls_first: term.nulls == @order.First,
    })
  }
  let order_work : ControlBudget = {
    remaining: limits.max_order_work,
    max_frames: 0,
  }
  let workspace : RowWorkspace = {
    limit: limits.max_workspace_entries,
    live: 0,
    peak: 0,
  }
  let rows = match stable_order_indices(table, terms, order_work, workspace) {
    Ok(value) => value
    Err(InvalidInput) => return Err(InvalidProjection)
    Err(Limit) => return Err(Limit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  Ok({ table, schema, names, columns: Some(columns), rows: Some(rows), })
}

///|
fn completed_export_field_names(rows : CompletedExportRows) -> Array[String] {
  rows.names.copy()
}
