///|
// SAME admitted Fragment roots, including dormant branches and every typed
// child/intermediate. Number/Boolean/Null payloads are bounded immediate
// cells; a scalar result alone cannot establish this constructor fact.
// Reuse the original typed node table, never sampled rows or authored SQL.
fn bounded_primitive_fragment_nodes(context : FragmentRuntimeContext) -> Int? {
  let request = context.fragment.candidate.material.request.request
  let roots = @lower.fragment_pipeline_roots(
    @lower.fragment_request_pipeline(request),
  )
  if !physical_equal(
      @lower.sequence_owner(@lower.root_sequence(roots)),
      @lower.kernel_owner(context.kernel),
    ) ||
    @lower.root_step_range(roots) !=
    (@lower.kernel_step(context.kernel), @lower.kernel_step(context.kernel) + 1) {
    return None
  }
  let mut total = 0
  for index in 0..<@lower.root_count(roots) {
    guard @lower.root_at(roots, index) is Some(root) &&
      root.step_index == @lower.kernel_step(context.kernel) else {
      return None
    }
    let original = root.typed_expression
    let count = @typing.node_count(original)
    if count < 1 || count > 2147483647 - total {
      return None
    }
    for node in 0..<count {
      guard @typing.node_at(original, node) is Some(value) else { return None }
      match value.contract.shape {
        @contract.Number | @contract.Boolean => ()
        _ => return None
      }
    }
    total += count
  }
  if total > 0 {
    Some(total)
  } else {
    None
  }
}

///|
// Constructor proof for the bounded, selected, single binding-row provider.
// This is not a bound inferred from an AST's encoded size. The accepted
// evaluator paths (expression.mbt) return an input/prior-slot alias, capture an
// immutable admitted literal (scalar.mbt), return inline Null, or select a
// checked property of an original input/prior-slot value. LENGTH of a direct
// original Text field also returns an inline Number without a new Text root.
// None builds a new value tree. A separately inventoried scalar pipeline admits
// Number CAST of a two-argument SUBSTRING over one original Text field and
// an admitted numeric literal. Logical live-byte guards execute unchanged.
//
// Replace the generic live-value DATA premium. The caller retains the full
// physical node/byte/depth quote except for required immediate Number/Boolean
// input/output cells: their measuring writer and charged row cursor construct
// no physical body or decoded forest. Even that constructor keeps the full
// depth, input/output roots, operation workspace and enforcement limits.
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
    ) else {
    return None
  }
  let bindings = @lower.kernel_bindings(kernel)
  let predicate_nodes = if @lower.kernel_body(kernel) is @lower.Filter(_) {
    bounded_primitive_fragment_nodes(context)
  } else {
    None
  }
  let count = match bindings {
    Some(value) => @lower.bindings_count(value)
    None =>
      match predicate_nodes {
        Some(nodes) => nodes
        None => return None
      }
  }
  let ordered = bindings.map(@lower.bindings_ordered).unwrap_or(false)
  let mut text_number = false
  let mut text_length = false
  let mut properties = 0L
  // A proven primitive predicate retains all original roots/continuations;
  // other predicates keep the complete generic live-value DATA envelope.
  for index in 0..<bindings.map(@lower.bindings_count).unwrap_or(0) {
    guard @lower.binding_at(bindings.unwrap(), index) is Some((_, expression)) else {
      return None
    }
    // Property continuations retain the original receiver and return its
    // selected immutable child (or Null). Their name/selection cursors and
    // logical result measurements still use the original workspace/guards.
    // Only a chain rooted in an original input/prior slot uses this proof;
    // computed receivers and dynamic subscripts keep the generic envelope.
    let mut leaf = expression
    let mut property = false
    while @lower.expression_body(leaf) is @lower.Property(child, _, ordinal) {
      if ordinal < 0 {
        return None
      }
      property = true
      properties += 1L
      leaf = child
    }
    if property {
      match @lower.expression_body(leaf) {
        @lower.Field(_, @relation.InputField(_)) => ()
        @lower.Field(_, @relation.PriorSlot(slot)) =>
          if !bounded_leaf_prior_slot_supported(ordered, index, slot) {
            return None
          }
        _ => return None
      }
      continue
    }
    match @lower.expression_body(expression) {
      @lower.Field(_, @relation.InputField(_))
      | @lower.Literal(_)
      | @lower.TypedNull => ()
      @lower.Field(_, @relation.PriorSlot(slot)) =>
        if !bounded_leaf_prior_slot_supported(ordered, index, slot) {
          return None
        }
      @lower.Unary(@lower.Length, child) => {
        // Length walks the SAME admitted Text and returns an inline Number
        // (or Null); it has no output Text root or builder. Constructed and
        // nested receivers retain the complete generic envelope.
        guard @lower.expression_contract(expression).shape is @contract.Number &&
          @lower.expression_contract(child).shape is @contract.Text(_) &&
          @lower.expression_body(child)
          is @lower.Field(_, @relation.InputField(_)) else {
          return None
        }
        text_length = true
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
  let roots = 2L * limits.rows.max_rows.to_int64() +
    count.to_int64() +
    2L +
    2L * properties
  // Current-row snapshot, binding values, and output aliases are separate
  // occurrences. Their immutable backing remains with its original owner.
  let aliases = inputs + outputs + count.to_int64() + properties
  let aliases_bytes = preparation_representation_cost({
    // Per root: LogicalRoot, measurement+Some, lease, scope Some, value/tag
    // carriers, plus conservative spare headers. References include both
    // root/lease arrays and scope slots/free-list spare capacity. Scalar words
    // include all root/measurement/lease fields and free-list backing.
    // Fixed tail: budget, two scopes, ordered execution, active ExpressionFrame,
    // leaf FieldName/Return/EvaluatedValue carriers and their empty arrays.
    // Traversal cursor/emit/writer backing remains in the physical envelope.
    // Only the independently checked immediate-scalar constructor omits an
    // unused body/forest; references and tagged JSON retain their full quote.
    // LENGTH additionally holds two one-element operand/root arrays, the
    // TextFunctionState (borrowed strings, no builder/output root), its
    // Unary/TextFunction/Return continuations, and the scalar decoder's
    // tuple/Some/Ok/Number carriers. Only one text function is active: bindings
    // run sequentially and their retained results are already in roots above.
    record_headers: 64L +
    8L * roots +
    2L * aliases +
    (if text_length { 16L } else { 0L }),
    reference_slots: 128L +
    16L * roots +
    4L * aliases +
    (if text_length { 24L } else { 0L }),
    scalar_words: 128L +
    16L * roots +
    2L * aliases +
    (if text_length { 64L } else { 0L }),
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
