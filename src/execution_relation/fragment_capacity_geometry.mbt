///|
// Constructor proof for the bounded, selected, single binding-row provider.
// This is not a bound inferred from an AST's encoded size. The three accepted
// evaluator cases (expression.mbt) return an input/prior-slot alias, capture an
// immutable admitted literal (scalar.mbt), or return inline Null. None builds
// a new value tree. A separately inventoried scalar pipeline below admits
// Number CAST of a two-argument SUBSTRING over one original Text field and
// an admitted numeric literal. Logical live-byte guards execute unchanged.
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
  let mut text_number = false
  for index in 0..<count {
    guard @lower.binding_at(bindings, index) is Some((_, expression)) else {
      return None
    }
    match @lower.expression_body(expression) {
      @lower.Field(_, @relation.InputField(_))
      | @lower.Literal(_)
      | @lower.TypedNull => ()
      @lower.Field(_, @relation.PriorSlot(slot)) =>
        if !bounded_leaf_prior_slot_supported(ordered, index, slot) {
          return None
        }
      @lower.Cast(child) => {
        // This exact evaluator path allocates scalar text, not a value tree.
        // General CAST, nested expressions and dynamic substring positions
        // retain the original generic quote.
        guard @lower.expression_contract(expression).shape is @contract.Number &&
          @lower.expression_contract(child).shape is @contract.Text(_) &&
          @lower.expression_body(child)
          is @lower.Many(@lower.Substring, [text, start]) &&
          @lower.expression_body(text)
          is @lower.Field(_, @relation.InputField(_)) &&
          @lower.expression_contract(text).shape is @contract.Text(_) &&
          @lower.expression_body(start) is @lower.Literal(_) &&
          @lower.expression_contract(start).shape is @contract.Number else {
          return None
        }
        text_number = true
      }
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
  let aliases_bytes = preparation_representation_cost({
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
  if !text_number {
    return aliases_bytes
  }
  let live = context.limits.max_live_value_bytes
  if live < 0L || live > (9223372036854775807L - 256L) / 4L {
    return None
  }
  // expression_text_functions admits every slice byte before its builder.
  // CAST charges that original root before parse_json; successful numeric
  // text is ASCII and its input is borrowed by Parser. The slice builder and
  // read_binary64 spelling builder execute in succession. Keep two complete
  // part/header/slot sets per admitted byte, spare array slots and both text
  // spellings, including the failed-parser prefix. Fixed tail covers the
  // Cast/Many/TextFunction continuations, Parser/Node/Span/Point and roots.
  // The original operation workspace and full physical traversal envelope
  // remain independently charged by the caller.
  guard aliases_bytes is Some(base) &&
    preparation_representation_cost({
      record_headers: 128L + 2L * live,
      reference_slots: 256L + 2L * live,
      scalar_words: 256L + 2L * live,
      owned_utf16_units: 4L * live,
      owned_wire_bytes: 4L * live,
    })
    is Some(copies) else {
    return None
  }
  checked_preparation_add_product(base, copies, 1L)
}

///|
// Kept explicit so malformed references, normally refused by checked lowering,
// can be tested without constructing a counterfeit checked kernel.
fn bounded_leaf_prior_slot_supported(
  ordered : Bool,
  index : Int,
  slot : Int,
) -> Bool {
  ordered && slot >= 0 && slot < index
}
