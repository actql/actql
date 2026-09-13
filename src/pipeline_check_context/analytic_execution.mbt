///|
pub enum AnalyticExecutionRule {
  PartitionAuthoredPeers
  EvaluateCallDemands
  EvaluateAggregate(@relation.AnalyticCall)
  ValidateResultContract(@relation.AnalyticCall)
  EnforceStatisticalLaw(@relation.AnalyticCall, StatisticalLaw)
  EnforceStringBytes(@relation.AnalyticCall, GroupStringLimit)
}

///|
/// Call demand is evaluated in partition/source-position/output-name order.
/// Peer keys are authored keys, never the completed position-order suffix.
pub struct AnalyticExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  analytic : @relation.CheckedAnalytic
  rule : AnalyticExecutionRule
}

///|
fn analytic_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    (
      pending.kind is @relation.AnalyticPeerOrder ||
      pending.kind is @relation.AnalyticFrameDemand ||
      pending.kind is @relation.AggregateDemand ||
      pending.kind is @relation.AggregateEnvelope ||
      pending.kind is @relation.StatisticalAggregateLaw
    ) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    @relation.analytic(operation) is Some(analytic) else {
    return Ok(None)
  }
  guard step.input is Some(input) &&
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
  let rule = if pending.kind is @relation.AnalyticPeerOrder {
    AnalyticExecutionRule::PartitionAuthoredPeers
  } else if pending.kind is @relation.AnalyticFrameDemand {
    EvaluateCallDemands
  } else {
    guard @relation.analytic_call_for_validation(analytic, site.index)
      is Some(call) &&
      call.function is @relation.Aggregate(aggregate) else {
      return Err(ForeignOccurrence(site.step))
    }
    if pending.kind is @relation.AggregateDemand {
      EvaluateAggregate(call)
    } else if pending.kind is @relation.StatisticalAggregateLaw {
      let law = match @relation.aggregate_function(aggregate) {
        PercentileCont => PercentileInterpolation
        VarPop => PopulationVariance
        VarSamp => SampleVariance
        StddevPop => PopulationStandardDeviation
        StddevSamp => SampleStandardDeviation
        _ => return Err(ForeignOccurrence(site.step))
      }
      EnforceStatisticalLaw(call, law)
    } else {
      match @relation.aggregate_function(aggregate) {
        // Per-frame collection bounds require separate selection. A scalar
        // result contract is not a substitute for array/string resource caps.
        ArrayAgg | StringAgg => return Ok(None)
        Count
        | CountIf
        | Sum
        | Avg
        | Min
        | Max
        | First
        | Last
        | PercentileDisc
        | PercentileCont
        | VarPop
        | VarSamp
        | StddevPop
        | StddevSamp => ValidateResultContract(call)
      }
    }
  }
  Ok(Some(AnalyticExecution({ site, step, input, operation, analytic, rule, })))
}
