///|
/// A per-frame call scope, not a future frame observation or admitted proof.
pub struct AnalyticAggregateSource {
  operation : UnitOperationSource
  call : @relation.AnalyticCall
  scope : String
}

///|
pub fn unit_analytic_aggregate_source_at(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  index : Int,
) -> AnalyticAggregateSource? {
  guard program.units.get(stage) is Some(unit) &&
    unit_operation_source(unit, unit.pipeline, step) is Some(location) &&
    @pipeline.step_at(unit.pipeline, step) is Some(checked) &&
    checked.operation is @pipeline.Unary(operation) &&
    @relation.analytic(operation) is Some(analytic) &&
    @relation.analytic_call_at(analytic, index) is Some(call) &&
    call.function is @relation.Aggregate(aggregate) else {
    return None
  }
  let scope = match @relation.aggregate_function(aggregate) {
    ArrayAgg => "items"
    StringAgg => "bytes"
    _ => return None
  }
  Some({ operation: location, call, scope, })
}

///|
pub fn analytic_aggregate_subject(
  source : AnalyticAggregateSource,
  max_work : Int,
) -> String raise UnitBuildFailure {
  let budget = IdentityBudget::{ work: max_work, bytes: 0, nodes: 0, depth: 0, }
  for _ in 0..<4 {
    identity_charge(budget, source.call.name.length())
  }
  identity_charge(budget, 32)
  let prefix = unit_operation_subject(source.operation, budget)
  let token = source.call.name
    .replace(old="~", new="~0")
    .replace(old="/", new="~1")
  prefix + "/analytic/functions/" + token + "/" + source.scope
}
