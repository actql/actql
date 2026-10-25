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
      demand.authored_literal_cells.to_int64() > 2147483647L - cells {
      return Err(@strategy.GraphIssue::InvalidLimits)
    }
    rows += demand.authored_literal_rows.to_int64()
    cells += demand.authored_literal_cells.to_int64()
  }
  Ok({
    authored_literal_rows: rows.to_int(),
    authored_literal_cells: cells.to_int(),
    work_used: max_work - remaining,
  })
}
