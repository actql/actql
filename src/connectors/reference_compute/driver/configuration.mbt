///|
pub(all) struct NumericComputeConfiguration {
  sequences : Array[@execution.CompletionPreparation]
  limits : @numeric.NumericExecutionLimits
  expressions : @lower.ExpressionLimits
  milliseconds : Int64?
  max_work : Int
}

///|
pub fn configure_numeric_compute(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  configuration : NumericComputeConfiguration,
) -> Result[NumericComputeContribution, @strategy.RunIssue] {
  // Validate the estimate before constructing an owned execution channel.
  if configuration.max_work < 1 ||
    (configuration.milliseconds is Some(value) && value < 0L) {
    return Err(numeric_dispatch_issue(Limit))
  }
  let installed = match
    prepare_numeric_dispatch_module(
      driver,
      registry,
      registration,
      configuration.sequences,
      configuration.limits,
      configuration.expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(numeric_dispatch_issue(issue))
  }
  prepare_numeric_contribution(
    installed,
    configuration.milliseconds,
    configuration.max_work,
  )
}
