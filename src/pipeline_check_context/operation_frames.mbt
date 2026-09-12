///|
pub(all) enum OperationFrameIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  InvalidFrame(Int)
  Scalar(OperationScalarIssue)
} derive(Eq, Debug)

///|
pub struct OperationFrameResolution {
  requirement_index : Int
  site : OperationRequirementSite
  frame : @relation.RowsFrame
  start_distance : Int64
  end_distance : Int64
  start_parameter : @parameter.BoundParameter?
  end_parameter : @parameter.BoundParameter?
}

///|
struct ProgramOperationFrames {
  scalars : ProgramOperationScalars
  entries : Array[OperationFrameResolution]
  work : Int
}

///|
fn frame_distance(
  distance : @relation.CountValue,
  visit : ParameterVisit,
  index : Int,
  budget : OperationScalarBudget,
) -> (Int64, @parameter.BoundParameter?) raise OperationScalarStop {
  scalar_spend(budget, 1)
  match distance {
    Literal(n) => (n, None)
    Parameter(name) => {
      let parameter = operation_scalar_parameter(visit, name, index, budget)
      let demand = @pipeline.SafeInteger(name, minimum=1L)
      guard operation_scalar_value(parameter.value.value, demand)
        is Some(Integer(n)) else {
        raise OperationScalarStop(InvalidValue(index, demand))
      }
      (n, Some(parameter))
    }
  }
}

///|
/// Close the relative order of symbolic ROWS boundaries using the same owned
/// bindings as scalar admission. This does not resolve row data or frame demand.
pub fn check_program_operation_frames(
  scalars : ProgramOperationScalars,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationFrames, OperationFrameIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if scalars.work >= max_work {
    return Err(BudgetExceeded)
  }
  let budget = { remaining: max_work - scalars.work - 1, }
  let requirements = scalars.orders.requirements
  let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let entries : Array[OperationFrameResolution] = []
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(budget, 1)
      let site = requirements.entries[i]
      let pending = match site.requirement {
        RelationRequirement(v) if v.kind is @relation.BoundFrameOrder => v
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
      guard @relation.analytic(operation).bind(a => @relation.analytic_frame(a))
        is Some(frame) else {
        return Err(ForeignOwner(i))
      }
      if !physical_equal(frame.source, pending.source) {
        return Err(ForeignOwner(i))
      }
      let (a, z, preceding) = match (frame.start, frame.end) {
        (Preceding(a), Preceding(z)) => (a, z, true)
        (Following(a), Following(z)) => (a, z, false)
        _ => return Err(InvalidFrame(i))
      }
      let (start_distance, start_parameter) = frame_distance(
        a, visit, i, budget,
      )
      let (end_distance, end_parameter) = frame_distance(z, visit, i, budget)
      if (preceding && start_distance < end_distance) ||
        (!preceding && start_distance > end_distance) {
        return Err(InvalidFrame(i))
      }
      entries.push({
        requirement_index: i,
        site,
        frame,
        start_distance,
        end_distance,
        start_parameter,
        end_parameter,
      })
    }
    Ok({ scalars, entries, work: max_work - budget.remaining, })
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(issue) => Err(Scalar(issue))
  }
}

///|
pub fn operation_frames_scalars(
  v : ProgramOperationFrames,
) -> ProgramOperationScalars {
  v.scalars
}

///|
pub fn operation_frames_count(v : ProgramOperationFrames) -> Int {
  v.entries.length()
}

///|
pub fn operation_frame_at(
  v : ProgramOperationFrames,
  index : Int,
) -> OperationFrameResolution? {
  v.entries.get(index)
}

///|
pub fn operation_frames_work(v : ProgramOperationFrames) -> Int {
  v.work
}
