///|
/// Owned demand measurements for a fixed-input comparison, not SQL execution
/// attestation. The retained receipt and producer must still be live.
struct FixedComputeDemand {
  compute : FixedCompute
  receipt : FixedComputeReceipt
  ceiling : Int
  usage : FixedComputeDemandUsage
}

///|
pub enum FixedComputeDemandUsage {
  Comparison(NativeDemandUsage)
  DirectCount(input_rows~ : Int, output_rows~ : Int)
  DirectView(input_rows~ : Int, output_rows~ : Int)
  DirectJoin(left_rows~ : Int, right_rows~ : Int, output_rows~ : Int)
}

///|
pub fn measure_fixed_compute_demand(
  compute : FixedCompute,
  receipt : FixedComputeReceipt,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
  input_demand? : FixedImportDemand,
) -> Result[FixedComputeDemand, NativeDemandIssue] {
  let result = measure_fixed_compute_demand_impl(
    compute, receipt, max_value_bytes, physical, input_demand,
  )
  if result is Err(_) && physical_equal(receipt.owner.compute, compute) {
    abort_fixed_compute_receiving(receipt.owner)
  }
  result
}

///|
fn measure_fixed_compute_demand_impl(
  compute : FixedCompute,
  receipt : FixedComputeReceipt,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
  input_demand : FixedImportDemand?,
) -> Result[FixedComputeDemand, NativeDemandIssue] {
  if !physical_equal(receipt.owner.compute, compute) ||
    !fixed_compute_receipt_matches(receipt, receipt.owner) {
    return Err(InvalidState)
  }
  if input_demand is Some(demand) {
    return consume_fixed_import_demand(
      demand,
      compute,
      @execution.admitted_output_row_count(receipt.rows),
      max_value_bytes,
      physical,
    ).map(usage => FixedComputeDemand::{
      compute,
      receipt,
      ceiling: max_value_bytes,
      usage,
    })
  }
  measure_fixed_compute_demand_usage(
    compute,
    @execution.admitted_output_row_count(receipt.rows),
    max_value_bytes,
    physical,
  ).map(usage => FixedComputeDemand::{
    compute,
    receipt,
    ceiling: max_value_bytes,
    usage,
  })
}

///|
fn measure_fixed_compute_demand_usage(
  compute : FixedCompute,
  output_rows : Int,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[FixedComputeDemandUsage, NativeDemandIssue] {
  if max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let input = compute.imports[0].input
  let query = match compute.query {
    FilterSelect(query) => query
    CountGroup(_) =>
      return Ok(
        DirectCount(
          input_rows=@execution.producer_read_row_count(input),
          output_rows~,
        ),
      )
    InnerJoin(query) =>
      return Ok(
        DirectJoin(
          left_rows=@execution.producer_read_row_count(
            compute.imports[query.left_input].input,
          ),
          right_rows=@execution.producer_read_row_count(
            compute.imports[query.right_input].input,
          ),
          output_rows~,
        ),
      )
  }
  let schema = @execution.producer_read_schema(input)
  let budget : NativeValueBudget = {
    guards: {
      max_value_bytes,
      max_output_rows: @execution.producer_read_row_count(input),
    },
    work: physical.max_work,
    bytes: physical.max_bytes,
    nodes: physical.max_nodes,
    depth: physical.max_depth,
  }
  let column = match fixed_comparison_column(schema, query, budget) {
    Ok(column) => column
    Err(issue) => return Err(issue)
  }
  let rhs = match query.parameter.value {
    Admitted(value) => Admitted(value)
    Null => Null
    _ => return Err(InvalidLayout)
  }
  let state : ComparisonDemand = {
    rows: 0,
    field_bytes: 0L,
    rhs_bytes: None,
    null_rows: 0,
  }
  for row in 0..<@execution.producer_read_row_count(input) {
    let value = match @execution.producer_read_cell(input, row, column) {
      Some(@execution.Null) => Null
      Some(@execution.Number(value)) => ScalarNumber(value)
      Some(@execution.Boolean(value)) => ScalarBoolean(value)
      Some(@execution.Captured(value)) => Admitted(value)
      _ => return Err(InvalidLayout)
    }
    match accumulate_comparison_demand(state, budget, value, rhs) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  finish_comparison_demand(state, output_rows, budget, physical).map(usage => {
    Comparison(usage)
  })
}

///|
fn fixed_comparison_column(
  schema : @schema.Schema,
  query : NativeQuery,
  budget : NativeValueBudget,
) -> Result[Int, NativeDemandIssue] {
  let mut selected = None
  for index in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(
      @schema.field_at(schema, index).unwrap().name,
    )
    for size in [name.length(), query.predicate_field.length()] {
      if size > budget.work {
        return Err(Predicate(MeasurementWork))
      }
      budget.work -= size
    }
    if name == query.predicate_field {
      selected = Some(index)
      break
    }
  }
  guard selected is Some(column) else { return Err(InvalidLayout) }
  Ok(column)
}

///|
struct FixedComputeStreamDemand {
  compute : FixedCompute
  receipt : FixedComputeStreamReceipt
  ceiling : Int
  usage : FixedComputeDemandUsage
}

///|
pub fn measure_fixed_compute_stream_demand(
  compute : FixedCompute,
  receipt : FixedComputeStreamReceipt,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
  input_demand? : FixedImportDemand,
) -> Result[FixedComputeStreamDemand, NativeDemandIssue] {
  if !physical_equal(receipt.owner.compute, compute) ||
    !fixed_compute_stream_receipt_matches(receipt, receipt.owner) {
    return Err(InvalidState)
  }
  let (_, _, _, output_rows) = @execution.output_stream_identity(
    receipt.admitted,
  )
  let result = if input_demand is Some(demand) {
    consume_fixed_import_demand(
      demand, compute, output_rows, max_value_bytes, physical,
    )
  } else {
    measure_fixed_compute_demand_usage(
      compute, output_rows, max_value_bytes, physical,
    )
  }
  if result is Err(_) {
    abort_fixed_compute_receiving(receipt.owner)
  }
  result.map(usage => FixedComputeStreamDemand::{
    compute,
    receipt,
    ceiling: max_value_bytes,
    usage,
  })
}

///|
pub fn fixed_compute_stream_demand_matches(
  value : FixedComputeStreamDemand,
  compute : FixedCompute,
  receipt : FixedComputeStreamReceipt,
  max_value_bytes : Int,
) -> Bool {
  physical_equal(value.compute, compute) &&
  physical_equal(value.receipt, receipt) &&
  value.ceiling == max_value_bytes &&
  fixed_compute_stream_receipt_matches(receipt, receipt.owner)
}

///|
pub fn fixed_compute_stream_demand_usage(
  value : FixedComputeStreamDemand,
) -> FixedComputeDemandUsage {
  value.usage
}

///|
pub fn fixed_compute_demand_matches(
  value : FixedComputeDemand,
  compute : FixedCompute,
  receipt : FixedComputeReceipt,
  max_value_bytes : Int,
) -> Bool {
  physical_equal(value.compute, compute) &&
  physical_equal(value.receipt, receipt) &&
  value.ceiling == max_value_bytes &&
  fixed_compute_receipt_matches(receipt, receipt.owner)
}

///|
pub fn fixed_compute_demand_usage(
  value : FixedComputeDemand,
) -> FixedComputeDemandUsage {
  value.usage
}
