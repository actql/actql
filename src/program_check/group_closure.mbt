///|
// Construct before exposing CheckedProgram. Imported visits do not acquire a
// second consumer-owned identity for the producer's aggregate restriction.
fn prepare_program_group_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> Array[Array[GroupLimit]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let seen : Map[(Int, Int, String), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is EnforceArrayItems(selected) else {
      continue
    }
    guard units.get(check.site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, check.site.pipeline) {
      continue
    }
    let call = @context.group_array_limit_call(selected)
    let name = @relation.aggregate_name(call)
    identity_charge(remaining, name.length())
    let key = (check.site.stage, check.site.step, name)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    guard unit_operation_source(unit, check.site.pipeline, check.site.step)
      is Some(operation) else {
      raise ForeignOwner
    }
    let source = GroupAggregateSource::{ operation, call, scope: "items", }
    let limit = assemble_group_array_limit(
      units,
      source,
      selected,
      remaining,
      conversion~,
    )
    identity_charge(remaining, 1)
    result[check.site.stage].push(limit)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_group_limit_count(program : CheckedProgram, stage : Int) -> Int? {
  program.group_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_group_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> GroupLimit? {
  program.group_limits.get(stage).bind(v => v.get(index))
}
