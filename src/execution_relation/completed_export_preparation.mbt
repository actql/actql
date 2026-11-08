///|
/// Private serialization preparation. This owner borrows an immutable completed
/// source, reserves metadata capacity, then copies names and zero summaries one
/// column at a time. It cannot create a completion or retention receipt.
struct CompletedOutputExportPreparation {
  mut source : CompletedOutput?
  mut rows : CompletedExportRows?
  order_cursor : RowWireOrderPreparation
  workspace : RowWorkspace
  budget : ValueBudget
  wire : RowWireLimits
  logical_wire : RowWireLimits?
  schema_limits : RelationSchemaIdentityLimits?
  mut schema_cursor : RelationSchemaIdentityPreparation?
  mut schema_identity : RelationSchemaIdentity?
  max_batch_bytes : Int
  mut order : RowWireOrder?
  mut names : Array[String]
  mut column_rows : Array[Int]
  mut column_bytes : Array[Int]
  mut column_nodes : Array[Int]
  mut column_max_value_bytes : Array[Int]
  mut column_null_rows : Array[Int]
  mut column_admitted_depths : Array[Int]
  mut column : Int
  mut phase : Int
  mut stream : CompletedOutputExport?
  mut closed : Bool
  mut advancing : Bool
  mut poll_work : Int
}

///|
pub fn completed_export_preparation_workspace_slots(max_columns : Int) -> Int? {
  if max_columns < 0 {
    None
  } else {
    Some(Int64::min(2147483647L, 16L + 8L * max_columns.to_int64()).to_int())
  }
}

///|
pub fn start_completed_output_export(
  source : CompletedOutput,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
  max_workspace_entries : Int,
) -> Result[CompletedOutputExportPreparation, CompletedExportIssue] {
  if !completed_output_available(source) {
    return Err(Unavailable)
  }
  guard source.table is Some(table) else { return Err(NotCellRepresentation) }
  guard admitted_relation_output_target(
    @lower.sequence_owner(source.completion.sequence),
    source.target,
  ) else {
    return Err(InvalidTarget)
  }
  let rows : CompletedExportRows = {
    table,
    schema: completed_output_relation_schema(source),
    // Checked completed table metadata is immutable. Own its independent name
    // array incrementally before exposing the export stream.
    names: RelationRows::field_names(table),
    columns: None,
    rows: None,
  }
  start_completed_export_rows_metadata(
    source,
    rows,
    max_rows,
    values,
    wire,
    None,
    None,
    max_batch_bytes,
    max_workspace_entries,
  )
}

///|
fn start_completed_export_rows_metadata(
  source : CompletedOutput,
  rows : CompletedExportRows,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  logical_wire : RowWireLimits?,
  schema_limits : RelationSchemaIdentityLimits?,
  max_batch_bytes : Int,
  max_workspace_entries : Int,
) -> Result[CompletedOutputExportPreparation, CompletedExportIssue] {
  if max_rows < 0 || IndexedRows::row_count(rows) > max_rows {
    return Err(Admission(CaptureLimit))
  }
  if !row_wire_valid_limits(wire) ||
    (logical_wire is Some(limits) && !row_wire_valid_limits(limits)) ||
    max_batch_bytes < 1 {
    return Err(Wire(InvalidLimits))
  }
  let budget = match value_budget(values) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let order_cursor = match
    start_row_wire_order(rows.names, wire.max_columns, wire.max_order_work) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  if max_workspace_entries < 0 {
    cancel_row_wire_order(order_cursor) |> ignore
    return Err(Admission(InvalidCaptureLimits))
  }
  let workspace = row_workspace(max_workspace_entries)
  // Six summary arrays, a copied name array and canonical column entries.
  // Reserve the order entries before its incremental allocation begins.
  if !reserve_slots(workspace, 16) ||
    !reserve_slots(workspace, rows.names.length()) {
    cancel_row_wire_order(order_cursor) |> ignore
    return Err(Admission(CaptureLimit))
  }
  Ok({
    source: Some(source),
    rows: Some(rows),
    order_cursor,
    workspace,
    budget,
    wire,
    logical_wire,
    schema_limits,
    schema_cursor: None,
    schema_identity: None,
    max_batch_bytes,
    order: None,
    names: [],
    column_rows: [],
    column_bytes: [],
    column_nodes: [],
    column_max_value_bytes: [],
    column_null_rows: [],
    column_admitted_depths: [],
    column: 0,
    phase: 0,
    stream: None,
    closed: false,
    advancing: false,
    poll_work: 0,
  })
}

