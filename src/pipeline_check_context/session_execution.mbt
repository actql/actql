///|
pub(all) enum SessionExecutionRule {
  AssignSessionBoundaries
  DeriveSessionIdentity
} derive(Eq, Debug)

///|
/// Future checks owned by one session occurrence. Neither is an observed
/// identity, a successful arithmetic check, nor a resource bound.
pub struct SessionExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @event.CheckedEvent
  gap_ms : Int64
  gap_resolution : OperationScalarResolution?
  rule : SessionExecutionRule
}

///|
fn session_execution_check(
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.EventRequirement(pending) &&
    (pending == @event.SessionArithmetic || pending == @event.SessionIdentity) else {
    return (Ok(None), 0)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Event(operation) &&
    @event.options(operation) is Session(spec) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @event.pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    entries.get(occurrence) is Some(expected) &&
    physical_equal(site, expected) else {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let budget = { remaining: max_work, }
  let result : Result[OperationExecutionCheck?, OperationResolutionIndexIssue] = try {
    let (gap_ms, gap_resolution) = session_gap_resolution(
      @event.session_gap(spec),
      site,
      occurrence,
      entries,
      states,
      budget,
    )
    Ok(
      Some(
        SessionExecution({
          site,
          step,
          input,
          operation,
          gap_ms,
          gap_resolution,
          rule: if pending == @event.SessionArithmetic {
            AssignSessionBoundaries
          } else {
            DeriveSessionIdentity
          },
        }),
      ),
    )
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(_) => Err(ForeignOccurrence(occurrence))
  }
  (result, max_work - budget.remaining)
}

///|
fn session_gap_resolution(
  gap : @window.Milliseconds,
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  budget : OperationScalarBudget,
) -> (Int64, OperationScalarResolution?) raise OperationScalarStop {
  scalar_spend(budget, 1)
  guard gap is @window.Parameter(name, domain=@window.PositiveMilliseconds, ..) else {
    guard gap is @window.Literal(n) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    return (n, None)
  }
  let start = occurrence - site.index
  let mut found : OperationScalarResolution? = None
  for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
    scalar_spend(budget, 1)
    let index = start + slot
    guard entries.get(index) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      expected.step == site.step &&
      physical_equal(expected.pipeline, site.pipeline) &&
      physical_equal(expected.obligations, site.obligations) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    guard expected.requirement is @pipeline.EventRequirement(BindGap(candidate)) else {
      continue
    }
    scalar_spend(budget, name.length())
    scalar_spend(budget, candidate.length())
    if candidate != name {
      continue
    }
    guard found is None &&
      states.get(index) is Some(Resolved(Scalar(resolution))) &&
      physical_equal(resolution.site, expected) &&
      resolution.requirement_index == index &&
      resolution.value is Milliseconds(_) else {
      raise OperationScalarStop(ForeignOwner(occurrence))
    }
    found = Some(resolution)
  }
  guard found is Some(resolution) && resolution.value is Milliseconds(n) else {
    raise OperationScalarStop(ForeignOwner(occurrence))
  }
  (n, Some(resolution))
}
