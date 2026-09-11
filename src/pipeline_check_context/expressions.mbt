///|
pub struct ExpressionRequirement {
  visit : Int
  step : Int
  slot : Int
  consumer : @pipeline.ExpressionConsumer
  filter : @pipeline.ExpressionFilter?
  expression : @typing.TypedExpression
  obligation : @typing.Obligation
}

///|
pub(all) enum ExpressionRequirementIssue {
  WorkLimit(Int)
  Slots(Int, @pipeline.ExpressionSlotIssue)
}

///|
priv struct ExpressionRequirements {
  entries : Array[ExpressionRequirement]
  work : Int
}

///|
// All local typed expression slots are enumerated for every producer visit.
// No returned array from an individual expression is copied before charging it.
fn collect_expression_requirements(
  closure : @pipeline.ContextualClosure,
  max_work : Int,
) -> Result[ExpressionRequirements, ExpressionRequirementIssue] {
  let mut work = 0
  let entries : Array[ExpressionRequirement] = []
  for visit in 0..<@pipeline.contextual_closure_count(closure) {
    if work >= max_work {
      return Err(WorkLimit(visit))
    }
    work += 1
    let pipeline = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(closure, visit).unwrap(),
    )
    let slots = match
      @pipeline.collect_expression_slots(
        pipeline,
        max_work=max_work - work,
        max_slots=max_work - work,
      ) {
      Ok(v) => v
      Err(e) => return Err(Slots(visit, e))
    }
    work += @pipeline.expression_slots_work(slots)
    for i in 0..<@pipeline.expression_slot_count(slots) {
      if work >= max_work {
        return Err(WorkLimit(visit))
      }
      work += 1
      let slot = @pipeline.expression_slot_at(slots, i).unwrap()
      let n = @typing.pending_validation_count(slot.expression)
      if n > max_work - work {
        return Err(WorkLimit(visit))
      }
      work += n
      for j in 0..<n {
        entries.push({
          visit,
          step: slot.step,
          slot: i,
          consumer: slot.consumer,
          filter: slot.filter,
          expression: slot.expression,
          obligation: @typing.pending_validation_at(slot.expression, j).unwrap(),
        })
      }
    }
  }
  Ok({ entries, work, })
}

///|
/// Outstanding static expression requirements, not completed runtime checks.
pub fn expression_requirement_count(v : PipelineContext) -> Int {
  v.expressions.entries.length()
}

///|
pub fn expression_requirement_at(
  v : PipelineContext,
  index : Int,
) -> ExpressionRequirement? {
  v.expressions.entries.get(index)
}

///|
pub fn expression_requirement_work(v : PipelineContext) -> Int {
  v.expressions.work
}
