///|
pub(all) enum GraphEqualityRule {
  AdmitOperands
  CompareCanonicalGraphs
  RequireComparisonResources
} derive(Eq, Debug)

///|
pub(all) enum GraphComparisonResource {
  ComparisonWork
  RetainedComparisonState
  InputAndTemporaryBytes
} derive(Eq, Debug)

///|
/// Exact operand occurrences survive self-comparison. This is an execution
/// requirement, not a completed comparison or backend resource admission.
pub struct GraphEqualityCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @graph.CheckedEquality
  rule : GraphEqualityRule
  policy : @policy.Policy
}

///|
pub fn graph_comparison_resource_count(check : GraphEqualityCheck) -> Int {
  if check.rule == RequireComparisonResources {
    3
  } else {
    0
  }
}

///|
pub fn graph_comparison_resource_at(
  check : GraphEqualityCheck,
  index : Int,
) -> GraphComparisonResource? {
  if check.rule != RequireComparisonResources {
    return None
  }
  graph_comparison_resource(index)
}

///|
fn graph_comparison_resource(index : Int) -> GraphComparisonResource? {
  match index {
    0 => Some(ComparisonWork)
    1 => Some(RetainedComparisonState)
    2 => Some(InputAndTemporaryBytes)
    _ => None
  }
}

///|
fn graph_equality_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.EqualityRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    AdmitBothGraphs => AdmitOperands
    CompareTypedCanonicalGraphs => CompareCanonicalGraphs
    ResolveComparisonResources => RequireComparisonResources
    ResolveSgaProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphEquality(right~, checked=operation) &&
    step.input is Some(left) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.equality_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.role != @pipeline.Left ||
    l.target != left ||
    r.role != @pipeline.Right ||
    r.target != right {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      GraphEqualityExecution({
        site,
        step,
        left,
        right,
        operation,
        rule,
        policy,
      }),
    ),
  )
}
