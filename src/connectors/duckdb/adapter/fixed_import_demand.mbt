///|
/// Demand accumulated from the exact import scan. No row array or second input
/// evaluation is retained; successful consumption binds one receiving receipt.
struct FixedImportDemand {
  compute : FixedCompute
  column : Int
  rhs : ParameterValue
  state : ComparisonDemand
  budget : NativeValueBudget
  physical : @execution.FixedInputGuardMeasureLimits
  mut issue : NativeDemandIssue?
  mut verified : @execution.VerifiedProducerScan?
  mut consumed : Bool
}

///|
/// The receiver column required by a new comparison. The resident read plan
/// maps it to the stored source column; this alone grants no reuse.
pub fn fixed_import_demand_column(stream : FixedImportStream) -> Int? {
  stream.demand.map(value => value.column)
}

///|
/// A one-column physical receiver for a comparison on a reused immutable
/// material. The ordinary full scan remains the fallback when reuse fails.
pub fn prepare_fixed_import_reused_demand_physical(
  stream : FixedImportStream,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  metadata_work : Int,
) -> Result[PhysicalResult, FixedImportStreamIssue] {
  guard stream.values_reused &&
    stream.demand is Some(demand) &&
    stream.demand_physical is None &&
    demand.state.rows == 0 else {
    return Err(Demand(InvalidState))
  }
  let source = @execution.producer_read_schema(stream.owner.input)
  let field = @schema.field_at(source, demand.column).unwrap()
  let schema = match
    @schema.from_fields(
      [(field.name, field.contract)],
      max_fields=1,
      max_name_bytes=metadata_work,
    ) {
    Ok(value) => value
    Err(_) => return Err(Physical(MetadataLimit))
  }
  let physical = match
    prepare_physical_result(
      schema,
      fields,
      {
        max_rows: stream.rows,
        max_cells: stream.rows,
        max_nodes: limits.max_nodes,
        max_text_bytes: limits.max_text_bytes,
      },
      metadata_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  stream.demand_physical = Some(physical)
  Ok(physical)
}

///|
pub fn verify_fixed_import_reused_demand_chunk(
  stream : FixedImportStream,
  physical : PhysicalResult,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, FixedImportStreamIssue] {
  guard stream.values_reused &&
    stream.demand is Some(demand) &&
    stream.demand_physical is Some(bound) &&
    physical_equal(bound, physical) &&
    rows >= 0 &&
    rows <= stream.rows - stream.demand_read_rows else {
    return Err(Demand(InvalidState))
  }
  if !@execution.retained_producer_scan_reuse_current(stream.scan) {
    @execution.cancel_retained_producer_scan(stream.scan) |> ignore
    return Err(Content(Unavailable))
  }
  let batch = match admit_physical_chunk(physical, rows, columns) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_retained_producer_scan(stream.scan) |> ignore
      return Err(Physical(issue))
    }
  }
  for row in 0..<rows {
    if demand.issue is None {
      let cell = physical_batch_cell(batch, row, 0).unwrap()
      match
        accumulate_comparison_demand(
          demand.state,
          demand.budget,
          Admitted(cell.value),
          demand.rhs,
        ) {
        Ok(_) => ()
        Err(issue) => demand.issue = Some(issue)
      }
    }
  }
  stream.demand_read_rows += rows
  Ok(())
}

///|
pub fn attach_fixed_import_demand(
  stream : FixedImportStream,
  compute : FixedCompute,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[Unit, FixedImportStreamIssue] {
  if stream.rows != 0 ||
    stream.demand is Some(_) ||
    compute.imports.length() != 1 ||
    !physical_equal(stream.owner, compute.imports[0]) ||
    !@execution.producer_read_available(stream.owner.input) {
    return Err(Demand(InvalidState))
  }
  if max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(Demand(InvalidLimits))
  }
  guard compute.query is FilterSelect(query) else {
    return Err(Demand(InvalidLayout))
  }
  let budget : NativeValueBudget = {
    guards: {
      max_value_bytes,
      max_output_rows: @execution.producer_read_row_count(stream.owner.input),
    },
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let column = match
    fixed_comparison_column(
      @execution.producer_read_schema(stream.owner.input),
      query,
      budget,
    ) {
    Ok(column) => column
    Err(issue) => return Err(Demand(issue))
  }
  let rhs = match query.parameter.value {
    Admitted(value) => Admitted(value)
    Null => Null
    _ => return Err(Demand(InvalidLayout))
  }
  stream.demand = Some({
    compute,
    column,
    rhs,
    state: { rows: 0, field_bytes: 0L, rhs_bytes: None, null_rows: 0, },
    budget,
    physical,
    issue: None,
    verified: None,
    consumed: false,
  })
  Ok(())
}

///|
fn accumulate_fixed_import_demand(
  stream : FixedImportStream,
  values : Array[@admitted.CheckedValue],
) -> Unit {
  guard stream.demand is Some(demand) && demand.issue is None else { return }
  match
    accumulate_comparison_demand(
      demand.state,
      demand.budget,
      Admitted(values[demand.column].value),
      demand.rhs,
    ) {
    Ok(_) => ()
    Err(issue) => demand.issue = Some(issue)
  }
}

///|
pub fn fixed_import_verified_demand(
  stream : FixedImportStream,
) -> FixedImportDemand? {
  guard stream.demand is Some(demand) &&
    demand.verified is Some(verified) &&
    @execution.verified_producer_scan_matches(verified, stream.owner.input) else {
    return None
  }
  Some(demand)
}

///|
fn consume_fixed_import_demand(
  demand : FixedImportDemand,
  compute : FixedCompute,
  output_rows : Int,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[FixedComputeDemandUsage, NativeDemandIssue] {
  if demand.consumed ||
    !physical_equal(demand.compute, compute) ||
    demand.budget.guards.max_value_bytes != max_value_bytes ||
    demand.physical.max_work != physical.max_work ||
    demand.physical.max_bytes != physical.max_bytes ||
    demand.physical.max_nodes != physical.max_nodes ||
    demand.physical.max_depth != physical.max_depth ||
    !(demand.verified is Some(verified) &&
    @execution.verified_producer_scan_matches(
      verified,
      compute.imports[0].input,
    )) {
    return Err(InvalidState)
  }
  demand.consumed = true
  if demand.issue is Some(issue) {
    return Err(issue)
  }
  finish_comparison_demand(demand.state, output_rows, demand.budget, physical).map(usage => {
      Comparison(usage)
    },
  )
}
