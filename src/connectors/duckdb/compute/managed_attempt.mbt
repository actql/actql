///|
/// Installed managed output receiver for one existing selected Compute attempt.
/// This does not select a profile or waive demanded identities. The Host must
/// admit those obligations before choosing this output path.
struct ManagedDuckDBComputeOutput {
  attempt : DuckDBComputeAttempt
  values : @execution.ManagedOutputValues
  receiver : @duckdb.ManagedPhysicalOutput
  mut receipt : @execution.ManagedOutputValueReceipt?
  mut demand : @duckdb.ManagedFixedComputeDemand?
  mut open : Bool
  mut verified : Bool
}

///|
/// Claims the output mode exactly once. Input admission and join validation
/// precede it, and output consumes their remaining logical measurement budget.
pub fn begin_managed_duckdb_compute_output(
  attempt : DuckDBComputeAttempt,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[ManagedDuckDBComputeOutput, DuckDBComputeIssue] {
  if attempt.managed ||
    attempt.completed ||
    attempt.receiving is Some(_) ||
    !duckdb_compute_inputs_ready(attempt) {
    return Err(InvalidState)
  }
  attempt.managed = true
  let values = match
    @execution.prepare_fixed_managed_output_values(
      attempt.measurement,
      attempt.limits.retention,
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_duckdb_compute_attempt(attempt)
      return Err(ManagedValues(Values(issue)))
    }
  }
  let capacity = @connector.fixed_compute_request_capacity(attempt.request)
  let physical = if capacity.max_rows < attempt.limits.physical.max_rows {
    { ..attempt.limits.physical, max_rows: capacity.max_rows, }
  } else {
    attempt.limits.physical
  }
  let receiver = match
    @duckdb.prepare_managed_physical_output(
      values,
      fields,
      physical,
      attempt.limits.metadata_work,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_managed_output_values(values) |> ignore
      abort_duckdb_compute_attempt(attempt)
      return Err(ManagedValues(issue))
    }
  }
  Ok({
    attempt,
    values,
    receiver,
    receipt: None,
    demand: None,
    open: true,
    verified: false,
  })
}

///|
/// For installing the exact Store retention port before the first output row.
pub fn managed_duckdb_compute_output_values(
  output : ManagedDuckDBComputeOutput,
) -> @execution.ManagedOutputValues {
  output.values
}

///|
pub fn cancel_managed_duckdb_compute_output(
  output : ManagedDuckDBComputeOutput,
) -> Unit {
  output.open = false
  output.verified = false
  @duckdb.cancel_managed_physical_output(output.receiver) |> ignore
  close_duckdb_compute_attempt(output.attempt)
}

///|
pub fn receive_managed_duckdb_compute_output(
  output : ManagedDuckDBComputeOutput,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBComputeIssue] {
  if !output.open || !output.attempt.live {
    return Err(InvalidState)
  }
  match @duckdb.append_managed_physical_output(output.receiver, rows, columns) {
    Ok(_) => Ok(())
    Err(issue) => {
      cancel_managed_duckdb_compute_output(output)
      Err(ManagedValues(issue))
    }
  }
}

///|
/// Provisional content only: the native operation may not yet be settled.
pub fn finish_managed_duckdb_compute_output(
  output : ManagedDuckDBComputeOutput,
) -> Result[@execution.ManagedOutputValueReceipt, DuckDBComputeIssue] {
  if !output.open || !output.attempt.live {
    return Err(InvalidState)
  }
  output.open = false
  match @duckdb.finish_managed_physical_output(output.receiver) {
    Ok(receipt) => {
      output.receipt = Some(receipt)
      Ok(receipt)
    }
    Err(issue) => {
      cancel_managed_duckdb_compute_output(output)
      Err(ManagedValues(issue))
    }
  }
}

///|
/// Run only after actual transport settlement. Failure closes the attempt;
/// no alternate output mode or demand-budget reset is available afterwards.
pub fn verify_managed_duckdb_compute_output(
  output : ManagedDuckDBComputeOutput,
) -> Result[Unit, DuckDBComputeIssue] {
  let result = verify_managed_duckdb_compute_output_impl(output)
  if result is Err(_) {
    cancel_managed_duckdb_compute_output(output)
  }
  result
}

///|
fn verify_managed_duckdb_compute_output_impl(
  output : ManagedDuckDBComputeOutput,
) -> Result[Unit, DuckDBComputeIssue] {
  let attempt = output.attempt
  guard !output.open &&
    !output.verified &&
    attempt.live &&
    !attempt.completed &&
    output.receipt is Some(receipt) else {
    return Err(InvalidState)
  }
  if !(attempt.transport_matches)(attempt) || !attempt.live {
    return Err(UnverifiedTransport)
  }
  if !@duckdb.fixed_compute_join_validation_matches(
      attempt.compute,
      attempt.join_validation,
    ) ||
    !@execution.managed_output_value_fixed_measurement_matches(
      receipt,
      attempt.measurement,
    ) {
    return Err(Guard(ForeignInput))
  }
  let capacity = @connector.fixed_compute_request_capacity(attempt.request)
  let demand = if attempt.input_demand is Some(input_demand) {
    @duckdb.measure_managed_fixed_compute_demand(
      attempt.compute,
      receipt,
      capacity.max_value_bytes,
      attempt.limits.demand,
      input_demand~,
    )
  } else {
    @duckdb.measure_managed_fixed_compute_demand(
      attempt.compute,
      receipt,
      capacity.max_value_bytes,
      attempt.limits.demand,
    )
  }
  match demand {
    Err(issue) => Err(Demand(issue))
    Ok(demand) => {
      output.demand = Some(demand)
      output.verified = true
      Ok(())
    }
  }
}

///|
/// Finite verifier input to the common managed completion port. Exact retained
/// material is checked in addition to the selected attempt's execution facts.
/// This is not itself a completion, read permission or resource settlement API.
pub fn[T] verified_managed_duckdb_compute_material(
  output : ManagedDuckDBComputeOutput,
  material : @execution.ManagedRetainedOutput[T],
) -> @execution.ManagedRetainedOutput[T]? {
  let attempt = output.attempt
  guard output.verified &&
    attempt.live &&
    !attempt.completed &&
    output.receipt is Some(receipt) &&
    output.demand is Some(demand) &&
    (attempt.transport_matches)(attempt) &&
    attempt.live &&
    @execution.managed_output_value_fixed_measurement_matches(
      receipt,
      attempt.measurement,
    ) &&
    @duckdb.managed_fixed_compute_demand_matches(
      demand,
      attempt.compute,
      receipt,
      @connector.fixed_compute_request_capacity(attempt.request).max_value_bytes,
    ) &&
    @execution.managed_retained_output_matches(material, receipt) &&
    attempt.live else {
    return None
  }
  Some(material)
}
