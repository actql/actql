///|
pub enum PipelineAuthoringIssue {
  InvalidLimits
  BudgetExceeded
  ExpressionSlots(@pipeline.ExpressionSlotIssue)
  UnsupportedOperation(Int)
  PendingExpression(Int, @typing.Obligation)
  PendingOperation(Int, @pipeline.OperationObligations, Int)
}

///|
pub struct AuthoringRuntimeRequirement {
  step : Int
  owner : @pipeline.OperationObligations
  index : Int
}

///|
struct PipelineAuthoringClosure {
  profiles : PipelineOperationProfileChecks
  expressions : @pipeline.ExpressionSlots
  runtime : Array[AuthoringRuntimeRequirement]
  work : Int
}

///|
/// Close the static obligations of the currently connected Values/Derive/Select
/// path using its actual checked operation, expression and profile owners.
/// Recognized value/resource obligations retain their later execution owners.
/// Other operation or pending-expression paths remain unresolved, never a
/// smaller successful scope. This is not a whole-Program template certificate.
pub fn close_pipeline_authoring(
  profiles : PipelineOperationProfileChecks,
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
          Derive | Select => ()
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
      if n > max_work - work || n > max_requirements - runtime.length() {
        return Err(BudgetExceeded)
      }
      work += n
      for index in 0..<n {
        match @pipeline.operation_obligations_at(owner, index).unwrap() {
          @pipeline.ValuesRequirement(@values.BindCell(_))
          | @pipeline.ValuesRequirement(@values.ResolvePublicationResources) =>
            runtime.push({ step, owner, index, })
          _ => return Err(PendingOperation(step, owner, index))
        }
      }
    }
  }
  Ok({ profiles, expressions, runtime, work, })
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
pub fn pipeline_authoring_work(value : PipelineAuthoringClosure) -> Int {
  value.work
}
