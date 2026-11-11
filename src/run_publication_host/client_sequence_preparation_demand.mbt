///|
/// One checked original owner inventory, composed before the public preparation
/// is returned. Totals conservatively support every task's sequence; they are
/// independent of the output row envelope and JOIN's declared output bound.
fn client_sequence_preparation_demand(
  owners : Array[@lower.BoundPrepared],
  max_work : Int,
) -> Result[@lower.SequencePreparationDemand, @strategy.GraphIssue] {
  if max_work < 0 || owners.length() > max_work {
    return Err(@strategy.GraphIssue::WorkLimit)
  }
  let mut remaining = max_work - owners.length()
  let mut rows = 0L
  let mut cells = 0L
  let mut projection_names = 0L
  for owner in owners {
    let demand = match
      @lower.prepared_sequence_preparation_demand(
        @lower.bound_preparation(owner),
        remaining,
      ) {
      Ok(value) => value
      Err(@lower.WorkLimit) => return Err(@strategy.GraphIssue::WorkLimit)
      Err(_) => return Err(@strategy.GraphIssue::InvalidLimits)
    }
    remaining -= demand.work_used
    if demand.authored_literal_rows.to_int64() > 2147483647L - rows ||
      demand.authored_literal_cells.to_int64() > 2147483647L - cells ||
      demand.projection_name_bytes_bound.to_int64() >
      2147483647L -
      client_standard_values_sequence_limits().max_name_bytes.to_int64() -
      projection_names {
      return Err(@strategy.GraphIssue::InvalidLimits)
    }
    rows += demand.authored_literal_rows.to_int64()
    cells += demand.authored_literal_cells.to_int64()
    projection_names += demand.projection_name_bytes_bound.to_int64()
  }
  Ok({
    authored_literal_rows: rows.to_int(),
    authored_literal_cells: cells.to_int(),
    projection_name_bytes_bound: projection_names.to_int(),
    work_used: max_work - remaining,
  })
}

///|
// The checked owner retained these exact projection occurrences before it
// escaped. Keep the original authored-name allowance and all other explicit
// limits; only this already-checked projection spelling is additional demand.
fn client_sequence_limits_with_projection_demand(
  demand : @lower.SequencePreparationDemand,
) -> @lower.SequenceLimits {
  let original = client_standard_values_sequence_limits()
  {
    ..original,
    max_name_bytes: original.max_name_bytes + demand.projection_name_bytes_bound,
  }
}
