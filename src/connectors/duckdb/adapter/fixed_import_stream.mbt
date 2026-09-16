///|
/// Provisional parameter stream for an exact fixed import. A database must not
/// execute its consumer until full content verification and normal transport,
/// guard/demand and resource admission have succeeded.
struct FixedImportStream {
  owner : FixedImport
  scan : @execution.RetainedProducerScan
  mut rows : Int
  mut demand : FixedImportDemand?
}

///|
pub(all) enum FixedImportStreamIssue {
  Content(@execution.CompletedImportIssue)
  Parameter(ValueIssue)
  Demand(NativeDemandIssue)
  Physical(PhysicalResultIssue)
}

///|
pub fn prepare_fixed_import_physical(
  stream : FixedImportStream,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  metadata_work : Int,
) -> Result[PhysicalResult, FixedImportStreamIssue] {
  prepare_physical_result(
    @execution.retained_producer_scan_schema(stream.scan),
    fields,
    limits,
    metadata_work,
  ).map_err(issue => Physical(issue))
}

///|
pub fn verify_fixed_import_chunk(
  stream : FixedImportStream,
  physical : PhysicalResult,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, FixedImportStreamIssue] {
  if !physical_equal(
      physical.schema,
      @execution.retained_producer_scan_schema(stream.scan),
    ) {
    @execution.cancel_retained_producer_scan(stream.scan) |> ignore
    return Err(Physical(SchemaMismatch))
  }
  let batch = match admit_physical_chunk(physical, rows, columns) {
    Ok(batch) => batch
    Err(issue) => {
      @execution.cancel_retained_producer_scan(stream.scan) |> ignore
      return Err(Physical(issue))
    }
  }
  for row in 0..<rows {
    let values = Array::makei(@schema.field_count(physical.schema), column => {
      physical_batch_cell(batch, row, column).unwrap()
    })
    match verify_fixed_import_values(stream, values) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
pub fn prepare_fixed_import_stream(
  owner : FixedImport,
  max_rows : Int,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
) -> Result[FixedImportStream, FixedImportStreamIssue] {
  @execution.prepare_retained_producer_scan(
    owner.input,
    max_rows,
    values,
    wire,
    max_batch_bytes,
  )
  .map(scan => FixedImportStream::{ owner, scan, rows: 0, demand: None, })
  .map_err(issue => Content(issue))
}

///|
pub fn append_fixed_import_stream(
  stream : FixedImportStream,
  row : String,
  limits : @execution.RetainedRowDecodeLimits,
  materialize_parameters? : Bool = true,
) -> Result[Array[PhysicalParameter], FixedImportStreamIssue] {
  let values = match
    @execution.append_retained_producer_scan_wire(stream.scan, row, limits) {
    Ok(values) => values
    Err(issue) => return Err(Content(issue))
  }
  finish_fixed_import_row(stream, values, materialize_parameters)
}

///|
/// Existing resident/column readers can supply checked values without first
/// serializing them as retained row JSON. All content and consumer obligations
/// remain on the same stream; successful verification alone grants no execution.
pub fn verify_fixed_import_values(
  stream : FixedImportStream,
  values : Array[@admitted.CheckedValue],
) -> Result[Unit, FixedImportStreamIssue] {
  let projected = match
    @execution.append_retained_producer_scan_values(stream.scan, values) {
    Ok(projected) => projected
    Err(issue) => return Err(Content(issue))
  }
  finish_fixed_import_row(stream, projected, false).map(_ => ())
}

///|
fn finish_fixed_import_row(
  stream : FixedImportStream,
  values : Array[@admitted.CheckedValue],
  materialize_parameters : Bool,
) -> Result[Array[PhysicalParameter], FixedImportStreamIssue] {
  let parameters = []
  accumulate_fixed_import_demand(stream, values)
  stream.rows += 1
  let schema = @execution.producer_read_schema(stream.owner.input)
  for column, value in values {
    let field = @schema.field_at(schema, column).unwrap()
    if !materialize_parameters {
      // Resident reuse still checks the receiving physical type, but needs no
      // parameter object or parameter-wire representation of an existing cell.
      match parameter_type(field.contract) {
        Ok(_) => ()
        Err(issue) => {
          @execution.cancel_retained_producer_scan(stream.scan) |> ignore
          return Err(Parameter(issue))
        }
      }
      continue
    }
    // Use the receiving column's contract exactly as the cell-backed importer
    // does; the stored producer's schema need not use the same field names.
    match
      parameter_from_cell(field.contract, @execution.Captured(value.value)) {
      Ok(parameter) => parameters.push(parameter)
      Err(issue) => {
        @execution.cancel_retained_producer_scan(stream.scan) |> ignore
        return Err(Parameter(issue))
      }
    }
  }
  Ok(parameters)
}

///|
pub fn finish_fixed_import_stream(
  stream : FixedImportStream,
) -> Result[@execution.VerifiedProducerScan, FixedImportStreamIssue] {
  let verified = match @execution.finish_retained_producer_scan(stream.scan) {
    Ok(verified) => verified
    Err(issue) => return Err(Content(issue))
  }
  if !@execution.verified_producer_scan_matches(verified, stream.owner.input) {
    return Err(Content(Unavailable))
  }
  if stream.demand is Some(demand) {
    demand.verified = Some(verified)
  }
  Ok(verified)
}

///|
pub fn cancel_fixed_import_stream(stream : FixedImportStream) -> Bool {
  @execution.cancel_retained_producer_scan(stream.scan)
}

///|
pub fn attach_fixed_import_join(
  stream : FixedImportStream,
  join : @execution.FixedJoinStream,
) -> Result[Unit, FixedImportStreamIssue] {
  @execution.attach_retained_join_scan(stream.scan, join).map_err(issue => {
    Content(JoinValidation(issue))
  })
}

///|
/// Input guard accounting runs on the exact decoded rows used for physical
/// parameters, under the same measurement session as the eventual output.
pub fn attach_fixed_import_measurement(
  stream : FixedImportStream,
  measurement : @execution.FixedProducerMeasurement,
) -> Result[Unit, FixedImportStreamIssue] {
  @execution.attach_retained_producer_measurement(measurement, stream.scan).map_err(issue => {
      Content(InputGuard(issue))
    },
  )
}
