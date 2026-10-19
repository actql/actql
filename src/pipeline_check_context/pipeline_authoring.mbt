///|
pub enum PipelineAuthoringIssue {
  InvalidLimits
  BudgetExceeded
  ExpressionSlots(@pipeline.ExpressionSlotIssue)
  UnsupportedOperation(Int)
  ForeignValues(Int)
  PendingExpression(Int, @typing.Obligation)
  PendingOperation(Int, @pipeline.OperationObligations, Int)
}

///|
pub struct AuthoringRuntimeRequirement {
  step : Int
  owner : @pipeline.OperationObligations
  index : Int
  priv group_rule : GroupExecutionRule?
}

///|
priv struct AuthoringOrderRequirement {
  step : Int
  owner : @pipeline.OperationObligations
  index : Int
  demand : @pipeline.OperationOrderDemand
}

///|
struct PipelineAuthoringClosure {
  profiles : PipelineOperationProfileChecks
  capacity : @environment.Capacity
  expressions : @pipeline.ExpressionSlots
  runtime : Array[AuthoringRuntimeRequirement]
  resources : Array[AuthoringValuesPublicationCheck]
  orders : Array[AuthoringOrderRequirement]
  work : Int
}

///|
/// Close connected pipeline obligations using actual expression/profile owners
/// and completed static Values resource selection. An unresolved resource site
/// cannot become a runtime-only requirement. Bound-value obligations retain
/// their later execution owners.
/// Other operation or pending-expression paths remain unresolved, never a
/// smaller successful scope. This is not a whole-Program template certificate.
pub fn close_pipeline_authoring(
  profiles : PipelineOperationProfileChecks,
  capacity : @environment.Capacity,
  resources : Array[AuthoringValuesPublicationCheck],
  max_work : Int,
  max_slots : Int,
  max_requirements : Int,
) -> Result[PipelineAuthoringClosure, PipelineAuthoringIssue] {
  if max_work < 0 || max_slots < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let pipeline = profiles.pipeline
  let mut work = profiles.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let by_step : Map[Int, AuthoringValuesPublicationCheck] = Map([])
  if resources.length() > max_work - work {
    return Err(BudgetExceeded)
  }
  work += resources.length()
  for resource in resources {
    let step = authoring_values_step(resource)
    if !physical_equal(authoring_values_profiles(resource), profiles) ||
      !physical_equal(authoring_values_capacity(resource), capacity) ||
      by_step.contains(step) {
      return Err(ForeignValues(step))
    }
    let used = resource.work - profiles.work
    if used > max_work - work {
      return Err(BudgetExceeded)
    }
    work += used
    by_step[step] = resource
  }
  let expressions = match
    @pipeline.collect_expression_slots(
      pipeline,
      max_work=max_work - work,
      max_slots~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ExpressionSlots(issue))
  }
  work += @pipeline.expression_slots_work(expressions)
  let expression_count = @pipeline.expression_slot_count(expressions)
  if expression_count > max_work - work {
    return Err(BudgetExceeded)
  }
  work += expression_count
  for i in 0..<expression_count {
    let slot = @pipeline.expression_slot_at(expressions, i).unwrap()
    if @typing.pending_validation_at(slot.expression, 0) is Some(obligation) {
      return Err(PendingExpression(slot.step, obligation))
    }
  }
  let runtime : Array[AuthoringRuntimeRequirement] = []
  let orders : Array[AuthoringOrderRequirement] = []
  for step in 0..<@pipeline.step_count(pipeline) {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let operation = @pipeline.step_at(pipeline, step).unwrap().operation
    match operation {
      @pipeline.Values(_) => ()
      @pipeline.Unary(value) =>
        match @relation.operation(value) {
          Derive | Select | Filter | Rename | Drop | Sort | Take | Distinct | Group =>
            ()
          _ => return Err(UnsupportedOperation(step))
        }
      _ => return Err(UnsupportedOperation(step))
    }
    let count = @pipeline.operation_obligation_group_count(operation)
    if count > max_work - work {
      return Err(BudgetExceeded)
    }
    work += count
    for group in 0..<count {
      let owner = @pipeline.operation_obligation_group_at(operation, group).unwrap()
      let n = @pipeline.operation_obligations_count(owner)
      if n > max_work - work ||
        n > max_requirements - runtime.length() - orders.length() {
        return Err(BudgetExceeded)
      }
      work += n
      for index in 0..<n {
        let requirement = @pipeline.operation_obligations_at(owner, index).unwrap()
        if @pipeline.operation_order_demand(requirement) is Some(demand) {
          orders.push({ step, owner, index, demand, })
          continue
        }
        // Only the existing Take binding demand can survive this authoring
        // boundary. The exact obligation owner/index remains retained; no
        // representative value or declaration default discharges it.
        if operation is @pipeline.Unary(value) &&
          @relation.operation(value) == Take &&
          @pipeline.operation_scalar_demand(requirement)
          is Some(@pipeline.SafeInteger(_, ..)) {
          runtime.push({ step, owner, index, group_rule: None, })
          continue
        }
        // Retain only checks selected by the same Group execution owner used
        // during bound compilation. Their input observations and enforcement
        // remain future work; a binding condition or resource limit is not an
        // execution rule merely because it belongs to a Group operation.
        if operation is @pipeline.Unary(value) &&
          @relation.operation(value) == Group &&
          @relation.group(value) is Some(group) &&
          requirement is @pipeline.RelationRequirement(pending) {
          match select_group_execution_rule(group, index, pending.kind, step) {
            Ok(Some(rule)) => {
              runtime.push({ step, owner, index, group_rule: Some(rule), })
              continue
            }
            Err(_) => return Err(PendingOperation(step, owner, index))
            Ok(None) => ()
          }
        }
        match requirement {
          @pipeline.ValuesRequirement(@values.BindCell(_)) =>
            runtime.push({ step, owner, index, group_rule: None, })
          @pipeline.ValuesRequirement(@values.ResolvePublicationResources) =>
            if !by_step.contains(step) {
              return Err(PendingOperation(step, owner, index))
            }
          _ => return Err(PendingOperation(step, owner, index))
        }
      }
    }
  }
  Ok({
    profiles,
    capacity,
    expressions,
    runtime,
    resources: resources.copy(),
    orders,
    work,
  })
}

