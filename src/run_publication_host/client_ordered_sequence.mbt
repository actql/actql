///|
/// The compiler uses the actual selected registry bodies, never a claimed
/// digest or an adapter-built reference table. Physical provider admission
/// and complete fragment evidence remain separate runtime obligations.
fn client_compiler_ordered_contract(
  limits : @execution.RegistryLimits,
) -> @execution.RegisteredOrderedContract? {
  guard parse_plan_identity_value(
      compiler_registered_body_wire(),
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    is Some(registry) &&
    parse_plan_identity_value(
      compiler_registered_values_wire(),
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    is Some(values) &&
    parse_plan_identity_value(
      compiler_registered_ordered_wire(),
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    is Some(ordered) &&
    @execution.admit_relation_registry(registry, values, limits)
    is Ok(contracts) else {
    return None
  }
  @execution.admit_ordered_contract(contracts, ordered, limits).to_option()
}

///|
/// Preserve the existing checked node serialization for every other step.
/// Only registered ordered params extend the logical Plan representation;
/// no executable-looking incomplete ordered node is emitted by the lowerer.
fn emit_client_sequence_steps(
  sequence : @lower.PreparedSequence,
  first : Int,
  end : Int,
  physical : @execution.RegistryLimits,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if first < 0 || end < first || end > @lower.sequence_count(sequence) {
    raise @encode.InvalidStructure
  }
  let mut contract : @execution.RegisteredOrderedContract? = None
  @encode.begin_array(out)
  for step in first..<end {
    match @lower.sequence_step(sequence, step) {
      Some(@lower.RowStep(kernel)) if @lower.kernel_bindings(kernel)
        is Some(bindings) &&
        @lower.bindings_ordered(bindings) => {
        if contract is None {
          // Installed body admission is separate from the emitted Plan budget.
          // Use the existing client runtime's finite registration profile;
          // a small valid Plan need not fit the much larger contract body.
          contract = client_compiler_ordered_contract({
            max_body_bytes: 100000,
            max_body_nodes: 10000,
            max_body_depth: 100,
          })
        }
        guard contract is Some(selected) &&
          @lower.prepare_ordered_references(kernel, {
            max_references: physical.max_body_nodes,
            max_pointer_bytes: physical.max_body_bytes,
            max_work: physical.max_body_bytes,
            max_frames: physical.max_body_depth,
          })
          is Ok(references) else {
          raise @encode.InvalidStructure
        }
        @execution.emit_ordered_kernel_node(
          @execution.prepare_ordered_params(selected, references),
          out,
        )
      }
      _ => @lower.emit_sequence_node(sequence, step, out)
    }
  }
  @encode.end_array(out)
}
