///|
#export_name("residentImportMaterial")
pub fn resident_import_material(
  table : @duckdb_driver.DuckDBResidentTable,
) -> @execution.RetainedOutputMaterial? raise NodeHostFailure {
  guard @duckdb_driver.resident_table_import(table) is Some(imported) else {
    raise InvalidCommand
  }
  @execution.producer_storage_retained_material(
    @duckdb.resident_import_storage(imported),
  )
}

///|
#export_name("residentImportStreamBegin")
pub fn resident_import_stream_begin(
  table : @duckdb_driver.DuckDBResidentTable,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> @duckdb.ResidentImportStream raise NodeHostFailure {
  guard @duckdb_driver.resident_table_import(table) is Some(imported) else {
    raise InvalidCommand
  }
  match
    @duckdb.prepare_resident_import_stream(
      imported, max_rows, values, wire, max_batch_bytes,
    ) {
    Ok(stream) => stream
    Err(issue) => raise Compute(InputStream(issue))
  }
}

///|
#export_name("residentImportStreamAppend")
pub fn resident_import_stream_append(
  stream : @duckdb.ResidentImportStream,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> String raise NodeHostFailure {
  let parameters = match
    @duckdb.append_resident_import_stream(stream, row, limits) {
    Ok(parameters) => parameters
    Err(issue) => raise Compute(InputStream(issue))
  }
  try {
    let writer = @encode.writer(limits.max_bytes, limits.max_nodes, 5)
    @encode.begin_array(writer)
    for parameter in parameters {
      @duckdb.emit_physical_parameter(parameter, writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    issue => {
      @duckdb.cancel_resident_import_stream(stream) |> ignore
      raise Encoding(issue)
    }
  }
}

///|
#export_name("residentImportStreamFinish")
pub fn resident_import_stream_finish(
  stream : @duckdb.ResidentImportStream,
) -> Unit raise NodeHostFailure {
  match @duckdb.finish_resident_import_stream(stream) {
    Ok(_) => ()
    Err(issue) => raise Compute(InputStream(issue))
  }
}

///|
#export_name("residentImportStreamVerify")
pub fn resident_import_stream_verify(
  stream : @duckdb.ResidentImportStream,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Unit raise NodeHostFailure {
  match @duckdb.verify_resident_import_stream(stream, row, limits) {
    Ok(_) => ()
    Err(issue) => raise Compute(InputStream(issue))
  }
}

///|
#export_name("residentImportStreamCancel")
pub fn resident_import_stream_cancel(
  stream : @duckdb.ResidentImportStream,
) -> Unit {
  @duckdb.cancel_resident_import_stream(stream) |> ignore
}
