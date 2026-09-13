///|
pub(all) enum AsOfExecutionRule {
  AdmitAsOfClocksAndDistances
  ValidateAsOfLeftIdentity
  SelectAsOfMatch
  OrderAsOfOutput
  ValidateAsOfKey(@schema.Side, @evidence.KeyObligation)
} derive(Eq, Debug)

///|
/// Owned future checks, not completed matching or backend conformance.
/// The retained operation owns identity, correlation and tie-break tuples.
pub struct AsOfExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @join.CheckedAsOf
  left_time : @schema.FieldName
  right_time : @schema.FieldName
  left_timestamp : Bool
  right_timestamp : Bool
  output_order : @pipeline.LogicalOrder
  key : @evidence.KeyedRelation?
  rule : AsOfExecutionRule
}

///|
fn asof_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.AsOfRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateAsOfValues => AdmitAsOfClocksAndDistances
    StableIdentity(@schema.Left) => ValidateAsOfLeftIdentity
    RejectAsOfTies => SelectAsOfMatch
    ResolveAsOfOrder => OrderAsOfOutput
    ValidateAsOfKey(side, obligation) => ValidateAsOfKey(side, obligation)
    _ => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.AsOfJoin(right~, checked=operation) &&
    step.input is Some(left) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @join.asof_pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.logical_order(site.pipeline, @pipeline.Step(site.step))
    is Some(output_order) else {
    return Err(ForeignOccurrence(site.step))
  }
  let l = @pipeline.input_occurrence_at(step, 0).unwrap()
  let key = match rule {
    ValidateAsOfKey(side, _) => {
      guard @join.asof_key_completion(operation, side) is Some(key) else {
        return Err(ForeignOccurrence(site.step))
      }
      Some(key)
    }
    _ => None
  }
  let r = @pipeline.input_occurrence_at(step, 1).unwrap()
  if l.role != @pipeline.Left ||
    l.target != left ||
    r.role != @pipeline.Right ||
    r.target != right {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      AsOfExecution({
        site,
        step,
        left,
        right,
        operation,
        left_time: @join.asof_time(operation, @schema.Left),
        right_time: @join.asof_time(operation, @schema.Right),
        left_timestamp: @join.asof_uses_timestamp(operation, @schema.Left),
        right_timestamp: @join.asof_uses_timestamp(operation, @schema.Right),
        output_order,
        key,
        rule,
      }),
    ),
  )
}
