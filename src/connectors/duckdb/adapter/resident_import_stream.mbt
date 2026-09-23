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
/// Verify a retained row without building native INSERT parameters. The
/// complete storage scan still binds every row to the selected producer.
pub fn verify_resident_import_stream(
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
