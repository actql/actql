///|
/// Bounded temporal matching semantics, not a proof of physical search work or
/// completion of the separate per-key and total-output limit requirements.
pub struct SequenceMatchCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedSequence
  within_ms : Int64
  within_resolution : OperationScalarResolution?
}

///|
fn sequence_match_check(
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.SequenceRequirement(BoundedMatchSearch) else {
    return (Ok(None), 0)
  }
  if max_work < 0 {
    return (Err(BudgetExceeded), 0)
  }
  guard entries.get(occurrence) is Some(expected) &&
    physical_equal(site, expected) &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Sequence(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) ==
    @pipeline.SequenceSemantics &&
    @relation.sequence_obligation_at(operation, site.index) ==
    Some(@relation.BoundedMatchSearch) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let budget = { remaining: max_work, }
  let result : Result[OperationExecutionCheck?, OperationResolutionIndexIssue] = try {
    let mut resolution = None
    let within_ms = match @relation.sequence_within(operation) {
      Literal(value) => value
      Parameter(name, ..) => {
        let start = occurrence - site.index
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
          if expected.requirement
            is @pipeline.SequenceRequirement(BindWithin(candidate)) {
            scalar_spend(budget, name.length())
            scalar_spend(budget, candidate.length())
            guard candidate == name &&
              resolution is None &&
              states.get(index) is Some(Resolved(Scalar(value))) &&
              value.requirement_index == index &&
              physical_equal(value.site, expected) &&
              value.value is Milliseconds(n) &&
              n > 0L &&
              n <= 9007199254740991L else {
              raise OperationScalarStop(ForeignOwner(occurrence))
            }
            resolution = Some(value)
          }
        }
        guard resolution is Some(value) && value.value is Milliseconds(n) else {
          raise OperationScalarStop(ForeignOwner(occurrence))
        }
        n
      }
    }
    Ok(
      Some(
        SequenceMatch({
          site,
          step,
          input,
          operation,
          within_ms,
          within_resolution: resolution,
        }),
      ),
    )
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(_) => Err(ForeignOccurrence(occurrence))
  }
  (result, max_work - budget.remaining)
}