///|
pub fn pipeline_authoring_profiles(
  value : PipelineAuthoringClosure,
) -> PipelineOperationProfileChecks {
  value.profiles
}

///|
pub fn pipeline_authoring_expressions(
  value : PipelineAuthoringClosure,
) -> @pipeline.ExpressionSlots {
  value.expressions
}

///|
pub fn pipeline_authoring_runtime_count(
  value : PipelineAuthoringClosure,
) -> Int {
  value.runtime.length()
}

///|
pub fn pipeline_authoring_runtime_at(
  value : PipelineAuthoringClosure,
  index : Int,
) -> AuthoringRuntimeRequirement? {
  value.runtime.get(index)
}

///|
/// A retained Group rule is a static selection for this original requirement,
/// not an observation of input rows or evidence that the rule was enforced.
pub fn authoring_runtime_group_rule(
  value : AuthoringRuntimeRequirement,
) -> GroupExecutionRule? {
  value.group_rule
}

///|
pub fn pipeline_authoring_work(value : PipelineAuthoringClosure) -> Int {
  value.work
}

///|
pub fn pipeline_authoring_values_count(value : PipelineAuthoringClosure) -> Int {
  value.resources.length()
}

///|
pub fn pipeline_authoring_values_at(
  value : PipelineAuthoringClosure,
  index : Int,
) -> AuthoringValuesPublicationCheck? {
  value.resources.get(index)
}

///|
pub fn pipeline_authoring_capacity(
  value : PipelineAuthoringClosure,
) -> @environment.Capacity {
  value.capacity
}
