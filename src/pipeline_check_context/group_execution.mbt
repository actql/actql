///|
pub enum StatisticalLaw {
  PercentileInterpolation
  PopulationVariance
  SampleVariance
  PopulationStandardDeviation
  SampleStandardDeviation
}

///|
pub enum GroupExecutionRule {
  PartitionGroups
  EvaluateAggregate(@relation.CheckedAggregate)
  ValidateResultContract(@relation.CheckedAggregate)
  EnforceArrayItems(GroupArrayLimit)
  EnforceStringBytes(GroupStringLimit)
  CaptureNumericObservation(NumericSlot)
  EnforceStatisticalLaw(@relation.CheckedAggregate, StatisticalLaw)
}

///|
pub struct GroupExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  group : @relation.CheckedGroup
  rule : GroupExecutionRule
}

///|
fn group_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) else {
    return Ok(None)
  }
  guard pending.kind is @relation.GroupPartitioning ||
    pending.kind is @relation.AggregateDemand ||
    pending.kind is @relation.AggregateEnvelope ||
    pending.kind is @relation.StatisticalAggregateLaw else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(ForeignOccurrence(site.step))
  }
  // Window grouping already owns its checked boundary prefix. Keep the actual
  // step kind so consumers cannot reinterpret it as an ordinary group.
  let operation = match step.operation {
    @pipeline.Unary(op) | @pipeline.WindowGroup(op) => op
    _ => return Ok(None)
  }
  guard @relation.operation(operation) == @relation.Group else {
    return Ok(None)
  }
  guard @relation.group(operation) is Some(group) && step.input is Some(input) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body ||
    @pipeline.input_occurrence_count(step) != 1 {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  guard @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return Err(ForeignOccurrence(site.step))
  }
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = if pending.kind is @relation.GroupPartitioning {
    PartitionGroups
  } else {
    guard @relation.aggregate_for_validation(group, site.index) is Some(call) else {
      return Err(ForeignOccurrence(site.step))
    }
    if pending.kind is @relation.StatisticalAggregateLaw {
      let law = match @relation.aggregate_function(call) {
        PercentileCont => PercentileInterpolation
        VarPop => PopulationVariance
        VarSamp => SampleVariance
        StddevPop => PopulationStandardDeviation
        StddevSamp => SampleStandardDeviation
        _ => return Err(ForeignOccurrence(site.step))
      }
      EnforceStatisticalLaw(call, law)
    } else if pending.kind is @relation.AggregateEnvelope {
      // Collection-producing aggregates need separately selected resource
      // limits. Other calls retain their exact output contract, including
      // decimal precision and inherited bounds on selected values.
      match @relation.aggregate_function(call) {
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
    } else {
      EvaluateAggregate(call)
    }
  }
  Ok(Some(GroupExecution({ site, step, input, operation, group, rule, })))
}
