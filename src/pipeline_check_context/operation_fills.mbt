///|
pub(all) enum OperationFillIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  InvalidFill(Int)
  Scalar(OperationScalarIssue)
} derive(Eq, Debug)

///|
pub struct OperationFillResolution {
  requirement_index : Int
  site : OperationRequirementSite
  pivot : @relation.CheckedPivot
  parameter : @parameter.BoundParameter
  target : @contract.Contract
}

///|
struct ProgramOperationFills {
  frames : ProgramOperationFrames
  entries : Array[OperationFillResolution]
  work : Int
}

///|
// Reserve traversal and complete name comparisons before the type relation.
// Child slots are charged before allocating the explicit nonrecursive stack.
fn fill_contract_cost(
  c : @contract.Contract,
  b : OperationScalarBudget,
) -> Unit raise OperationScalarStop {
  scalar_spend(b, 1)
  let pending = [c]
  while !pending.is_empty() {
    let c = pending.pop().unwrap()
    match c.shape {
      Array(child, ..) => {
        scalar_spend(b, 1)
        pending.push(child)
      }
      Object(fields) => {
        let count = @contract.field_count(fields)
        scalar_spend(b, count)
        for i in 0..<count {
          let field = @contract.field_at(fields, i).unwrap()
          scalar_spend(b, field.name.length())
          pending.push(field.contract)
        }
      }
      ResourceRef(resource_kind~) => scalar_spend(b, resource_kind.length())
      ArtifactRef(media_type=Some(text)) => scalar_spend(b, text.length())
      _ => ()
    }
  }
}

///|
/// Reuse admitted typed values, without reconstructing a wire value or applying
/// coercion. The source declaration and pivot must belong to the owned Program.
pub fn check_program_operation_fills(
  frames : ProgramOperationFrames,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationFills, OperationFillIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if frames.work >= max_work {
    return Err(BudgetExceeded)
  }
  let budget = { remaining: max_work - frames.work - 1, }
  let requirements = frames.scalars.orders.requirements
  let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let entries : Array[OperationFillResolution] = []
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(budget, 1)
      let site = requirements.entries[i]
      let (pending, name) = match site.requirement {
        RelationRequirement(v) =>
          match v.kind {
            BoundFill(name) => (v, name)
            _ => continue
          }
        _ => continue
      }
      if entries.length() == max_resolutions {
        return Err(BudgetExceeded)
      }
      let visit = stages.contexts[site.stage].visits[site.producer_visit]
      if !physical_equal(
          @parameter_slots.pipeline(visit.collected),
          site.pipeline,
        ) {
        return Err(ForeignOwner(i))
      }
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
        return Err(ForeignOwner(i))
      }
      guard step.operation is @pipeline.Unary(operation) else {
        return Err(ForeignOwner(i))
      }
      guard @relation.pivot(operation) is Some(pivot) else {
        return Err(ForeignOwner(i))
      }
      guard @relation.pivot_fill(pivot)
        is Some(Parameter(fill_name, contract=declared, source~)) else {
        return Err(ForeignOwner(i))
      }
      scalar_spend(budget, name.length())
      scalar_spend(budget, fill_name.length())
      if name != fill_name || !physical_equal(source, pending.source) {
        return Err(ForeignOwner(i))
      }
      let parameter = operation_scalar_parameter(visit, name, i, budget)
      let actual = parameter.value.contract
      let target = @relation.pivot_result(pivot)
      fill_contract_cost(actual, budget)
      fill_contract_cost(declared, budget)
      fill_contract_cost(actual, budget)
      fill_contract_cost(target, budget)
      // Binding admission already checked every value against actual. These
      // bounded type relations transfer that evidence, not a caller's assertion.
      let (declared_ok, used) = @contract.assignable_usage(
        actual,
        declared,
        budget.remaining,
      ) catch {
        _ => return Err(BudgetExceeded)
      }
      scalar_spend(budget, used)
      let (target_ok, used) = @contract.assignable_usage(
        actual,
        target,
        budget.remaining,
      ) catch {
        _ => return Err(BudgetExceeded)
      }
      scalar_spend(budget, used)
      if !declared_ok || !target_ok {
        return Err(InvalidFill(i))
      }
      entries.push({ requirement_index: i, site, pivot, parameter, target, })
    }
    Ok({ frames, entries, work: max_work - budget.remaining, })
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(issue) => Err(Scalar(issue))
  }
}

///|
pub fn operation_fills_frames(
  v : ProgramOperationFills,
) -> ProgramOperationFrames {
  v.frames
}

///|
pub fn operation_fills_count(v : ProgramOperationFills) -> Int {
  v.entries.length()
}

///|
pub fn operation_fill_at(
  v : ProgramOperationFills,
  index : Int,
) -> OperationFillResolution? {
  v.entries.get(index)
}

///|
pub fn operation_fills_work(v : ProgramOperationFills) -> Int {
  v.work
}
