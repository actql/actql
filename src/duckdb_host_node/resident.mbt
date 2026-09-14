///|
#export_name("residentBegin")
pub fn resident_begin(
  run : @strategy.CapturedDAG,
  task : Int,
  bytes : Int64,
) -> @strategy.ResidentEnvironment raise NodeHostFailure {
  match @strategy.begin_resident_environment(run, task, bytes) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentConfirm")
pub fn resident_confirm(
  run : @strategy.CapturedDAG,
  env : @strategy.ResidentEnvironment,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  match @strategy.confirm_resident_environment(run, env, bytes) {
    Ok(_) => ()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentClose")
pub fn resident_close(
  run : @strategy.CapturedDAG,
  env : @strategy.ResidentEnvironment,
  settled : Bool,
) -> Unit raise NodeHostFailure {
  match @strategy.close_resident_environment(run, env) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
  if settled {
    match @strategy.settle_resident_environment(run, env) {
      Ok(_) => ()
      Err(issue) => raise Physical(issue)
    }
  }
}

///|
#export_name("residentBorrow")
pub fn resident_borrow(
  run : @strategy.CapturedDAG,
  table : @strategy.ResidentTable,
  task : Int,
  entries : Int,
  names : Int,
  sql : Int,
) -> @strategy.ResidentRead raise NodeHostFailure {
  match @strategy.borrow_resident_table(run, table, task, entries, names, sql) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentBorrowSetup")
pub fn resident_borrow_setup(
  setup : @host.StrategyComputeHostConfiguration,
  env : @strategy.ResidentEnvironment,
  table : @strategy.ResidentTable,
  entries : Int,
  names : Int,
  sql : Int,
) -> @strategy.ResidentRead raise NodeHostFailure {
  let (run, task) = @host.configured_strategy_compute_graph(setup)
  if !@strategy.resident_environment_available(run, env) {
    raise InvalidCommand
  }
  resident_borrow(run, table, task, entries, names, sql)
}

///|
#export_name("residentReadSql")
pub fn resident_read_sql(read : @strategy.ResidentRead) -> String {
  @strategy.resident_read_view_sql(read)
}

///|
#export_name("residentReturn")
pub fn resident_return(
  read : @strategy.ResidentRead,
) -> Unit raise NodeHostFailure {
  match @strategy.return_resident_read(read) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentTablePrepare")
pub fn resident_table_prepare(
  run : @strategy.CapturedDAG,
  env : @strategy.ResidentEnvironment,
  producer : Int,
  bytes : Int64,
  entries : Int,
  names : Int,
  sql : Int,
) -> @strategy.ResidentTable raise NodeHostFailure {
  match
    @strategy.prepare_resident_table(
      run, env, producer, bytes, entries, names, sql,
    ) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentTableAt")
pub fn resident_table_at(
  run : @strategy.CapturedDAG,
  env : @strategy.ResidentEnvironment,
  producer : Int,
) -> @strategy.ResidentTable raise NodeHostFailure {
  guard @strategy.resident_table_at(run, env, producer) is Some(table) else {
    raise InvalidCommand
  }
  table
}

///|
#export_name("residentHasTable")
pub fn resident_has_table(
  run : @strategy.CapturedDAG,
  env : @strategy.ResidentEnvironment,
  producer : Int,
) -> Bool {
  @strategy.resident_table_at(run, env, producer) is Some(_)
}

///|
#export_name("residentTransferBegin")
pub fn resident_transfer_begin(
  run : @strategy.CapturedDAG,
  table : @strategy.ResidentTable,
  bytes : Int64,
  scratch : Int64,
) -> @strategy.ResidentTransfer raise NodeHostFailure {
  match @strategy.begin_resident_transfer(run, table, bytes, scratch) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentTransferCharge")
pub fn resident_transfer_charge(
  run : @strategy.CapturedDAG,
  transfer : @strategy.ResidentTransfer,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  match @strategy.charge_resident_transfer(run, transfer, bytes) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentTransferSettle")
pub fn resident_transfer_settle(
  run : @strategy.CapturedDAG,
  transfer : @strategy.ResidentTransfer,
  confirmed : Bool,
) -> Unit raise NodeHostFailure {
  match @strategy.settle_resident_transfer(run, transfer, confirmed) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentTransferComplete")
pub fn resident_transfer_complete(
  run : @strategy.CapturedDAG,
  transfer : @strategy.ResidentTransfer,
) -> Unit raise NodeHostFailure {
  match @strategy.complete_resident_transfer(run, transfer) {
    Ok(_) => ()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentTransferAbort")
pub fn resident_transfer_abort(
  run : @strategy.CapturedDAG,
  transfer : @strategy.ResidentTransfer,
) -> Unit raise NodeHostFailure {
  match @strategy.abort_resident_transfer(run, transfer) {
    Ok(_) => ()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentImportSql")
pub fn resident_import_sql(
  table : @strategy.ResidentTable,
  insert : Bool,
) -> String {
  let imported = @strategy.resident_table_import(table)
  if insert {
    @duckdb.resident_import_insert_sql(imported)
  } else {
    @duckdb.resident_import_create_sql(imported)
  }
}

///|
#export_name("residentImportCount")
pub fn resident_import_count(
  table : @strategy.ResidentTable,
  columns : Bool,
) -> Int {
  let imported = @strategy.resident_table_import(table)
  if columns {
    @duckdb.resident_import_column_count(imported)
  } else {
    @duckdb.resident_import_row_count(imported)
  }
}

///|
#export_name("residentImportParameter")
pub fn resident_import_parameter(
  table : @strategy.ResidentTable,
  row : Int,
  column : Int,
  bytes : Int,
  nodes : Int,
) -> String raise NodeHostFailure {
  let value = match
    @duckdb.resident_import_parameter(
      @strategy.resident_table_import(table),
      row,
      column,
    ) {
    Ok(value) => value
    Err(issue) => raise ComputeParameter(issue)
  }
  try {
    let writer = @encode.writer(bytes, nodes, 4)
    @duckdb.emit_physical_parameter(value, writer)
    @encode.finish(writer)
  } catch {
    issue => raise Encoding(issue)
  }
}
