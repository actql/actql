///|
/// Distinct measurement sites in the canonical nest expansion.
pub(all) enum NestResourceScope {
  ChildItems
  EmptyItems
  GroupedBytes
  AttachedBytes
} derive(Eq)

///|
/// An authored nest occurrence, not an internal generated group occurrence.
pub struct NestResourceSource {
  operation : UnitOperationSource
  nest : @nest.CheckedNest
  priv owner : @context.ProgramSourceIdentity
}

///|
fn unit_nest_resource_source(
  unit : BuiltUnit,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
) -> NestResourceSource? {
  guard unit_operation_source(unit, pipeline, step) is Some(operation) &&
    @pipeline.step_at(pipeline, step) is Some(checked) &&
    checked.operation is @pipeline.Nest(checked=nest, ..) else {
    return None
  }
  Some({
    operation,
    nest,
    owner: @context.expression_closure_identity(unit.expressions),
  })
}

///|
pub fn unit_nest_resource_source_at(
  program : CheckedProgram,
  stage : Int,
  step : Int,
) -> NestResourceSource? {
  program.units
  .get(stage)
  .bind(unit => unit_nest_resource_source(unit, unit.pipeline, step))
}

///|
pub fn nest_resource_subject(
  source : NestResourceSource,
  scope : NestResourceScope,
  max_work : Int,
) -> String raise UnitBuildFailure {
  let budget = IdentityBudget::{ work: max_work, bytes: 0, nodes: 0, depth: 0, }
  nest_resource_subject_with_budget(source, scope, budget)
}

///|
fn nest_resource_subject_with_budget(
  source : NestResourceSource,
  scope : NestResourceScope,
  budget : IdentityBudget,
) -> String raise UnitBuildFailure {
  identity_charge(budget, 32)
  let prefix = unit_operation_subject(source.operation, budget)
  let suffix = match scope {
    ChildItems => "/nest/child-arrays/items"
    EmptyItems => "/nest/empty-array/items"
    GroupedBytes => "/nest/child-arrays/bytes"
    AttachedBytes => "/nest/attachment/bytes"
  }
  prefix + suffix
}

///|
/// Bounded reconstruction of one authored guard, not runtime enforcement.
pub fn unit_nest_guard_witness(
  program : CheckedProgram,
  stage : Int,
  step : Int,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
) -> @wire.WireWitness? raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  guard unit_nest_resource_source_at(program, stage, step) is Some(source) else {
    raise ForeignOwner
  }
  let closure = @context.stage_requirement_operations(requirements(program))
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(budget, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(NestItems(selected))) &&
      selected.site.stage == stage &&
      selected.site.step == step &&
      physical_equal(selected.site.pipeline, source.operation.pipeline) else {
      continue
    }
    return emit_nest_guard_witness(source, selected, budget)
  }
  raise ForeignOwner
}

///|
// The selected restriction and the source must share the original checked
// occurrence. A matching Unit CID or bound number is not ownership evidence.
fn emit_nest_guard_witness(
  source : NestResourceSource,
  selected : @context.NestItemLimit,
  budget : IdentityBudget,
) -> @wire.WireWitness? raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let owner = @context.operation_requirements_expressions(
    @context.operation_resolution_requirements(selected.owner),
  )
  guard physical_equal(selected.operation, source.nest) &&
    physical_equal(selected.site.pipeline, source.operation.pipeline) &&
    selected.site.step == source.operation.source_ordinal &&
    physical_equal(@context.expression_closure_identity(owner), source.owner) else {
    raise ForeignOwner
  }
  let witness = match selected.guard_value {
    None => None
    Some(value) => {
      identity_charge(remaining, 64)
      let path = "$.steps[" +
        source.operation.source_ordinal.to_string() +
        "].nest.max_items"
      Some(
        emit_unit_guard_witness(
          source.operation.unit_definition_cid,
          path,
          "actql.guard.nested-array-items",
          "array_items",
          value,
          remaining,
        ),
      )
    }
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  witness
}
