///|
pub enum WindowExecutionRule {
  AdmitTimeValues
  AssignMemberships(WindowMembershipOptions)
}

///|
/// Bound options for this execution occurrence, not an observed output bound.
pub struct WindowMembershipOptions {
  size : Int64
  step : Int64?
  offset : Int64
  maximum_per_input : Int64
  size_resolution : OperationScalarResolution?
  step_resolution : OperationScalarResolution?
  offset_resolution : OperationScalarResolution?
}

///|
pub struct WindowExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  window : @window.CheckedWindow
  rule : WindowExecutionRule
}

///|
fn window_execution_check(
  site : OperationRequirementSite,
  occurrence : Int,
  requirements : ProgramOperationRequirements,
  states : Array[OperationResolutionState],
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.WindowRequirement(_) else {
    return (Ok(None), 0)
  }
  let budget = { remaining: max_work, }
  let result = window_execution_owned(
    site, occurrence, requirements, states, budget,
  )
  (result, max_work - budget.remaining)
}

///|
fn window_execution_owned(
  site : OperationRequirementSite,
  occurrence : Int,
  requirements : ProgramOperationRequirements,
  states : Array[OperationResolutionState],
  budget : OperationScalarBudget,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.WindowRequirement(pending) else {
    return Ok(None)
  }
  match pending {
    ValidateTimeValues | CheckedWindowArithmetic => ()
    BindMilliseconds(_, _)
    | ResolveMembershipBound
    | ResolvePublicationResources => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Window(window) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @window.pending_validation_at(window, site.index) is Some(owned) &&
    owned == pending else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = if pending == @window.ValidateTimeValues {
    AdmitTimeValues
  } else {
    let options = @window.options(window)
    try {
      let (size, size_resolution) = window_milliseconds(
        @window.size(options),
        site,
        occurrence,
        requirements,
        states,
        budget,
      )
      let (step, step_resolution) = match @window.step(options) {
        Some(value) => {
          let (n, resolution) = window_milliseconds(
            value, site, occurrence, requirements, states, budget,
          )
          (Some(n), resolution)
        }
        None => (None, None)
      }
      let (offset, offset_resolution) = window_milliseconds(
        @window.offset(options),
        site,
        occurrence,
        requirements,
        states,
        budget,
      )
      let maximum_per_input = if @window.kind(options) == @window.Fixed {
        1L
      } else {
        let divisor = step.unwrap()
        size / divisor + (if size % divisor == 0L { 0L } else { 1L })
      }
      AssignMemberships({
        size,
        step,
        offset,
        maximum_per_input,
        size_resolution,
        step_resolution,
        offset_resolution,
      })
    } catch {
      OperationScalarStop(BudgetExceeded) => return Err(BudgetExceeded)
      OperationScalarStop(_) => return Err(ForeignOccurrence(occurrence))
    }
  }
  Ok(Some(WindowExecution({ site, step, input, window, rule, })))
}

///|
// Requirement groups are stored contiguously without dropping scalar slots.
// Search only this exact group and retain the original scalar resolution.
fn window_milliseconds(
  value : @window.Milliseconds,
  site : OperationRequirementSite,
  occurrence : Int,
  requirements : ProgramOperationRequirements,
  states : Array[OperationResolutionState],
  budget : OperationScalarBudget,
) -> (Int64, OperationScalarResolution?) raise OperationScalarStop {
  scalar_spend(budget, 1)
  guard value is @window.Parameter(name, domain~, ..) else {
    guard value is @window.Literal(n) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    return (n, None)
  }
  let start = occurrence - site.index
  for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
    scalar_spend(budget, 1)
    let i = start + slot
    guard requirements.entries.get(i) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      expected.step == site.step &&
      physical_equal(expected.obligations, site.obligations) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    guard expected.requirement
      is @pipeline.WindowRequirement(
        @window.BindMilliseconds(candidate, candidate_domain)
      ) else {
      continue
    }
    scalar_spend(budget, name.length())
    scalar_spend(budget, candidate.length())
    if name != candidate || domain != candidate_domain {
      continue
    }
    guard states.get(i) is Some(Resolved(Scalar(resolution))) &&
      physical_equal(resolution.site, expected) &&
      resolution.requirement_index == i &&
      resolution.value is Milliseconds(n) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    return (n, Some(resolution))
  }
  raise OperationScalarStop(ForeignOwner(occurrence))
}
