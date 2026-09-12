///|
/// Source-owned Local preparation, not complete static closure or execution
/// permission. Future imports retain declared ports, not observed values.
struct PreparedLocalSource {
  source : @parameters.Source
  values : @binding.BoundValues
  wiring : ResultWiring
  operations : @parameters.BoundOperations
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
  Operations(@parameters.OperationsIssue)
  OperationBindings(@parameters.BindingsIssue)
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
  let remaining = limits.max_work - count - 1 - used.work
  if count > remaining {
    return Err(BudgetExceeded)
  }
  let stages = []
  let mut shared_work = 0
  for i in 0..<count {
    let stage = stage_port_source(wiring_stage_at(wiring, i).unwrap())
    // These exact collection prefixes were charged by prepare_local_program.
    shared_work += @parameters.collection_work(stage)
    stages.push(stage)
  }
  let operation_cap = shared_work + remaining - count
  let collected = match
    @parameters.collect_prepared_operations(source, stages, {
      max_work: operation_cap,
      max_slots: limits.max_work,
      max_references: limits.max_work,
      max_pointer_units: limits.max_work,
      max_direct_text_bytes: used.text_bytes,
    }) {
    Ok(v) => v
    Err(e) => return Err(Operations(e))
  }
  let operations = match
    @parameters.bind_operations(collected, values, max_work=operation_cap) {
    Ok(v) => v
    Err(e) => return Err(OperationBindings(e))
  }
  Ok({
    source,
    values,
    wiring,
    operations,
    usage: {
      ..used,
      work: used.work +
      count +
      1 +
      count +
      (@parameters.bindings_usage(operations).work - shared_work),
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

///|
/// Operation-only references bound to this source's own effective values.
pub fn local_source_operations(
  v : PreparedLocalSource,
) -> @parameters.BoundOperations {
  v.operations
}
