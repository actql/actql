///|
/// Exact selected policy scopes for one analytic operation. These ceilings
/// impose atomic enforcement; they do not prove observed sizes or heap use.
pub struct AnalyticEnvelopeCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  analytic : @relation.CheckedAnalytic
  policy : @policy.Policy
  input_wire_bytes : @policy.Ceiling
  output_wire_bytes : @policy.Ceiling
  partition_wire_bytes : @policy.Ceiling
  frame_memberships : @policy.Ceiling
  output_rows : @policy.Ceiling
}

///|
fn analytic_envelope_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    pending.kind is @relation.AnalyticEnvelope else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    @relation.analytic(operation) is Some(analytic) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return Err(ForeignOccurrence(site.step))
  }
  // Absence is unresolved, not a default ceiling or proof of zero usage.
  guard @policy.ceiling(policy, "max_analytic_input_wire_bytes")
    is Some(input_wire_bytes) &&
    @policy.ceiling(policy, "max_analytic_output_wire_bytes")
    is Some(output_wire_bytes) &&
    @policy.ceiling(policy, "max_analytic_partition_wire_bytes")
    is Some(partition_wire_bytes) &&
    @policy.ceiling(policy, "max_analytic_frame_memberships")
    is Some(frame_memberships) &&
    @policy.ceiling(policy, "max_relation_output_rows") is Some(output_rows) else {
    return Ok(None)
  }
  Ok(
    Some(
      AnalyticEnvelope({
        site,
        step,
        input,
        operation,
        analytic,
        policy,
        input_wire_bytes,
        output_wire_bytes,
        partition_wire_bytes,
        frame_memberships,
        output_rows,
      }),
    ),
  )
}
