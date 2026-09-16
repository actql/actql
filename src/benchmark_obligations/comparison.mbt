///|
/// Exact completed input scan association, not a product execution receipt.
struct ObligationComparison {
  input : ObligationStream
  slot : ComparisonSlot
  mut consumed : Bool
}

///|
priv struct ComparisonSlot {
  measurement : @duckdb.ComparisonMeasurement
  mut issue : @duckdb.NativeDemandIssue?
}

///|
#export_name("obligationComparison")
pub fn obligation_comparison(
  input : ObligationStream,
  field : String,
  rhs_columns : String,
  ceiling : Int,
  limits : @execution.FixedInputGuardMeasureLimits,
) -> ObligationComparison raise ObligationFailure {
  let (rows, _, _, _) = @duckdb.physical_result_usage(input.physical)
  if !input.open || rows != 0 {
    raise Closed
  }
  let mut column = None
  for index in 0..<input.width {
    let (name, position) = @execution.row_wire_order_column(input.order, index).unwrap()
    if name == field {
      column = Some(position)
    }
  }
  guard column is Some(column) else { raise InvalidLayout }
  // This registered comparator uses a numeric comparison RHS. Decode it through
  // the same bounded physical value admission as the input, never a JS Number
  // cast pretending to be an admitted value.
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("rhs"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=3,
  ).unwrap()
  let physical = @duckdb.prepare_physical_result(
    schema,
    [("rhs", @duckdb.Float64)],
    { max_rows: 1, max_cells: 1, max_nodes: 1, max_text_bytes: 0, },
    100,
  ).unwrap()
  let columns = match
    @duckdb.decode_transport_columns(rhs_columns, {
      max_bytes: 64,
      max_nodes: 10,
      max_columns: 1,
      max_rows: 1,
      max_text_bytes: 32,
    }) {
    Ok(value) => value
    Err(_) => raise InvalidLayout
  }
  let batch = match @duckdb.admit_physical_chunk(physical, 1, columns) {
    Ok(value) => value
    Err(issue) => raise Physical(issue)
  }
  let measurement = match
    @duckdb.prepare_comparison_measurement(
      @duckdb.physical_batch_cell(batch, 0, 0).unwrap().value,
      ceiling,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => raise Demand(issue)
  }
  let slot = { measurement, issue: None, }
  input.comparisons.push((column, slot))
  { input, slot, consumed: false, }
}

///|
#export_name("obligationComparisonFinish")
pub fn obligation_comparison_finish(
  comparison : ObligationComparison,
  true_rows : Int,
) -> @duckdb.NativeDemandUsage raise ObligationFailure {
  if !comparison.input.finished || comparison.consumed {
    raise Closed
  }
  comparison.consumed = true
  if comparison.slot.issue is Some(issue) {
    raise Demand(issue)
  }
  match
    @duckdb.finish_comparison_measurement(
      comparison.slot.measurement,
      true_rows,
    ) {
    Ok(value) => value
    Err(issue) => raise Demand(issue)
  }
}
