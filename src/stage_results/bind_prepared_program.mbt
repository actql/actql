///|
/// Bind the declarations owned by a prepared topology without reissuing its
/// Source or pipelines. Arbitrary wiring has no retained preparation accounting
/// and is rejected. Depth bounds the new binding pass, not a topology recheck.
pub fn bind_prepared_program(
  wiring : ResultWiring,
  supplied : @decode.Cursor?,
  limits : LocalProgramLimits,
) -> Result[PreparedLocalSource, LocalSourceIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    limits.max_stages < 0 ||
    limits.max_steps < 0 ||
    limits.max_results < 0 {
    return Err(InvalidLimits)
  }
  let used = match wiring.preparation_usage {
    Some(v) => v
    None => return Err(MissingPreparation)
  }
  let count = @parameters.stage_count(wiring.source)
  if count > limits.max_stages ||
    used.steps > limits.max_steps ||
    used.results > limits.max_results ||
    used.tokens > limits.max_tokens ||
    count >= limits.max_work ||
    used.work > limits.max_work - count - 1 ||
    used.nodes > limits.max_nodes ||
    used.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let declarations = @parameters.declarations(wiring.source)
  let (decl_nodes, decl_text) = @binding.declaration_usage(declarations)
  if decl_nodes > limits.max_nodes - used.nodes ||
    decl_text > limits.max_text_bytes - used.text_bytes {
    return Err(BudgetExceeded)
  }
  let bound = match
    @binding.bind(declarations, supplied, {
      max_nodes: limits.max_nodes - used.nodes - decl_nodes,
      max_text_bytes: limits.max_text_bytes - used.text_bytes - decl_text,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Binding(e))
  }
  let (bind_nodes, bind_text) = @binding.binding_usage(bound)
  let values = match bound {
    Ready(v) => v
    NeedsBindings(missing) => return Err(NeedsBindings(missing))
  }
  finish_local_source(
    wiring, used, values, decl_nodes, decl_text, bind_nodes, bind_text, limits,
  )
}
