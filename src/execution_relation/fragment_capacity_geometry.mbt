///|
// Constructor proof for the bounded, selected, single binding-row provider.
// This is not a bound inferred from an AST's encoded size. The three accepted
// evaluator cases (expression.mbt) return an input/prior-slot alias, capture an
// immutable admitted literal (scalar.mbt), or return inline Null. None builds
// a new value tree. Logical live-byte guards still execute unchanged.
//
// Only replace the generic live-value DATA premium. The caller MUST retain
// the complete physical node/byte/depth traversal quote, input/output DATA,
// operation workspace, and the original enforcement limits.
fn bounded_leaf_fragment_capacity(
  generated : GeneratedSequence,
  context : FragmentRuntimeContext,
  limits : SequenceExecutionLimits,
) -> Int64? {
  guard limits.rows.max_rows >= 0 &&
    generated.selected_steps is Some([step]) &&
    generated_sequence_step_at(generated, 0) is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_step(kernel) == step &&
    physical_equal(kernel, context.kernel) &&
    physical_equal(
      @lower.kernel_owner(kernel),
      @lower.sequence_owner(generated.sequence),
    ) &&
    @lower.kernel_bindings(kernel) is Some(bindings) else {
    return None
  }
  let count = @lower.bindings_count(bindings)
  let ordered = @lower.bindings_ordered(bindings)
  for index in 0..<count {
    guard @lower.binding_at(bindings, index) is Some((_, expression)) else {
      return None
    }
    match @lower.expression_body(expression) {
      @lower.Field(_, @relation.InputField(_))
      | @lower.Literal(_)
      | @lower.TypedNull => ()
      @lower.Field(_, @relation.PriorSlot(slot)) =>
        if !ordered || slot < 0 || slot >= index { return None }
      _ => return None
    }
  }
  let inputs = @schema.field_count(@lower.kernel_input_schema(kernel)).to_int64()
  let outputs = @schema.field_count(@lower.kernel_output_schema(kernel)).to_int64()
  // All input row roots remain held while output roots accumulate. Count both
  // full sides, every binding occurrence (including repeated prior-slot reads),
  // plus the active result and output-before-input-release transition. This
  // also covers any failed prefix; no cleanup/release credit is assumed.
  let roots = 2L * limits.rows.max_rows.to_int64() + count.to_int64() + 2L
  // Current-row snapshot, binding values, and output aliases are separate
  // occurrences. Their immutable backing remains with its original owner.
  let aliases = inputs + outputs + count.to_int64()
  preparation_representation_cost({
    // Per root: LogicalRoot, measurement+Some, lease, scope Some, value/tag
    // carriers, plus conservative spare headers. References include both
    // root/lease arrays and scope slots/free-list spare capacity. Scalar words
    // include all root/measurement/lease fields and free-list backing.
    // Fixed tail: budget, two scopes, ordered execution, active ExpressionFrame,
    // leaf FieldName/Return/EvaluatedValue carriers and their empty arrays.
    // Traversal cursor/emit/writer backing is STILL funded by the full physical
    // envelope; no depth-only assumption is made for references or tagged JSON.
    record_headers: 64L + 8L * roots + 2L * aliases,
    reference_slots: 128L + 16L * roots + 4L * aliases,
    scalar_words: 128L + 16L * roots + 2L * aliases,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
