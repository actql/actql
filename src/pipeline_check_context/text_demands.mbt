///|
/// An already evaluated test in the owning site's stage/producer visit.
/// Slot indices are local coordinates, not Fragment roots or semantic IDs.
pub struct TextDemandTest {
  slot : Int
  expression : @typing.TypedExpression
  node_index : Int
  kind : @typing.DemandTestKind
}

///|
/// Compose the owning aggregate filter with expression-local demand, without
/// evaluating either. No caller-supplied filter or demand list is accepted.
/// The cap includes the filter prefix and is checked before allocating tests.
pub fn text_bound_demand_tests(
  v : TextBoundResolution,
  max_tests~ : Int,
) -> Result[Array[TextDemandTest], @typing.DemandIssue] {
  if max_tests < 0 {
    return Err(@typing.InvalidLimits)
  }
  let requirement = validation_site_requirement(v.site)
  let prefix = if requirement.filter is Some(_) { 1 } else { 0 }
  if prefix > max_tests {
    return Err(@typing.BudgetExceeded)
  }
  let conditions = match
    @typing.demand_tests(
      v.demands,
      requirement.obligation.node_index,
      max_tests=max_tests - prefix,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let result = []
  if requirement.filter is Some(filter) {
    result.push({
      slot: filter.slot,
      expression: filter.expression,
      node_index: 0,
      kind: @typing.IsTrue,
    })
  }
  for condition in conditions {
    result.push({
      slot: requirement.slot,
      expression: requirement.expression,
      node_index: condition.node_index,
      kind: condition.kind,
    })
  }
  Ok(result)
}
