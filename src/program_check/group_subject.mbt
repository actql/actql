///|
/// An owned ordinary-group resource scope, not an admitted limit or proof.
pub struct GroupAggregateSource {
  operation : UnitOperationSource
  call : @relation.CheckedAggregate
  scope : String
}

///|
fn unit_group_aggregate_source(
  unit : BuiltUnit,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  aggregate : Int,
) -> GroupAggregateSource? {
  guard unit_operation_source(unit, pipeline, step) is Some(location) &&
    @pipeline.step_at(pipeline, step) is Some(checked) &&
    checked.operation is @pipeline.Unary(operation) &&
    @relation.operation(operation) == @relation.Group &&
    @relation.group(operation) is Some(group) &&
    @relation.aggregate_at(group, aggregate) is Some(call) else {
    return None
  }
  let scope = match @relation.aggregate_function(call) {
    ArrayAgg => "items"
    StringAgg => "bytes"
    _ => return None
  }
  Some({ operation: location, call, scope, })
}

///|
pub fn unit_group_aggregate_source_at(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  aggregate : Int,
) -> GroupAggregateSource? {
  program.units
  .get(stage)
  .bind(unit => {
    unit_group_aggregate_source(unit, unit.pipeline, step, aggregate)
  })
}

///|
pub fn group_aggregate_subject(
  source : GroupAggregateSource,
  max_work : Int,
) -> String raise UnitBuildFailure {
  let budget = IdentityBudget::{ work: max_work, bytes: 0, nodes: 0, depth: 0, }
  let name = @relation.aggregate_name(source.call)
  // Charge both escaping passes at their worst-case lengths before allocating.
  for _ in 0..<4 {
    identity_charge(budget, name.length())
  }
  identity_charge(budget, 32)
  let prefix = unit_operation_subject(source.operation, budget)
  let token = name.replace(old="~", new="~0").replace(old="/", new="~1")
  prefix + "/group/aggregates/" + token + "/" + source.scope
}
