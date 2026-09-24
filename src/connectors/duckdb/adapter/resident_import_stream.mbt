///|
/// Full producer copy into a provisional resident table. This does not stand
/// in for any later consumer's input measurement, demand or execution permit.
struct ResidentImportStream {
  owner : ResidentImport
  scan : @execution.RetainedStorageScan
}

///|
pub fn prepare_resident_import_stream(
  owner : ResidentImport,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[ResidentImportStream, FixedImportStreamIssue] {
  @execution.prepare_retained_storage_scan(
    owner.storage,
    max_rows,
    values,
    wire,
    max_batch_bytes,
  )
  .map(scan => ResidentImportStream::{ owner, scan, })
  .map_err(issue => Content(issue))
}

///|
pub fn append_resident_import_stream(
  stream : ResidentImportStream,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Result[Array[PhysicalParameter], FixedImportStreamIssue] {
  let values = match
    @execution.append_retained_storage_scan_wire(stream.scan, row, limits) {
    Ok(values) => values
    Err(issue) => return Err(Content(issue))
  }
  let schema = @execution.producer_storage_schema(stream.owner.storage)
  let parameters = []
  for column, value in values {
    let field = @schema.field_at(schema, column).unwrap()
    match
      parameter_from_cell(field.contract, @execution.Captured(value.value)) {
      Ok(parameter) => parameters.push(parameter)
      Err(issue) => {
        @execution.cancel_retained_storage_scan(stream.scan) |> ignore
        return Err(Parameter(issue))
      }
    }
  }
  Ok(parameters)
}

///|
/// Scalar staging uses the same exact retained-content verifier as the typed
/// importer. It avoids materializing physical parameters when the bounded
/// native appender checks the corresponding scalar row.
pub fn append_resident_import_scalar_stream(
  stream : ResidentImportStream,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Result[Unit, FixedImportStreamIssue] {
  match @execution.append_retained_storage_scan_wire(stream.scan, row, limits) {
    Ok(_) => Ok(())
    Err(issue) => Err(Content(issue))
  }
}

///|
/// Check the native staging table against the same retained-content stream
/// used by the row importer. Physical parsing alone is never import evidence.
pub fn prepare_resident_import_physical(
  stream : ResidentImportStream,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[PhysicalResult, PhysicalResultIssue] {
  prepare_physical_result(
    @execution.producer_storage_schema(stream.owner.storage),
    fields,
    limits,
    max_metadata_work,
  )
}

///|
pub fn append_resident_import_physical(
  stream : ResidentImportStream,
  physical : PhysicalResult,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, FixedImportStreamIssue] {
  let batch = match admit_physical_chunk(physical, rows, columns) {
    Ok(batch) => batch
    Err(issue) => {
      @execution.cancel_retained_storage_scan(stream.scan) |> ignore
      return Err(Physical(issue))
    }
  }
  let count = resident_import_column_count(stream.owner)
  if rows == 0 {
    return Ok(())
  }
  let values = Array::makei(count, column => {
    physical_batch_cell(batch, 0, column).unwrap()
  })
  for row in 0..<physical_batch_rows(batch) {
    for column in 0..<count {
      guard physical_batch_cell(batch, row, column) is Some(value) else {
        @execution.cancel_retained_storage_scan(stream.scan) |> ignore
        return Err(Content(Unavailable))
      }
      values[column] = value
    }
    match @execution.append_retained_storage_scan_values(stream.scan, values) {
      Ok(_) => ()
      Err(issue) => return Err(Content(issue))
    }
  }
  Ok(())
}

///|
pub fn finish_resident_import_stream(
  stream : ResidentImportStream,
) -> Result[@execution.VerifiedStorageScan, FixedImportStreamIssue] {
  match @execution.finish_retained_storage_scan(stream.scan) {
    Err(issue) => Err(Content(issue))
    Ok(verified) => {
      if !@execution.verified_storage_scan_matches(
          verified,
          stream.owner.storage,
        ) {
        return Err(Content(Unavailable))
      }
      Ok(verified)
    }
  }
}

///|
pub fn cancel_resident_import_stream(stream : ResidentImportStream) -> Bool {
  @execution.cancel_retained_storage_scan(stream.scan)
}
