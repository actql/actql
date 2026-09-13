///|
/// Owned demand measurements for a fixed-input comparison, not SQL execution
/// attestation. The retained receipt and producer must still be live.
struct FixedComputeDemand {
  compute : FixedCompute
  receipt : FixedComputeReceipt
  ceiling : Int
  usage : NativeDemandUsage
}

///|
pub fn measure_fixed_compute_demand(
  compute : FixedCompute,
  receipt : FixedComputeReceipt,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
) -> Result[FixedComputeDemand, NativeDemandIssue] {
  let result = measure_fixed_compute_demand_impl(
    compute, receipt, max_value_bytes, physical,
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
) -> Result[FixedComputeDemand, NativeDemandIssue] {
  if !physical_equal(receipt.owner.compute, compute) ||
    !fixed_compute_receipt_matches(receipt, receipt.owner) {
    return Err(InvalidState)
  }
  if max_value_bytes < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let input = compute.imported.input
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
  let mut selected = None
  for index in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(
      @schema.field_at(schema, index).unwrap().name,
    )
    for size in [name.length(), compute.query.predicate_field.length()] {
      if size > budget.work {
        return Err(Predicate(MeasurementWork))
      }
      budget.work -= size
    }
    if name == compute.query.predicate_field {
      selected = Some(index)
      break
    }
  }
  guard selected is Some(column) else { return Err(InvalidLayout) }
  let rhs = match compute.query.parameter.value {
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
  finish_comparison_demand(
    state,
    @execution.admitted_output_row_count(receipt.rows),
    budget,
    physical,
  ).map(usage => FixedComputeDemand::{
    compute,
    receipt,
    ceiling: max_value_bytes,
    usage,
  })
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
) -> NativeDemandUsage {
  value.usage
}