///|
pub fn cancel_completed_output_export_preparation(
  value : CompletedOutputExportPreparation,
) -> Bool {
  if value.closed {
    return false
  }
  value.closed = true
  value.source = None
  value.rows = None
  if value.schema_cursor is Some(cursor) {
    cancel_relation_schema_identity(cursor) |> ignore
  }
  value.schema_cursor = None
  value.schema_identity = None
  cancel_row_wire_order(value.order_cursor) |> ignore
  value.order = None
  value.names = []
  value.column_rows = []
  value.column_bytes = []
  value.column_nodes = []
  value.column_max_value_bytes = []
  value.column_null_rows = []
  value.column_admitted_depths = []
  if value.stream is Some(stream) {
    cancel_completed_output_export(stream)
  }
  value.stream = None
  release_slots(value.workspace, value.workspace.live)
  true
}

///|
fn complete_export_metadata(
  value : CompletedOutputExportPreparation,
  source : CompletedOutput,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  let rows = value.rows.unwrap()
  let schema_identity = value.schema_identity
  if value.logical_wire is Some(limits) &&
    (
      limits.max_columns < value.wire.max_columns ||
      limits.max_order_work < value.wire.max_order_work
    ) {
    return Err(Wire(OrderLimit))
  }
  try {
    let writer = @encode.buffered_hashing_writer(
      value.wire.max_bytes,
      value.wire.max_nodes,
      value.wire.max_depth,
      value.max_batch_bytes,
    )
    @encode.begin_array(writer)
    let logical_writer = value.logical_wire.map(limits => {
      let writer = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      @encode.begin_object(writer)
      @encode.key(writer, "sort")
      @encode.string_value(writer, "relation")
      @encode.key(writer, "value")
      @encode.begin_array(writer)
      writer
    })
    Ok({
      export_identity: Ref(()),
      source: Some(source),
      rows: { ..rows, names: value.names, },
      order: value.order.unwrap(),
      schema: schema_identity,
      writer,
      logical_writer,
      budget: value.budget,
      column_rows: value.column_rows,
      column_bytes: value.column_bytes,
      column_nodes: value.column_nodes,
      column_max_value_bytes: value.column_max_value_bytes,
      column_null_rows: value.column_null_rows,
      column_admitted_depths: value.column_admitted_depths,
      measurement_max_bytes: value.wire.max_bytes,
      measurement_max_nodes: value.wire.max_nodes,
      measurement_max_depth: value.wire.max_depth,
      row: 0,
      reading: false,
      poll_steps: 0,
      pending_row: None,
      references: if managed_schema_reference_free(
          rows.schema,
          value.wire.max_nodes,
        ) ==
        Some(true) {
        None
      } else {
        match prepare_completed_export_references(value.budget.limits) {
          Ok(references) => Some(references)
          Err(issue) => return Err(issue)
        }
      },
    })
  } catch {
    issue => Err(Wire(Encoding(issue)))
  }
}

///|
pub fn advance_completed_output_export_preparation(
  value : CompletedOutputExportPreparation,
  quantum : Int,
) -> Result[(Bool, Int), CompletedExportIssue] {
  advance_completed_export_metadata_owned(value, quantum, None)
}

