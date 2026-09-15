///|
#export_name("residentBegin")
pub fn resident_begin(
  run : @strategy.CapturedDAG,
  task : Int,
  bytes : Int64,
) -> @duckdb_driver.DuckDBResidentStore raise NodeHostFailure {
  match @strategy.begin_resident_environment(run, task, bytes) {
    Ok(value) => @duckdb_driver.prepare_resident_store(value)
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentConfirm")
pub fn resident_confirm(
  run : @strategy.CapturedDAG,
  env : @duckdb_driver.DuckDBResidentStore,
  bytes : Int64,
) -> Unit raise NodeHostFailure {
  match
    @strategy.confirm_resident_environment(
      run,
      @duckdb_driver.resident_store_environment(env),
      bytes,
    ) {
    Ok(_) => ()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentClose")
pub fn resident_close(
  run : @strategy.CapturedDAG,
  env : @duckdb_driver.DuckDBResidentStore,
  settled : Bool,
) -> Unit raise NodeHostFailure {
  match @duckdb_driver.close_resident_store(run, env, settled) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentBorrowSetup")
pub fn resident_borrow_setup(
  setup : @host.StrategyComputeHostConfiguration,
  env : @duckdb_driver.DuckDBResidentStore,
  tables : Array[@duckdb_driver.DuckDBResidentTable],
  entries : Int,
  names : Int,
  sql : Int,
) -> @duckdb_driver.DuckDBResidentInputs raise NodeHostFailure {
  match
    @host.borrow_configured_resident_inputs(
      setup,
      env,
      tables.map(@duckdb_driver.resident_table_handle),
      entries,
      names,
      sql,
    ) {
    Ok(value) => value
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentInputsSql")
pub fn resident_inputs_sql(
  inputs : @duckdb_driver.DuckDBResidentInputs,
) -> Array[String] {
  @duckdb_driver.resident_inputs_read_plans(inputs).map(
    @duckdb_compute.duckdb_resident_read_sql,
  )
}

///|
#export_name("residentCancelInputs")
pub fn resident_cancel_inputs(
  inputs : @duckdb_driver.DuckDBResidentInputs,
) -> Unit raise NodeHostFailure {
  match @duckdb_driver.cancel_resident_inputs(inputs) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentTablePrepare")
pub fn resident_table_prepare(
  run : @strategy.CapturedDAG,
  env : @duckdb_driver.DuckDBResidentStore,
  producer : Int,
  bytes : Int64,
  entries : Int,
  names : Int,
  sql : Int,
) -> @duckdb_driver.DuckDBResidentTable raise NodeHostFailure {
  match
    @duckdb_driver.prepare_resident_table(
      run, env, producer, bytes, entries, names, sql,
    ) {
    Ok(value) => @duckdb_driver.bind_resident_table(env, value).unwrap()
    Err(issue) => raise Strategy(issue)
  }
}

///|
#export_name("residentTableAt")
pub fn resident_table_at(
  run : @strategy.CapturedDAG,
  env : @duckdb_driver.DuckDBResidentStore,
  producer : Int,
) -> @duckdb_driver.DuckDBResidentTable raise NodeHostFailure {
  guard @strategy.resident_table_at(
      run,
      @duckdb_driver.resident_store_environment(env),
      producer,
    )
    is Some(table) else {
    raise InvalidCommand
  }
  @duckdb_driver.bind_resident_table(env, table).unwrap()
}

///|
#export_name("residentTableCancel")
pub fn resident_table_cancel(
  run : @strategy.CapturedDAG,
  table : @duckdb_driver.DuckDBResidentTable,
) -> Unit raise NodeHostFailure {
  match
    @strategy.cancel_resident_table_preparation(
      run,
      @duckdb_driver.resident_table_handle(table),
    ) {
    Ok(_) => ()
    Err(issue) => raise Physical(issue)
  }
}

///|
#export_name("residentHasTable")
pub fn resident_has_table(
  run : @strategy.CapturedDAG,
  env : @duckdb_driver.DuckDBResidentStore,
  producer : Int,
) -> Bool {
  @strategy.resident_table_at(
    run,
    @duckdb_driver.resident_store_environment(env),
    producer,
  )
  is Some(_)
}

///|
#export_name("residentTransferBegin")
pub fn resident_transfer_begin(
  run : @strategy.CapturedDAG,
  table : @duckdb_driver.DuckDBResidentTable,
  bytes : Int64,
  scratch : Int64,
) -> @strategy.ResidentTransfer raise NodeHostFailure {
  match
    @strategy.begin_resident_transfer(
      run,
      @duckdb_driver.resident_table_handle(table),
      bytes,
      scratch,
    ) {
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
  table : @duckdb_driver.DuckDBResidentTable,
  insert : Bool,
) -> String raise NodeHostFailure {
  guard @duckdb_driver.resident_table_import(table) is Some(imported) else {
    raise InvalidCommand
  }
  if insert {
    @duckdb.resident_import_insert_sql(imported)
  } else {
    @duckdb.resident_import_create_sql(imported)
  }
}

///|
#export_name("residentImportCount")
pub fn resident_import_count(
  table : @duckdb_driver.DuckDBResidentTable,
  columns : Bool,
) -> Int raise NodeHostFailure {
  guard @duckdb_driver.resident_table_import(table) is Some(imported) else {
    raise InvalidCommand
  }
  if columns {
    @duckdb.resident_import_column_count(imported)
  } else {
    @duckdb.resident_import_row_count(imported)
  }
}

///|
#export_name("residentImportParameter")
pub fn resident_import_parameter(
  table : @duckdb_driver.DuckDBResidentTable,
  row : Int,
  column : Int,
  bytes : Int,
  nodes : Int,
) -> String raise NodeHostFailure {
  guard @duckdb_driver.resident_table_import(table) is Some(imported) else {
    raise InvalidCommand
  }
  let value = match @duckdb.resident_import_parameter(imported, row, column) {
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
