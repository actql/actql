///|
pub(all) enum GraphDiagnosticRule {
  RequireDiagnosticResources
  EnforceDiagnosticRows
} derive(Eq, Debug)

///|
pub struct GraphDiagnosticCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  rule : GraphDiagnosticRule
  policy : @policy.Policy
  output_rows : @policy.Ceiling
}

///|
fn graph_diagnostic_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  let rule = match site.requirement {
    @pipeline.DiagnosticRequirement(pending) =>
      match pending {
        ResolveDiagnosticResources => RequireDiagnosticResources
        EnforceDiagnosticRelationRows => EnforceDiagnosticRows
        AdmitDiagnosticGraph | BindDiagnosticThreshold(_) => return Ok(None)
      }
    @pipeline.ComponentsRequirement(pending) =>
      match pending {
        EnforceComponentInputNodes | ResolveComponentResources =>
          RequireDiagnosticResources
        EnforceComponentOutputRows | EnforceComponentAuthorGuard =>
          EnforceDiagnosticRows
        AdmitComponentGraph | BindComponentAuthorGuard(_) => return Ok(None)
      }
    _ => return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.input is Some(input) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0)
    is Some({ role: @pipeline.Primary, target, }) &&
    target == input else {
    return Err(ForeignOccurrence(site.step))
  }
  let exact = match (step.operation, site.requirement) {
    (@pipeline.GraphBounds(operation), @pipeline.DiagnosticRequirement(pending)) =>
      @pipeline.operation_obligations_graph_bounds(site.obligations)
      is Some(owner) &&
      physical_equal(owner, operation) &&
      @graph.graph_bounds_pending_at(operation, site.index) == Some(pending)
    (@pipeline.GraphDegree(operation), @pipeline.DiagnosticRequirement(pending)) =>
      @pipeline.operation_obligations_graph_degree(site.obligations)
      is Some(owner) &&
      physical_equal(owner, operation) &&
      @graph.degree_pending_at(operation, site.index) == Some(pending)
    (
      @pipeline.GraphComponents(operation),
      @pipeline.ComponentsRequirement(pending),
    ) =>
      @pipeline.operation_obligations_graph_components(site.obligations)
      is Some(owner) &&
      physical_equal(owner, operation) &&
      @graph.components_pending_at(operation, site.index) == Some(pending)
    _ => false
  }
  if !exact {
    return Err(ForeignOccurrence(site.step))
  }
  guard @policy.ceiling(policy, "max_relation_output_rows") is Some(output_rows) else {
    return Ok(None)
  }
  Ok(
    Some(
      GraphDiagnosticExecution({ site, step, input, rule, policy, output_rows, }),
    ),
  )
}
