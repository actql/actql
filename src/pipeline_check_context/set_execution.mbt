///|
pub(all) enum SetRowsRule {
  AdmitBothInputs
  CompareCompleteTypedRows
  PreserveEarliestLeftOccurrences
  BoundOutputByLeftInput
  RetainIdentityAndCompleteness
  RequireComparisonResources
} derive(Eq, Debug)

///|
/// Semantics over exact captured operand occurrences. These checks neither
/// execute row comparison nor claim a backend's resource contract is installed.
pub struct SetRowsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @set.CheckedSet
  rule : SetRowsRule
  policy : @policy.Policy
  left_order : @pipeline.LogicalOrder?
}

///|
pub(all) enum SetComparisonResource {
  ComparisonWork
  RetainedComparisonState
  InputAndTemporaryBytes
} derive(Eq, Debug)

///|
/// The selected physical implementation must bind enforceable finite limits for
/// every category before execution. Logical output row limits do not suffice.
pub fn set_resource_requirement_count(check : SetRowsCheck) -> Int {
  if check.rule == RequireComparisonResources {
    3
  } else {
    0
  }
}

///|
pub fn set_resource_requirement_at(
  check : SetRowsCheck,
  index : Int,
) -> SetComparisonResource? {
  if check.rule != RequireComparisonResources {
    return None
  }
  match index {
    0 => Some(ComparisonWork)
    1 => Some(RetainedComparisonState)
    2 => Some(InputAndTemporaryBytes)
    _ => None
  }
}

///|
fn set_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  let rule : SetRowsRule = match site.requirement {
    @pipeline.SetRequirement(ValidateInputRows) => AdmitBothInputs
    @pipeline.SetRequirement(CompareCompleteTypedRows) =>
      CompareCompleteTypedRows
    @pipeline.SetRequirement(PreserveEarliestLeftOccurrences) =>
      PreserveEarliestLeftOccurrences
    @pipeline.SetRequirement(BoundOutputByLeftInput) => BoundOutputByLeftInput
    @pipeline.SetRequirement(ResolveIdentityAndCompleteness) =>
      RetainIdentityAndCompleteness
    @pipeline.SetRequirement(ResolveComparisonResources) =>
      RequireComparisonResources
    _ => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Set(right~, checked=operation) &&
    step.input is Some(left) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @pipeline.input_occurrence_count(step) != 2 {
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
  Ok(
    Some(
      SetRows({
        site,
        step,
        left,
        right,
        operation,
        rule,
        policy,
        left_order: @pipeline.logical_order(site.pipeline, left),
      }),
    ),
  )
}
