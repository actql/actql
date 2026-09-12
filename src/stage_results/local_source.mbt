///|
/// Source-owned Local preparation, not complete static closure or execution
/// permission. Future imports retain declared ports, not observed values.
struct PreparedLocalSource {
  source : @parameters.Source
  values : @binding.BoundValues
  wiring : ResultWiring
  usage : LocalProgramUsage
}

///|
pub enum LocalSourceIssue {
  InvalidLimits
  BudgetExceeded
  Declarations(@parameters.Issue)
  Binding(@binding.Issue)
  NeedsBindings(@binding.MissingNames)
  Program(LocalProgramIssue)
}

///|
/// Derive declarations and effective Parameters from the retained Program before
/// constructing Local topology. Admission nodes/text are shared with topology;
/// work additionally charges the Stage copy and the final owner assembly.
pub fn prepare_local_source(
  program : @syntax.Program,
  supplied : @decode.Cursor?,
  max_parameters~ : Int,
  limits : LocalProgramLimits,
) -> Result[PreparedLocalSource, LocalSourceIssue] {
  if max_parameters < 0 ||
    limits.max_stages < 0 ||
    limits.max_steps < 0 ||
    limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_tokens < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let count = @syntax.stage_count(program)
  if count > limits.max_stages || count >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let source = match
    @parameters.prepare(program, {
      max_parameters,
      max_nodes: limits.max_nodes,
      max_text_bytes: limits.max_text_bytes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Declarations(e))
  }
  let declarations = @parameters.declarations(source)
  let (decl_nodes, decl_text) = @binding.declaration_usage(declarations)
  let bound = match
    @binding.bind(declarations, supplied, {
      max_nodes: limits.max_nodes - decl_nodes,
      max_text_bytes: limits.max_text_bytes - decl_text,
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
  let (wiring, used) = match
    prepare_local_program(source, {
      ..limits,
      max_work: limits.max_work - count - 1,
      max_nodes: limits.max_nodes - decl_nodes - bind_nodes,
      max_text_bytes: limits.max_text_bytes - decl_text - bind_text,
    }) {
    Ok(v) => v
    Err(e) => return Err(Program(e))
  }
  Ok({
    source,
    values,
    wiring,
    usage: {
      ..used,
      work: used.work + count + 1,
      nodes: used.nodes + decl_nodes + bind_nodes,
      text_bytes: used.text_bytes + decl_text + bind_text,
    },
  })
}

///|
pub fn local_source_source(v : PreparedLocalSource) -> @parameters.Source {
  v.source
}

///|
pub fn local_source_values(v : PreparedLocalSource) -> @binding.BoundValues {
  v.values
}

///|
pub fn local_source_wiring(v : PreparedLocalSource) -> ResultWiring {
  v.wiring
}

///|
pub fn local_source_usage(v : PreparedLocalSource) -> LocalProgramUsage {
  v.usage
}
