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

///|
// Only these fixed built-in constructors select this serial peak. The Values
// literal borrows its same-owner cached DATA; the direct StringAgg and final
// projection keep their complete output holdings. Their operation kinds never
// consult an injected family in bounded_relation_step_provider.
pub fn bounded_literal_string_group_chain(sequence : GeneratedSequence) -> Bool {
  let prepared = @lower.bound_preparation(generated_sequence_owner(sequence))
  guard sequence.selected_steps is None &&
    sequence.selected_prefix_end is None &&
    @lower.sequence_count(sequence.sequence) == 3 &&
    @lower.preparation_input_count(prepared) == 0 &&
    @lower.node_count(prepared) == 3 &&
    generated_sequence_step_count(sequence) == 3 &&
    generated_sequence_step_index_at(sequence, 0) == Some(0) &&
    generated_sequence_step_index_at(sequence, 1) == Some(1) &&
    generated_sequence_step_index_at(sequence, 2) == Some(2) &&
    generated_sequence_step_at(sequence, 0) is Some(@lower.ValuesStep(_)) &&
    generated_sequence_step_at(sequence, 1) is Some(@lower.RowStep(group)) &&
    bounded_string_group_borrows_input(group) &&
    generated_sequence_step_at(sequence, 2) is Some(@lower.RowStep(projection)) &&
    @lower.kernel_is_projection(projection) &&
    @lower.node_at(prepared, 0) is Some(seed) &&
    @lower.node_input_count(seed) == 0 &&
    @lower.node_values_row_count(seed) is Some(_) &&
    @lower.node_values_literal_text_bytes(seed) is Some(_) else {
    return false
  }
  for index in 1..<3 {
    guard @lower.node_at(prepared, index) is Some(node) &&
      @lower.node_input_count(node) == 1 &&
      @lower.node_input_target(node, 0) == Some(@pipeline.Step(index - 1)) else {
      return false
    }
  }
  for index in 0..<3 {
    if index == 1 {
      continue
    }
    guard @lower.preparation_schema_at(prepared, @pipeline.Step(index))
      is Some(schema) &&
      @schema.all_fields_required(schema) else {
      return false
    }
    for field in 0..<@schema.field_count(schema) {
      if !json_leaf_representation_contract(
          @schema.field_at(schema, field).unwrap().contract,
        ) {
        return false
      }
    }
  }
  true
}
