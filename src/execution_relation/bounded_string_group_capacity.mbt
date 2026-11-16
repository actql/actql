///|
// The direct ordered StringAgg constructor keeps contributor indices and
// borrowed flat cells. Its sorter and exact UTF16 builder reserve the SAME
// RowWorkspace before allocation, including the builder/to_string overlap.
// Complete output Text DATA remains independently charged by the row limits.
// Dynamic/recursive/distinct/mixed aggregate families keep the full recipe.
fn bounded_string_group_borrows_input(kernel : @lower.PreparedKernel) -> Bool {
  guard @lower.kernel_group(kernel) is Some(group) &&
    !@lower.group_is_window(group) &&
    @lower.group_aggregate_count(group) == 1 &&
    bounded_number_group_scalar_schema(@lower.kernel_input_schema(kernel)) &&
    bounded_number_group_scalar_schema(@lower.kernel_output_schema(kernel)) &&
    @lower.group_aggregate_at(group, 0) is Some(aggregate) &&
    @lower.group_aggregate_function(aggregate) is @relation.StringAgg &&
    @lower.group_aggregate_argument(aggregate) is @lower.AggregateField(field) &&
    @schema.lookup(@lower.kernel_input_schema(kernel), field) is Some(contract) &&
    contract.shape is @contract.Text(_) &&
    @lower.group_aggregate_result(aggregate).shape is @contract.Text(_) &&
    @lower.group_aggregate_filter(aggregate) is None &&
    @lower.group_aggregate_distinct(aggregate) != Some(true) &&
    @lower.group_aggregate_delimiter(aggregate) is Some(_) &&
    @lower.group_aggregate_byte_limit(aggregate) is Some(maximum) &&
    maximum >= 0L &&
    @lower.group_aggregate_order_count(aggregate) > 0 else {
    return false
  }
  for index in 0..<@lower.group_aggregate_order_count(aggregate) {
    guard @lower.group_aggregate_order_term_at(aggregate, index)
      is Some((field, _, _)) &&
      @schema.lookup(@lower.kernel_input_schema(kernel), field) is Some(_) else {
      return false
    }
  }
  true
}
