///|
pub(all) enum QueryTimeRequirementIssue {
  Slots(@pipeline.ExpressionSlotIssue)
  WorkLimit
}

///|
/// Inspect original checked expression slots, never JSON keys or source text.
/// This declares demand; it cannot sample, bind a Run, or authorize execution.
pub fn bound_prepared_requires_query_time(
  value : BoundPrepared,
  max_work~ : Int,
  max_expressions~ : Int,
) -> Result[Bool, QueryTimeRequirementIssue] {
  bound_prepared_query_time_requirement_usage(
    value,
    max_work~,
    max_expressions~,
  ).map(result => result.0)
}

///|
/// Return actual semantic work so an enclosing owner carries one finite
/// planning budget across tasks rather than resetting it for each request.
pub fn bound_prepared_query_time_requirement_usage(
  value : BoundPrepared,
  max_work~ : Int,
  max_expressions~ : Int,
) -> Result[(Bool, Int), QueryTimeRequirementIssue] {
  let slots = match
    @pipeline.collect_expression_slots(
      value.prepared.owner,
      max_work~,
      max_slots=max_expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Slots(issue))
  }
  let mut remaining = max_work - @pipeline.expression_slots_work(slots)
  let mut required = false
  for index in 0..<@pipeline.expression_slot_count(slots) {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    required = required ||
      @typing.requires_query_time(
        @pipeline.expression_slot_at(slots, index).unwrap().expression,
      )
  }
  Ok((required, max_work - remaining))
}
