///|
priv enum ValuesResourceSource {
  BoundCells(ProgramOperationCells, Int, OperationRequirementSite)
  Authored(PipelineOperationProfileChecks, Int, @environment.Capacity)
}

///|
/// The same resource occurrence before or after actual cell binding. Neither
/// source variant asserts that static resource admission has completed.
struct ValuesResourceOwner {
  source : ValuesResourceSource
  values : @values.CheckedValues
}

///|
fn bound_values_resource_owner(
  cells : ProgramOperationCells,
  requirement_index : Int,
) -> Result[ValuesResourceOwner, ValuesMeasurementIssue] {
  guard cells.requirements.entries.get(requirement_index) is Some(site) else {
    return Err(InvalidRequirement)
  }
  guard site.requirement
    is @pipeline.ValuesRequirement(@values.ResolvePublicationResources) else {
    return Err(InvalidRequirement)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Values(values) else {
    return Err(ForeignOwner)
  }
  if site.index != 0 ||
    @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body {
    return Err(ForeignOwner)
  }
  Ok({ source: BoundCells(cells, requirement_index, site), values, })
}

///|
fn authored_values_resource_owner(
  profiles : PipelineOperationProfileChecks,
  step_index : Int,
  capacity : @environment.Capacity,
) -> Result[ValuesResourceOwner, ValuesMeasurementIssue] {
  guard @pipeline.step_at(profiles.pipeline, step_index) is Some(step) &&
    step.operation is @pipeline.Values(values) else {
    return Err(InvalidRequirement)
  }
  Ok({ source: Authored(profiles, step_index, capacity), values, })
}

///|
fn values_resource_pipeline(
  owner : ValuesResourceOwner,
) -> @pipeline.CheckedPipeline {
  match owner.source {
    BoundCells(_, _, site) => site.pipeline
    Authored(profiles, _, _) => profiles.pipeline
  }
}

///|
fn values_resource_step(owner : ValuesResourceOwner) -> Int {
  match owner.source {
    BoundCells(_, _, site) => site.step
    Authored(_, step, _) => step
  }
}

///|
fn values_resource_policy(owner : ValuesResourceOwner) -> @policy.Policy {
  let capacity = match owner.source {
    BoundCells(cells, _, _) => cells.requirements.capacity
    Authored(_, _, capacity) => capacity
  }
  @environment.capacity_policy(capacity)
}

///|
fn values_resource_cell(
  owner : ValuesResourceOwner,
  row : @values.Row,
  row_index : Int,
  column : Int,
  next_binding : Int,
) -> Result[(@value.CheckedValue, Int), ValuesMeasurementIssue] {
  match owner.source {
    BoundCells(cells, index, site) =>
      resolved_values_cell(
        cells,
        site,
        owner.values,
        index,
        row,
        row_index,
        column,
        next_binding,
      )
    Authored(_, _, _) =>
      match @values.cell_at(row, column).unwrap() {
        @values.Literal(value, ..) => Ok((value, next_binding))
        @values.Parameter(_, ..) => Err(NeedsBinding(row_index, column))
      }
  }
}
