///|
/// One exact private Table input occurrence. This uses the bound producer and
/// common checked declaration, not a public Result port or caller schema.
struct ManagedTableInputOccurrence {
  identity : Ref[Unit]
  owner : @lower.BoundPrepared
  declarations : @results.CheckedTableInputs
  definition : @results.TableInputDefinition
}

///|
pub(all) enum ManagedTableInputOccurrenceIssue {
  ForeignOwner
  MissingInput
} derive(Eq, Debug)

///|
pub fn bind_managed_table_input_occurrence(
  owner : @lower.BoundPrepared,
  declarations : @results.CheckedTableInputs,
  name : String,
) -> Result[ManagedTableInputOccurrence, ManagedTableInputOccurrenceIssue] {
  if !physical_equal(
      @results.table_inputs_pipeline(declarations),
      @lower.pipeline(@lower.bound_preparation(owner)),
    ) {
    return Err(ForeignOwner)
  }
  guard @results.lookup_table_input(declarations, name) is Some(definition) else {
    return Err(MissingInput)
  }
  Ok({ identity: Ref(()), owner, declarations, definition, })
}

///|
pub fn managed_table_input_occurrence_owner(
  value : ManagedTableInputOccurrence,
) -> @lower.BoundPrepared {
  value.owner
}

///|
pub fn managed_table_input_occurrence_definition(
  value : ManagedTableInputOccurrence,
) -> @results.TableInputDefinition {
  value.definition
}

///|
pub fn managed_table_input_occurrence_declarations(
  value : ManagedTableInputOccurrence,
) -> @results.CheckedTableInputs {
  value.declarations
}

///|
pub fn managed_table_input_occurrence_same(
  left : ManagedTableInputOccurrence,
  right : ManagedTableInputOccurrence,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
/// Column mapping is resumable inside the existing completed export boundary.
/// No row map or cell copy is created: Table storage grants no query ordering.
/// The original completion remains the only source availability owner.
struct CompletedTableInputRelationExportPreparation {
  source : CompletedOutput
  occurrence : ManagedTableInputOccurrence
  table : CompletedTable
  schema : @schema.Schema
  view_limits : CompletedResultViewLimits
  max_rows : Int
  values : ValueLimits
  payload_wire : RowWireLimits
  logical_wire : RowWireLimits
  schema_limits : RelationSchemaIdentityLimits
  max_batch_bytes : Int
  columns : Array[Int]
  names : Array[String]
  mut field : Int
  mut column : Int
  mut mapping_work : Int
  mut stream : CompletedOutputExport?
  mut closed : Bool
}

///|
/// Start from the exact checked private projection, not public Result
/// publication. Completion, Table capability and Effect authority remain
/// separate obligations; this grants none of them.
pub fn start_completed_table_input_relation_export(
  source : CompletedOutput,
  occurrence : ManagedTableInputOccurrence,
  view_limits : CompletedResultViewLimits,
  max_rows : Int,
  values : ValueLimits,
  payload_wire : RowWireLimits,
  logical_wire : RowWireLimits,
  schema_limits : RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[CompletedTableInputRelationExportPreparation, CompletedExportIssue] {
  if view_limits.max_fields < 0 ||
    view_limits.max_mapping_work < 0 ||
    view_limits.max_workspace_entries < 0 ||
    view_limits.max_order_work < 0 {
    return Err(ResultView(InvalidLimits))
  }
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(NotCellRepresentation) }
  if !physical_equal(
      occurrence.owner,
      @lower.sequence_owner(source.completion.sequence),
    ) ||
    @results.table_input_target(occurrence.definition) != source.target {
    return Err(ResultView(ForeignOccurrence))
  }
  let selected_schema = @results.table_input_schema(occurrence.definition)
  let fields = @schema.field_count(selected_schema)
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(occurrence.owner),
      @results.table_input_target(occurrence.definition),
    )
    is Some(producer_schema) else {
    return Err(ResultView(InvalidProjection))
  }
  // The checked declaration only selects unique original fields. Selecting
  // all of them is the same schema, not a re-admitted receiving contract.
  // Preserve that exact owner for retained presence-row admission; a proper
  // subset remains its own closed projection and cannot masquerade as a full
  // producer representation on reload.
  let schema = if fields == @schema.field_count(producer_schema) {
    producer_schema
  } else {
    selected_schema
  }
  // Each selected field retains one column index and one name reference.
  // Admit both arrays, not just the logical field count, before allocation.
  if fields > view_limits.max_fields ||
    fields > view_limits.max_workspace_entries / 2 {
    return Err(ResultView(Limit))
  }
  Ok({
    source,
    occurrence,
    table,
    schema,
    view_limits,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
    columns: [],
    names: [],
    field: 0,
    column: 0,
    mapping_work: view_limits.max_mapping_work,
    stream: None,
    closed: false,
  })
}

