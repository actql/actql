///|
// Share the existing Group rule selection between bound compilation and
// prebinding authoring. The caller retains the original group/validation
// occurrence. This selection is not an input observation or enforcement ACK.
fn select_group_execution_rule(
  group : @relation.CheckedGroup,
  index : Int,
  kind : @relation.ValidationKind,
  step : Int,
) -> Result[GroupExecutionRule?, OperationResolutionIndexIssue] {
  if kind is @relation.GroupPartitioning {
    return Ok(Some(PartitionGroups))
  }
  if !(kind is @relation.AggregateDemand ||
    kind is @relation.AggregateEnvelope ||
    kind is @relation.StatisticalAggregateLaw) {
    return Ok(None)
  }
  guard @relation.aggregate_for_validation(group, index) is Some(call) else {
    return Err(ForeignOccurrence(step))
  }
  if kind is @relation.StatisticalAggregateLaw {
    let law = match @relation.aggregate_function(call) {
      PercentileCont => PercentileInterpolation
      VarPop => PopulationVariance
      VarSamp => SampleVariance
      StddevPop => PopulationStandardDeviation
      StddevSamp => SampleStandardDeviation
      _ => return Err(ForeignOccurrence(step))
    }
    return Ok(Some(EnforceStatisticalLaw(call, law)))
  }
  if kind is @relation.AggregateEnvelope {
    // Collection-producing calls need their separately selected resource
    // limits; the ordinary result contract cannot stand in for those limits.
    return match @relation.aggregate_function(call) {
      ArrayAgg | StringAgg => Ok(None)
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
      | StddevSamp => Ok(Some(ValidateResultContract(call)))
    }
  }
  Ok(Some(EvaluateAggregate(call)))
}
