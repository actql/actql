///|
/// Bind the declarations owned by a prepared topology without reissuing its
/// Source or pipelines. Arbitrary wiring has no retained preparation accounting
/// and is rejected. Depth bounds the new binding pass, not a topology recheck.
pub fn bind_prepared_program(
  wiring : ResultWiring,
  supplied : @decode.Cursor?,
  limits : LocalProgramLimits,
) -> Result[PreparedLocalSource, LocalSourceIssue] {
  let original = match
    prepare_local_program_binding_input(wiring, supplied, limits) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  finish_local_program_binding_input(
    original,
    @parameters.bind(wiring.source, supplied, original.binding_limits),
  )
}

///|
/// The original topology chooses the remaining binding limits. This is a pure
/// constructor continuation, not a new Source, Resource Owner or ready Plan.
struct LocalProgramBindingInput {
  wiring : ResultWiring
  supplied : @decode.Cursor?
  limits : LocalProgramLimits
  used : LocalProgramUsage
  binding_limits : @value.Limits
  declaration_nodes : Int
  declaration_text : Int
  mut available : Bool
}

///|
/// Fixed selection constructor only: declaration usage tuple1H2W, selected
/// limits1H3W, original input1H5R3W and returned Ok1H1R1W. The existing wiring,
/// supplied value, full binder and final Local assembly are separate holdings.
pub fn local_program_binding_input_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 4L, reference_slots: 6L, scalar_words: 9L, }
}

///|
/// Select the original binding limits AFTER topology usage. A staged caller
/// backs this fixed entrance before entry, then drives the existing binding
/// reader on these exact declarations/supplied input/limits before completion.
pub fn prepare_local_program_binding_input(
  wiring : ResultWiring,
  supplied : @decode.Cursor?,
  limits : LocalProgramLimits,
) -> Result[LocalProgramBindingInput, LocalSourceIssue] {
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
  Ok({
    wiring,
    supplied,
    limits,
    used,
    binding_limits: {
      max_nodes: limits.max_nodes - used.nodes - decl_nodes,
      max_text_bytes: limits.max_text_bytes - used.text_bytes - decl_text,
      max_depth: limits.max_depth,
    },
    declaration_nodes: decl_nodes,
    declaration_text: decl_text,
    available: true,
  })
}

///|
/// Borrow the SAME original Source and input, with its selected binding limits.
/// No read, copy, physical backing or validation is performed by this getter.
pub fn local_program_binding_input_facts(
  original : LocalProgramBindingInput,
) -> (@parameters.Source, @decode.Cursor?, @value.Limits)? {
  if original.available {
    Some((original.wiring.source, original.supplied, original.binding_limits))
  } else {
    None
  }
}

///|
/// Consume only a completed original reader with the existing correspondence
/// rule. Pending, foreign, changed or incompatible-limit readers do not start
/// another binding pass. The wiring and its physical Source remain unchanged.
pub fn bind_prepared_program_from_binding(
  original : LocalProgramBindingInput,
  binding : @binding.BindingReadInput,
) -> Result[PreparedLocalSource, LocalSourceIssue] {
  if !original.available {
    return Err(MissingPreparation)
  }
  match
    @binding.reuse_binding_read(
      binding,
      @parameters.declarations(original.wiring.source),
      original.supplied,
      original.binding_limits,
    ) {
    None => Err(MissingPreparation)
    Some(completed) => finish_local_program_binding_input(original, completed)
  }
}

///|
/// Retire this pure continuation after its original constructor has unwound.
/// Its borrowed topology and another legitimate successor stay independent.
pub fn retire_local_program_binding_input(
  original : LocalProgramBindingInput,
) -> Unit {
  original.available = false
}

///|
fn finish_local_program_binding_input(
  original : LocalProgramBindingInput,
  completed : Result[@binding.BindingResult, @binding.Issue],
) -> Result[PreparedLocalSource, LocalSourceIssue] {
  if !original.available {
    return Err(MissingPreparation)
  }
  original.available = false
  let bound = match completed {
    Ok(v) => v
    Err(e) => return Err(Binding(e))
  }
  let (bind_nodes, bind_text) = @binding.binding_usage(bound)
  let values = match bound {
    Ready(v) => v
    NeedsBindings(missing) => return Err(NeedsBindings(missing))
  }
  finish_local_source(
    original.wiring,
    original.used,
    values,
    original.declaration_nodes,
    original.declaration_text,
    bind_nodes,
    bind_text,
    original.limits,
  )
}
