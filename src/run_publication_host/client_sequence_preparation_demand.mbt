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
  let mut expression_nodes = 0L
  let mut expression_text = 0L
  let mut full_sequence_steps = 0
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
    full_sequence_steps = Int::max(
      full_sequence_steps,
      demand.full_sequence_steps,
    )
    if demand.authored_literal_rows.to_int64() > 2147483647L - rows ||
      demand.authored_literal_cells.to_int64() > 2147483647L - cells ||
      demand.projection_name_bytes_bound.to_int64() >
      2147483647L -
      client_standard_values_sequence_limits().max_name_bytes.to_int64() -
      projection_names ||
      demand.authored_expression_nodes.to_int64() >
      2147483647L - expression_nodes ||
      demand.authored_expression_text_bytes.to_int64() >
      2147483647L - expression_text {
      return Err(@strategy.GraphIssue::InvalidLimits)
    }
    rows += demand.authored_literal_rows.to_int64()
    cells += demand.authored_literal_cells.to_int64()
    projection_names += demand.projection_name_bytes_bound.to_int64()
    expression_nodes += demand.authored_expression_nodes.to_int64()
    expression_text += demand.authored_expression_text_bytes.to_int64()
  }
  Ok({
    authored_literal_rows: rows.to_int(),
    authored_literal_cells: cells.to_int(),
    projection_name_bytes_bound: projection_names.to_int(),
    authored_expression_nodes: expression_nodes.to_int(),
    authored_expression_text_bytes: expression_text.to_int(),
    work_used: max_work - remaining,
    full_sequence_steps,
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
  client_sequence_limits_with_selected_demand(
    demand,
    original,
    original.max_steps,
    original.max_rows,
    original.max_cells,
  )
}

///|
// All quantities come from the same checked preparation and selected task.
// Reuse this constructor so task selection adds no policy-sized storage or
// extra limit-record copy. It is immutable DATA, not a resource grant.
fn client_sequence_limits_with_selected_demand(
  demand : @lower.SequencePreparationDemand,
  original : @lower.SequenceLimits,
  steps : Int,
  rows : Int,
  cells : Int,
) -> @lower.SequenceLimits {
  {
    ..original,
    max_steps: steps,
    max_rows: rows,
    max_cells: cells,
    max_name_bytes: original.max_name_bytes + demand.projection_name_bytes_bound,
    expressions: {
      ..original.expressions,
      max_nodes: Int::max(
        original.expressions.max_nodes,
        demand.authored_expression_nodes,
      ),
      max_literal_nodes: Int::max(
        original.expressions.max_literal_nodes,
        demand.authored_expression_nodes,
      ),
      max_literal_text_bytes: Int::max(
        original.expressions.max_literal_text_bytes,
        demand.authored_expression_text_bytes,
      ),
    },
  }
}