///|
pub fn cancel_completed_table_input_relation_export(
  value : CompletedTableInputRelationExportPreparation,
) -> Bool {
  if value.closed {
    return false
  }
  value.closed = true
  value.columns.clear()
  value.columns.shrink_to_fit()
  value.names.clear()
  value.names.shrink_to_fit()
  if value.stream is Some(stream) {
    cancel_completed_output_export(stream)
  }
  true
}

///|
/// One logical unit per checked source-column comparison and one for final
/// export setup. Quantum changes cannot change projection or logical work.
pub fn advance_completed_table_input_relation_export(
  value : CompletedTableInputRelationExportPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if quantum <= 0 {
    return Err(ResultView(InvalidLimits))
  }
  if value.closed {
    return Err(Closed)
  }
  if !completed_output_available(value.source) {
    cancel_completed_table_input_relation_export(value) |> ignore
    return Err(Unavailable)
  }
  if value.stream is Some(_) {
    return Ok((true, 0))
  }
  let count = @schema.field_count(value.schema)
  let source_names = RelationRows::field_names(value.table)
  let mut spent = 0
  while spent < quantum {
    if value.mapping_work == 0 {
      return Err(ResultView(Limit))
    }
    value.mapping_work -= 1
    spent += 1
    if value.field == count {
      let rows : CompletedExportRows = {
        table: value.table,
        schema: value.schema,
        names: value.names,
        columns: Some(value.columns),
        rows: None,
      }
      let stream = match
        prepare_completed_export_rows(
          value.source,
          rows,
          value.max_rows,
          value.values,
          value.payload_wire,
          Some(value.logical_wire),
          Some(value.schema_limits),
          value.max_batch_bytes,
        ) {
        Ok(stream) => stream
        Err(issue) => return Err(issue)
      }
      value.stream = Some(stream)
      return Ok((true, spent))
    }
    if value.column >= IndexedRows::column_count(value.table) {
      return Err(ResultView(InvalidProjection))
    }
    let field = @schema.field_at(value.schema, value.field).unwrap()
    let name = @schema.reference_name(field.name)
    if source_names[value.column] == name {
      value.columns.push(value.column)
      value.names.push(name)
      value.field += 1
      value.column = 0
    } else {
      value.column += 1
    }
  }
  Ok((false, spent))
}

///|
pub fn finish_completed_table_input_relation_export_preparation(
  value : CompletedTableInputRelationExportPreparation,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if value.closed {
    return Err(Closed)
  }
  guard value.stream is Some(stream) else { return Err(NotFinished) }
  value.closed = true
  Ok(stream)
}

///|
pub fn completed_table_input_export_preparation_matches_owner(
  value : CompletedTableInputRelationExportPreparation,
  occurrence : ManagedTableInputOccurrence,
  completed : CompletedOutput,
) -> Bool {
  managed_table_input_occurrence_same(value.occurrence, occurrence) &&
  physical_equal(value.source, completed) &&
  completed_output_available(completed)
}

///|
pub fn completed_table_input_export_preparation_matches_receipt(
  value : CompletedTableInputRelationExportPreparation,
  receipt : CompletedRelationExportReceipt,
) -> Bool {
  guard value.closed &&
    value.stream is Some(stream) &&
    receipt.rows.source is Some(source) else {
    return false
  }
  completed_output_available(source) &&
  physical_equal(stream.export_identity, receipt.rows.export_identity)
}

///|
/// Retain real mapping work even after failure, cancellation or repeated reads.
/// Exported cell admission remains the completed Relation receipt's accounting.
pub fn completed_table_input_export_preparation_work(
  value : CompletedTableInputRelationExportPreparation,
) -> Int {
  value.view_limits.max_mapping_work - value.mapping_work
}
