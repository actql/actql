///|
/// Demand evidence for a CID-free managed receipt. This is neither execution
/// attestation nor retention proof. The installed attempt must supply both.
struct ManagedFixedComputeDemand {
  compute : FixedCompute
  receipt : @execution.ManagedOutputValueReceipt
  ceiling : Int
  usage : FixedComputeDemandUsage
}

///|
fn managed_fixed_receipt_matches(
  compute : FixedCompute,
  receipt : @execution.ManagedOutputValueReceipt,
) -> Bool {
  guard compute.imports.get(0) is Some(first) else { return false }
  let owner = @execution.producer_read_receiver(first.input)
  if !@execution.managed_output_value_receipt_matches(
      receipt,
      owner,
      fixed_query_target(compute.query),
    ) {
    return false
  }
  for imported in compute.imports {
    if !physical_equal(@execution.producer_read_receiver(imported.input), owner) ||
      !@execution.producer_read_available(imported.input) {
      return false
    }
  }
  true
}

///|
/// Uses the same demand laws and already accumulated import demand as the old
/// receiving path, without requiring row-array encoding or a content CID.
pub fn measure_managed_fixed_compute_demand(
  compute : FixedCompute,
  receipt : @execution.ManagedOutputValueReceipt,
  max_value_bytes : Int,
  physical : @execution.FixedInputGuardMeasureLimits,
  input_demand? : FixedImportDemand,
) -> Result[ManagedFixedComputeDemand, NativeDemandIssue] {
  if !managed_fixed_receipt_matches(compute, receipt) {
    return Err(InvalidState)
  }
  let output_rows = @execution.managed_output_value_row_count(receipt)
  let result = if input_demand is Some(demand) {
    consume_fixed_import_demand(
      demand, compute, output_rows, max_value_bytes, physical,
    )
  } else {
    measure_fixed_compute_demand_usage(
      compute, output_rows, max_value_bytes, physical,
    )
  }
  result.map(usage => { compute, receipt, ceiling: max_value_bytes, usage, })
}

///|
pub fn managed_fixed_compute_demand_matches(
  value : ManagedFixedComputeDemand,
  compute : FixedCompute,
  receipt : @execution.ManagedOutputValueReceipt,
  max_value_bytes : Int,
) -> Bool {
  physical_equal(value.compute, compute) &&
  physical_equal(value.receipt, receipt) &&
  value.ceiling == max_value_bytes &&
  managed_fixed_receipt_matches(compute, receipt)
}

///|
pub fn managed_fixed_compute_demand_usage(
  value : ManagedFixedComputeDemand,
) -> FixedComputeDemandUsage {
  value.usage
}
