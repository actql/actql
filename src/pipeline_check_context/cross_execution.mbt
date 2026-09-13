///|
pub(all) enum CrossJoinRowsRule {
  CheckProductArithmetic
  PreserveLeftMajorOrder
  RequireExactlyOneRightRow
} derive(Eq, Debug)

///|
/// A missing cross-join identity is retained as unknown, not invented and not
/// the mandatory operand identity required specifically by full join.
pub struct CrossJoinIdentityCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  side : @schema.Side
  input : @pipeline.Target
  key : @evidence.KeyedRelation?
}

///|
/// Count evidence is conditional and may be unknown. Neither a Host ceiling
/// nor an authored singleton assertion is a measurement of the actual input.
pub struct CrossJoinRowsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @join.CheckedCrossJoin
  rule : CrossJoinRowsRule
  output_limit : @step_bounds.JoinLimit
  left_count : @pipeline.RowCount?
  right_count : @pipeline.RowCount?
  output_count : @pipeline.RowCount?
  left_order : @pipeline.LogicalOrder?
  right_order : @pipeline.LogicalOrder?
}

///|
fn cross_join_execution_check(
  site : OperationRequirementSite,
  output_limit : @step_bounds.JoinLimit,
) -> Result[CrossJoinRowsCheck, OperationResolutionIndexIssue] {
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.CrossJoin(right~, checked=operation) &&
    step.input is Some(left) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.input_occurrence_count(step) != 2 {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.target != left ||
    l.role != @pipeline.Left ||
    r.target != right ||
    r.role != @pipeline.Right {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = match site.requirement {
    @pipeline.CrossJoinRequirement(ResolveProductBound) =>
      CheckProductArithmetic
    @pipeline.CrossJoinRequirement(PreserveLeftMajorProductOrder) =>
      PreserveLeftMajorOrder
    @pipeline.CrossJoinRequirement(ValidateExactlyOneRightRow) => {
      if !@join.cross_requires_one_right_row(operation) {
        return Err(ForeignOccurrence(site.step))
      }
      RequireExactlyOneRightRow
    }
    _ => return Err(ForeignOccurrence(site.step))
  }
  Ok({
    site,
    step,
    left,
    right,
    operation,
    rule,
    output_limit,
    left_count: @pipeline.row_count(site.pipeline, left),
    right_count: @pipeline.row_count(site.pipeline, right),
    output_count: @pipeline.row_count(site.pipeline, @pipeline.Step(site.step)),
    left_order: @pipeline.logical_order(site.pipeline, left),
    right_order: @pipeline.logical_order(site.pipeline, right),
  })
}
