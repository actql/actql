///|
/// Rebuild-time bundle configuration. The connector validates the exact checked
/// sequences and owns the interpretation of execution and measurement limits.
pub(all) struct LocalComputeConfiguration {
  sequences : Array[@execution.GeneratedSequence]
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  max_work : Int
}

///|
pub fn configure_local_compute(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  configuration : LocalComputeConfiguration,
) -> Result[LocalDispatchModule, LocalDispatchIssue] {
  prepare_local_dispatch_module(
    driver,
    registry,
    registration,
    configuration.sequences,
    configuration.execution,
    configuration.measurement,
    configuration.max_work,
  ).map_err(_ => Configuration(InvalidLimits))
}
