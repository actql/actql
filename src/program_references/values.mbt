///|
struct ParameterValues {
  usage : DeclarationUsage
  values : @parameter.BoundValues
  program : @parameters.BoundIndex
  stages : Array[@parameters.BoundIndex]
  work : Int
}

///|
/// Bind all local projections atomically to one already admitted value set.
/// Opaque bindings and Program execution admission remain separate.
pub fn bind_parameter_values(
  usage : DeclarationUsage,
  values : @parameter.BoundValues,
  max_work~ : Int,
) -> Result[ParameterValues, @parameters.BindingIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let inventory = usage.inventory
  if !physical_equal(
      @parameters.declarations(inventory.program.parameters),
      @parameter.bound_declarations(values),
    ) {
    return Err(ForeignDeclarations)
  }
  if usage.work > max_work {
    return Err(WorkLimit)
  }
  let mut remaining = max_work - usage.work
  let prepared = match @parameters.prepare_values(values, max_work=remaining) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  remaining -= @parameters.prepared_work(prepared)
  let program = match
    @parameters.bind_prepared(
      inventory.program.parameters,
      prepared,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(issue) => return Err(issue)
  }
  remaining -= @parameters.binding_work(program)
  let stages = []
  for stage in inventory.locals {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let bound = match
      @parameters.bind_prepared(stage.parameters, prepared, max_work=remaining) {
      Ok(v) => v
      Err(issue) => return Err(issue)
    }
    remaining -= @parameters.binding_work(bound)
    stages.push(bound)
  }
  Ok({ usage, values, program, stages, work: max_work - remaining, })
}

///|
pub fn parameter_usage(value : ParameterValues) -> DeclarationUsage {
  value.usage
}

///|
pub fn parameter_values(value : ParameterValues) -> @parameter.BoundValues {
  value.values
}

///|
pub fn program_parameter_values(
  value : ParameterValues,
) -> @parameters.BoundIndex {
  value.program
}

///|
pub fn stage_parameter_values(
  value : ParameterValues,
  index : Int,
) -> @parameters.BoundIndex? {
  value.stages.get(index)
}

///|
pub fn parameter_work(value : ParameterValues) -> Int {
  value.work
}
