///|
// The actual bounded analytic constructor scans original cells with charged
// cursors and a measuring writer. It builds no input forest or measurement
// body. Keep complete operation/frame/Fragment storage and final output DATA.
// Escaping argument Text must be the original immutable payload; unknown
// constructed/recursive/optional values retain the full generic recipe.
pub fn bounded_analytic_borrows_input(kernel : @lower.PreparedKernel) -> Bool {
  guard @lower.kernel_analytic(kernel) is Some(analytic) &&
    analytic_execution_supported_with_numeric(analytic) &&
    bounded_number_group_scalar_schema(@lower.kernel_input_schema(kernel)) &&
    bounded_number_group_scalar_schema(@lower.kernel_output_schema(kernel)) else {
    return false
  }
  for index in 0..<@lower.analytic_call_count(analytic) {
    let call = @lower.analytic_call_at(analytic, index).unwrap()
    if @lower.analytic_call_default(call) is Some(fallback) &&
      !@lower.expression_result_borrows_payload(fallback) {
      return false
    }
    match @lower.analytic_call_function(call) {
      @lower.PreparedRowNumber
      | @lower.PreparedRank
      | @lower.PreparedDenseRank
      | @lower.PreparedPercentRank
      | @lower.PreparedNtile(_) => ()
      @lower.PreparedLag(expression, _)
      | @lower.PreparedLead(expression, _)
      | @lower.PreparedFirstValue(expression)
      | @lower.PreparedLastValue(expression) =>
        if !@lower.expression_result_borrows_payload(expression) {
          return false
        }
      @lower.PreparedFrameAggregate(aggregate) => {
        match @lower.group_aggregate_argument(aggregate) {
          @lower.AggregateRows | @lower.AggregateField(_) => ()
          @lower.AggregateExpression(expression) =>
            if !@lower.expression_result_borrows_payload(expression) {
              return false
            }
        }
        if @lower.group_aggregate_function(aggregate) is @relation.StringAgg {
          guard @lower.group_aggregate_byte_limit(aggregate) is Some(maximum) &&
            maximum >= 0L else {
            return false
          }
        }
      }
    }
  }
  true
}

///|
// Every frame result is retained in evaluated[call][row] before output-row
// admission. Price that complete staged Text independently of a tiny output
// policy; no early row-admission or scratch-release credit is assumed. The
// original output holding and each current frame's builder remain separate.
pub fn bounded_analytic_staged_text_capacity(
  kernel : @lower.PreparedKernel,
  limits : SequenceExecutionLimits,
) -> Int64? {
  guard bounded_analytic_borrows_input(kernel) &&
    @lower.kernel_analytic(kernel) is Some(analytic) &&
    limits.rows.max_rows >= 0 else {
    return None
  }
  let rows = limits.rows.max_rows.to_int64()
  let mut nodes = 0L
  let mut bytes = 0L
  for index in 0..<@lower.analytic_call_count(analytic) {
    let call = @lower.analytic_call_at(analytic, index).unwrap()
    if @lower.analytic_call_function(call)
      is @lower.PreparedFrameAggregate(aggregate) &&
      @lower.group_aggregate_function(aggregate) is @relation.StringAgg {
      guard @lower.group_aggregate_byte_limit(aggregate) is Some(maximum) &&
        checked_preparation_add_product(nodes, rows, 1L) is Some(next_nodes) &&
        checked_preparation_add_product(bytes, rows, maximum)
        is Some(next_bytes) else {
        return None
      }
      nodes = next_nodes
      bytes = next_bytes
    }
  }
  execution_capacity_inventory_bytes([
    { unit: ValueNodeSlots, count: nodes, copies: 1, },
    { unit: DecodedTextBytes, count: bytes, copies: 1, },
  ])
}
