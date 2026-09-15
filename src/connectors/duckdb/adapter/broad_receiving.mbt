///|
/// Full known-input scan; it does not require native predicate support.
struct BroadScan {
  owner : @lower.BoundPrepared
  input_index : Int
  schema : @schema.Schema
  sql : String
  database_schema : String
  table : String
}

///|
struct BroadTable {
  scan : BroadScan
}

///|
pub fn prepare_broad_scan(
  owner : @lower.BoundPrepared,
  input_index : Int,
  database_schema : String,
  table : String,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[BroadScan, NativeQueryIssue] {
  let prepared = @lower.bound_preparation(owner)
  guard @lower.input_id(prepared, input_index) is Some(_) &&
    @pipeline.schema_at(@lower.pipeline(prepared), @pipeline.Input(input_index))
    is Some(schema) else {
    return Err(UnsupportedShape)
  }
  let sql = match
    compile_scan_sql(schema, database_schema, table, max_columns, max_sql_bytes) {
    Ok(sql) => sql
    Err(issue) => return Err(issue)
  }
  Ok({ owner, input_index, schema, sql, database_schema, table, })
}

///|
pub fn broad_scan_sql(scan : BroadScan) -> String {
  scan.sql
}

///|
pub fn broad_scan_metadata_sql(_scan : BroadScan) -> String {
  source_table_metadata_sql()
}

///|
pub fn broad_scan_metadata_parameter(
  scan : BroadScan,
  index : Int,
) -> PhysicalParameter? {
  let value = match index {
    0 => scan.database_schema
    1 => scan.table
    _ => return None
  }
  Some({ id: "VARCHAR", decimal: None, value: ScalarText(value), })
}

///|
/// Metadata shape validation, not proof of Host permission or a live read view.
pub fn admit_broad_table(
  scan : BroadScan,
  rows : Int,
  fields : Array[(String, PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[BroadTable, SourceTableIssue] {
  validate_source_table_metadata(rows, fields, columns).map(_ => { scan, })
}

///|
pub(all) enum BroadReceivingIssue {
  InvalidState
  Values(PhysicalResultIssue)
  Retention(@execution.CaptureIssue)
}

///|
/// Provisional receiver, not observation evidence. The trusted Host verifies
/// source catalog, permission and read-view before starting this data receiver.
/// No captured input is available until every chunk is admitted and retained.
struct BroadReceiving {
  values : PhysicalResult
  input : @execution.AdmittedInput
  mut open : Bool
}

///|
pub fn prepare_broad_receiving(
  table : BroadTable,
  fields : Array[(String, PhysicalType)],
  physical : PhysicalResultLimits,
  max_metadata_work : Int,
  retention : @execution.ValueLimits,
) -> Result[BroadReceiving, BroadReceivingIssue] {
  let scan = table.scan
  let values = match
    prepare_physical_result(scan.schema, fields, physical, max_metadata_work) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  let input = match
    @execution.prepare_admitted_input(
      scan.owner,
      scan.input_index,
      physical.max_rows,
      retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  Ok({ values, input, open: true, })
}

///|
pub fn abort_broad_receiving(value : BroadReceiving) -> Unit {
  value.open = false
  cancel_physical_result(value.values)
  @execution.cancel_admitted_input(value.input) |> ignore
}

///|
pub fn accept_broad_chunk(
  receiving : BroadReceiving,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, BroadReceivingIssue] {
  if !receiving.open {
    return Err(InvalidState)
  }
  let result = accept_broad_chunk_impl(receiving, rows, columns)
  if result is Err(_) {
    abort_broad_receiving(receiving)
  }
  result
}

///|
fn accept_broad_chunk_impl(
  receiving : BroadReceiving,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, BroadReceivingIssue] {
  let batch = match admit_physical_chunk(receiving.values, rows, columns) {
    Ok(batch) => batch
    Err(issue) => return Err(Values(issue))
  }
  let width = @schema.field_count(receiving.values.schema)
  for row in 0..<batch.rows {
    // The temporary vector and owned row container are bounded by the physical
    // cell limit and retention ledger; immutable cell payloads are shared.
    let cells = Array::makei(width, col => {
      physical_batch_cell(batch, row, col).unwrap()
    })
    match @execution.append_admitted_input(receiving.input, cells) {
      Ok(_) => ()
      Err(issue) => return Err(Retention(issue))
    }
  }
  Ok(())
}

///|
/// Seal input once; the Host must still complete transport/cleanup and residual
/// execution before any acquisition capture. This is not a completed consumer.
pub fn finish_broad_receiving(
  value : BroadReceiving,
) -> Result[@execution.CapturedRows, BroadReceivingIssue] {
  if !value.open {
    return Err(InvalidState)
  }
  value.open = false
  cancel_physical_result(value.values)
  @execution.finish_admitted_input(value.input).map_err(issue => {
    Retention(issue)
  })
}
