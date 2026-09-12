///|
pub(all) enum OperationRequirementsIssue {
  InvalidLimits
  BudgetExceeded
} derive(Eq, Debug)

///|
/// Coordinates belong to this exact preparation, not to a durable identity.
pub struct OperationRequirementSite {
  stage : Int
  producer_visit : Int
  step : Int
  group : Int
  index : Int
  pipeline : @pipeline.CheckedPipeline
  obligations : @pipeline.OperationObligations
  requirement : @pipeline.OperationObligation
}

///|
struct ProgramOperationRequirements {
  expressions : ProgramExpressionClosure
  entries : Array[OperationRequirementSite]
  work : Int
}

///|
/// Collect requirements from all owned producer visits, including unused steps.
/// This is an inventory, not discharge or permission to defer static errors.
pub fn collect_program_operation_requirements(
  expressions : ProgramExpressionClosure,
  max_work : Int,
  max_requirements : Int,
) -> Result[ProgramOperationRequirements, OperationRequirementsIssue] {
  if max_work < 0 || max_requirements < 0 {
    return Err(InvalidLimits)
  }
  let mut work = expressions.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let preparation = expressions.identity.sources.operations.preparation
  let stages = preparation.profiles.context.selected.context.wired.stages
  let entries : Array[OperationRequirementSite] = []
  for stage in 0..<stages.contexts.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let visits = stages.contexts[stage].visits
    for producer_visit in 0..<visits.length() {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let pipeline = @parameter_slots.pipeline(visits[producer_visit].collected)
      for step in 0..<@pipeline.step_count(pipeline) {
        if work == max_work {
          return Err(BudgetExceeded)
        }
        work += 1
        let operation = @pipeline.step_at(pipeline, step).unwrap().operation
        let groups = @pipeline.operation_obligation_group_count(operation)
        for group in 0..<groups {
          if work == max_work {
            return Err(BudgetExceeded)
          }
          work += 1
          let obligations = @pipeline.operation_obligation_group_at(
            operation, group,
          ).unwrap()
          let n = @pipeline.operation_obligations_count(obligations)
          if n > max_work - work || n > max_requirements - entries.length() {
            return Err(BudgetExceeded)
          }
          work += n
          for index in 0..<n {
            let requirement = @pipeline.operation_obligations_at(
              obligations, index,
            ).unwrap()
            entries.push({
              stage,
              producer_visit,
              step,
              group,
              index,
              pipeline,
              obligations,
              requirement,
            })
          }
        }
      }
    }
  }
  Ok({ expressions, entries, work, })
}

///|
pub fn operation_requirements_expressions(
  v : ProgramOperationRequirements,
) -> ProgramExpressionClosure {
  v.expressions
}

///|
pub fn operation_requirements_count(v : ProgramOperationRequirements) -> Int {
  v.entries.length()
}

///|
pub fn operation_requirements_at(
  v : ProgramOperationRequirements,
  index : Int,
) -> OperationRequirementSite? {
  v.entries.get(index)
}

///|
pub fn operation_requirements_work(v : ProgramOperationRequirements) -> Int {
  v.work
}
