///|
pub(all) enum GraphMeanRule {
  AdmitMeanSamples
  CompareMeanSupport
  CloseMeanEndpoints
  CheckMeanLabels
  ApplyMeanProperties
  RoundMeanOnce
  ValidateMeanFiniteResults
  OrderMeanIdentities
  PreserveMeanDependencies
  RequireMeanResources
} derive(Eq, Debug)

///|
pub(all) enum GraphMeanResource {
  SampleWork
  ExactArithmeticWork
  ValueAndTemporaryBytes
  RetainedMeanState
} derive(Eq, Debug)

///|
pub struct GraphMeanCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @graph.CheckedMean
  rule : GraphMeanRule
  policy : @policy.Policy
}

///|
/// Resource contracts cover the whole sample list, not a fresh budget per sample.
pub fn graph_mean_resource_count(check : GraphMeanCheck) -> Int {
  if check.rule == RequireMeanResources {
    4
  } else {
    0
  }
}

///|
pub fn graph_mean_resource_at(
  check : GraphMeanCheck,
  index : Int,
) -> GraphMeanResource? {
  if check.rule != RequireMeanResources {
    return None
  }
  match index {
    0 => Some(SampleWork)
    1 => Some(ExactArithmeticWork)
    2 => Some(ValueAndTemporaryBytes)
    3 => Some(RetainedMeanState)
    _ => None
  }
}

///|
pub fn graph_mean_sample_count(check : GraphMeanCheck) -> Int {
  @graph.mean_sample_count(@graph.mean_options(check.operation))
}

///|
/// Positional samples retain repetitions and zero weights. The immutable
/// checked pipeline established Sample(i) and its exact target at construction.
pub fn graph_mean_sample_at(
  check : GraphMeanCheck,
  index : Int,
) -> (@pipeline.InputOccurrence, Double)? {
  guard @pipeline.input_occurrence_at(check.step, index) is Some(input) &&
    @graph.mean_weight_at(@graph.mean_options(check.operation), index)
    is Some(weight) else {
    return None
  }
  Some((input, weight))
}

///|
fn graph_mean_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.MeanRequirement(pending) else {
    return Ok(None)
  }
  let rule : GraphMeanRule = match pending {
    AdmitEveryMeanSample => AdmitMeanSamples
    CompareExactRationalSupport => CompareMeanSupport
    RetainSupportedNodesBeforeEdges => CloseMeanEndpoints
    RequirePositiveWeightLabelAgreement => CheckMeanLabels
    ApplyEveryMeanPropertyPolicy => ApplyMeanProperties
    RoundExactWeightedMeansOnce => RoundMeanOnce
    RejectNonfiniteMeanResults => ValidateMeanFiniteResults
    CanonicalMeanIdentityOrder => OrderMeanIdentities
    PreserveMeanObservationAndPolicy => PreserveMeanDependencies
    ResolveMeanResources => RequireMeanResources
    ResolveMeanProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphMean(operation) &&
    step.input is None &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.mean_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    @graph.mean_sample_count(@graph.mean_options(operation)) else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(GraphMeanExecution({ site, step, operation, rule, policy, })))
}
