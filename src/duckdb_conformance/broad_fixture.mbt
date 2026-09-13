///|
struct BroadFixture {
  scan : @duckdb.BroadScan
  retention_nodes : Int
  mut table : @duckdb.BroadTable?
  mut receiver : @duckdb.BroadReceiving?
  mut captured : @execution.CapturedRows?
}

///|
#export_name("broadCreate")
pub fn broad_create(retention_nodes : Int) -> BroadFixture {
  // Reuse this fixture's public checked owner, not a native execution result.
  let owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(@duckdb.native_receiving_scan(create())),
  )
  let scan = @duckdb.prepare_broad_scan(owner, 0, "main", "records", 10, 10000).unwrap()
  { scan, retention_nodes, table: None, receiver: None, captured: None, }
}

///|
#export_name("broadSql")
pub fn broad_sql(value : BroadFixture, metadata : Bool) -> String {
  if metadata {
    @duckdb.broad_scan_metadata_sql(value.scan)
  } else {
    @duckdb.broad_scan_sql(value.scan)
  }
}

///|
#export_name("broadParameter")
pub fn broad_parameter(value : BroadFixture, index : Int) -> String {
  try {
    let writer = @encode.writer(1000, 100, 10)
    @duckdb.emit_physical_parameter(
      @duckdb.broad_scan_metadata_parameter(value.scan, index).unwrap(),
      writer,
    )
    @encode.finish(writer)
  } catch {
    _ => abort("fixture broad parameter")
  }
}

///|
#export_name("broadMetadata")
pub fn broad_metadata(
  value : BroadFixture,
  rows : Int,
  names : String,
  data : String,
) -> Bool {
  match
    @duckdb.admit_broad_table(value.scan, rows, fields(names), columns(data)) {
    Ok(table) => {
      value.table = Some(table)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("broadBegin")
pub fn broad_begin(value : BroadFixture, names : String) -> Bool {
  match
    @duckdb.prepare_broad_receiving(
      value.table.unwrap(),
      fields(names),
      { max_rows: 100, max_cells: 200, max_nodes: 200, max_text_bytes: 10000, },
      10000,
      {
        max_nodes: value.retention_nodes,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 10000,
      },
    ) {
    Ok(receiver) => {
      value.receiver = Some(receiver)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("broadAccept")
pub fn broad_accept(value : BroadFixture, rows : Int, data : String) -> Bool {
  @duckdb.accept_broad_chunk(value.receiver.unwrap(), rows, columns(data))
  is Ok(_)
}

///|
#export_name("broadFinish")
pub fn broad_finish(value : BroadFixture) -> Bool {
  match @duckdb.finish_broad_receiving(value.receiver.unwrap()) {
    Ok(captured) => {
      value.captured = Some(captured)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("broadCancel")
pub fn broad_cancel(value : BroadFixture) -> Unit {
  if value.receiver is Some(receiver) {
    @duckdb.abort_broad_receiving(receiver)
  }
  value.captured = None
  value.table = None
}

///|
#export_name("broadIdentity")
pub fn broad_identity(value : BroadFixture) -> String {
  guard value.captured is Some(captured) else { return "null" }
  let identity = @execution.identify_captured_rows(captured, {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 1000,
    max_depth: 10,
  }).unwrap()
  @execution.row_wire_cid(identity)
}
