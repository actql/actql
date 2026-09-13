///|
/// Compiler selection to journal, not completed input validation.
pub struct AsOfKeyCompletion {
  requirement_index : Int
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @join.CheckedAsOf
  side : @schema.Side
  input : @pipeline.Target
  key : @evidence.KeyedRelation
}

///|
fn asof_key_completion(
  site : OperationRequirementSite,
  requirement_index : Int,
) -> Result[AsOfKeyCompletion?, OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.AsOfRequirement(JournalAsOfKeyCompletion(side)) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.AsOfJoin(right~, checked=operation) &&
    step.input is Some(left) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @join.asof_pending_validation_at(operation, site.index) ==
    Some(JournalAsOfKeyCompletion(side)) &&
    @join.asof_key_completion(operation, side) is Some(key) else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some({
      requirement_index,
      site,
      step,
      operation,
      side,
      input: if side == @schema.Left {
        left
      } else {
        right
      },
      key,
    }),
  )
}