///|
// Only the same latched identity scan passes its just-observed original
// Source. Metadata transitions invoke no external callbacks, so internal
// helpers need not repeat the parent's same current observation per frame.
fn advance_completed_export_metadata_owned(
  value : CompletedOutputExportPreparation,
  quantum : Int,
  observed_source : CompletedOutput?,
) -> Result[(Bool, Int), CompletedExportIssue] {
  if value.closed || value.advancing || quantum <= 0 {
    return Err(Closed)
  }
  value.poll_work = 0
  value.advancing = true
  let result = (fn() -> Result[(Bool, Int), CompletedExportIssue] {
    guard value.source is Some(source) else { return Err(Closed) }
    let available = match observed_source {
      Some(original) => physical_equal(source, original)
      None => completed_output_available(source)
    }
    if !available {
      return Err(Unavailable)
    }
    if value.closed {
      return Err(Closed)
    }
    let rows = value.rows.unwrap()
    if value.stream is Some(_) {
      return Ok((true, 0))
    }
    let mut steps = 0
    while steps < quantum {
      if value.closed {
        return Err(Closed)
      }
      if value.phase == 0 {
        let (done, used) = match
          advance_row_wire_order(value.order_cursor, quantum - steps) {
          Ok(value) => value
          Err(issue) => {
            value.poll_work = steps + value.order_cursor.poll_work
            return Err(Wire(issue))
          }
        }
        steps += used
        value.poll_work = steps
        if done {
          value.order = Some(finish_row_wire_order(value.order_cursor).unwrap())
          value.phase = 1
        }
      } else if value.phase == 1 {
        steps += 1
        value.poll_work = steps
        if value.column == rows.names.length() {
          value.phase = 2
        } else {
          if !reserve_slots(value.workspace, 7) {
            return Err(Admission(CaptureLimit))
          }
          value.names.push(rows.names[value.column])
          value.column_rows.push(0)
          value.column_bytes.push(0)
          value.column_nodes.push(0)
          value.column_max_value_bytes.push(0)
          value.column_null_rows.push(0)
          value.column_admitted_depths.push(0)
          value.column += 1
        }
      } else if value.phase == 2 && value.schema_limits is Some(limits) {
        steps += 1
        value.poll_work = steps
        value.schema_cursor = Some(
          match start_relation_schema_identity(rows.schema, limits) {
            Ok(cursor) => cursor
            Err(issue) => return Err(Schema(issue))
          },
        )
        value.phase = 3
      } else if value.phase == 3 {
        steps += 1
        value.poll_work = steps
        let cursor = value.schema_cursor.unwrap()
        let (done, _) = match advance_relation_schema_identity(cursor, 1) {
          Ok(progress) => progress
          Err(issue) => return Err(Schema(issue))
        }
        if done {
          value.schema_identity = Some(
            finish_relation_schema_identity(cursor).unwrap(),
          )
          value.schema_cursor = None
          value.phase = 4
        }
      } else {
        steps += 1
        value.poll_work = steps
        value.stream = Some(
          match complete_export_metadata(value, source) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          },
        )
        return Ok((true, steps))
      }
    }
    Ok((false, steps))
  })()
  value.advancing = false
  if result is Err(_) {
    cancel_completed_output_export_preparation(value) |> ignore
  }
  result
}

///|
pub fn finish_completed_output_export_preparation(
  value : CompletedOutputExportPreparation,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  finish_completed_export_metadata_owned(value, None)
}

///|
// Immediate private transfer in that same synchronous scan observation.
fn finish_completed_export_metadata_owned(
  value : CompletedOutputExportPreparation,
  observed_source : CompletedOutput?,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  if value.closed || value.advancing {
    return Err(Closed)
  }
  guard value.stream is Some(stream) else { return Err(NotFinished) }
  value.advancing = true
  let available = match (value.source, observed_source) {
    (Some(source), Some(original)) => physical_equal(source, original)
    (Some(source), None) => completed_output_available(source)
    _ => false
  }
  value.advancing = false
  if value.closed {
    return Err(Closed)
  }
  if !available {
    cancel_completed_output_export_preparation(value) |> ignore
    return Err(Unavailable)
  }
  // Release private custody, not the transferred arrays now owned by stream.
  value.stream = None
  value.source = None
  value.rows = None
  value.schema_cursor = None
  value.schema_identity = None
  value.order = None
  value.names = []
  value.column_rows = []
  value.column_bytes = []
  value.column_nodes = []
  value.column_max_value_bytes = []
  value.column_null_rows = []
  value.column_admitted_depths = []
  release_slots(value.workspace, value.workspace.live)
  value.closed = true
  Ok(stream)
}

///|
fn drain_completed_export_preparation(
  value : CompletedOutputExportPreparation,
) -> Result[CompletedOutputExport, CompletedExportIssue] {
  while value.stream is None {
    match advance_completed_output_export_preparation(value, 64) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_completed_output_export_preparation(value)
}
